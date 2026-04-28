import express from "express";
import { promises as fs } from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";

type CatalogFile = {
  name: string;
  path: string;
  size: number;
};

type MapSetManifest = {
  name: string;
  manifest_path: string;
  raster_files: string[];
  dtm_files: string[];
  dtm_vrt: string | null;
};

type MapSetCreateRequest = {
  name: string;
  raster_files?: string[];
  dtm_files?: string[];
  activate_dtm?: boolean;
};

const app = express();
app.use(express.json({ limit: "2mb" }));

const DATA_DIR = path.resolve(process.env.DATA_DIR ?? path.join(process.cwd(), "data"));
const RASTER_DIR = path.join(DATA_DIR, process.env.RASTER_DIRNAME ?? "raster");
const DTM_DIR = path.join(DATA_DIR, process.env.DTM_DIRNAME ?? "dtm");
const MAPSETS_DIR = path.join(DATA_DIR, process.env.MAPSETS_DIRNAME ?? "mapsets");
const ACTIVE_DATASET_STATE = path.join(
  DATA_DIR,
  process.env.ACTIVE_DATASET_STATE_FILENAME ?? "active-dataset.json"
);
const PORT = Number(process.env.PORT ?? 8002);

async function ensureDataDirs(): Promise<void> {
  await Promise.all([
    fs.mkdir(RASTER_DIR, { recursive: true }),
    fs.mkdir(DTM_DIR, { recursive: true }),
    fs.mkdir(MAPSETS_DIR, { recursive: true })
  ]);
}

function normalizeRelativePath(filePath: string): string {
  return filePath.split(path.sep).join("/");
}

function relativeToData(filePath: string): string {
  return normalizeRelativePath(path.relative(DATA_DIR, filePath));
}

async function listFiles(directory: string, suffixes: Set<string>): Promise<CatalogFile[]> {
  const rows: CatalogFile[] = [];
  await walkFiles(directory, async (filePath, stat) => {
    const ext = path.extname(filePath).toLowerCase();
    if (!suffixes.has(ext)) {
      return;
    }
    rows.push({
      name: path.basename(filePath),
      path: relativeToData(filePath),
      size: stat.size
    });
  });
  rows.sort((a, b) => a.path.localeCompare(b.path));
  return rows;
}

async function walkFiles(
  directory: string,
  visitor: (filePath: string, stat: Awaited<ReturnType<typeof fs.stat>>) => Promise<void>
): Promise<void> {
  let entries;
  try {
    entries = await fs.readdir(directory, { withFileTypes: true });
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code === "ENOENT") {
      return;
    }
    throw error;
  }

  for (const entry of entries) {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      await walkFiles(fullPath, visitor);
      continue;
    }
    if (!entry.isFile()) {
      continue;
    }
    const stat = await fs.stat(fullPath);
    await visitor(fullPath, stat);
  }
}

async function readMapsetManifests(): Promise<MapSetManifest[]> {
  let entries;
  try {
    entries = await fs.readdir(MAPSETS_DIR, { withFileTypes: true });
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code === "ENOENT") {
      return [];
    }
    throw error;
  }

  const manifests: MapSetManifest[] = [];
  for (const entry of entries) {
    if (!entry.isFile() || path.extname(entry.name).toLowerCase() !== ".json") {
      continue;
    }
    const filePath = path.join(MAPSETS_DIR, entry.name);
    const payload = JSON.parse(await fs.readFile(filePath, "utf8")) as MapSetManifest;
    manifests.push(payload);
  }

  manifests.sort((a, b) => a.name.localeCompare(b.name));
  return manifests;
}

async function readActiveDataset(): Promise<string | null> {
  try {
    const payload = JSON.parse(await fs.readFile(ACTIVE_DATASET_STATE, "utf8")) as {
      path?: unknown;
    };
    return typeof payload.path === "string" && payload.path ? payload.path : null;
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code === "ENOENT") {
      return null;
    }
    throw error;
  }
}

async function writeActiveDataset(relativePath: string): Promise<void> {
  await fs.writeFile(
    ACTIVE_DATASET_STATE,
    JSON.stringify({ path: relativePath }, null, 2),
    "utf8"
  );
}

function sanitizeMapSetName(name: string): string {
  const safe = name
    .split("")
    .map((char) => (/[\w-]/.test(char) ? char : "-"))
    .join("")
    .replace(/^[-_]+|[-_]+$/g, "");
  if (!safe) {
    throw new Error("Map set name must contain at least one letter or digit");
  }
  return safe;
}

async function resolveRelativeInput(relativePath: string, allowedRoot: string): Promise<string> {
  const candidate = path.resolve(DATA_DIR, relativePath);
  const normalizedRoot = path.resolve(allowedRoot);
  const relativeToRoot = path.relative(normalizedRoot, candidate);
  if (relativeToRoot.startsWith("..") || path.isAbsolute(relativeToRoot)) {
    throw new Error(`Path is outside allowed root: ${relativePath}`);
  }

  let stat;
  try {
    stat = await fs.stat(candidate);
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code === "ENOENT") {
      throw new Error(`File not found: ${relativePath}`);
    }
    throw error;
  }
  if (!stat.isFile()) {
    throw new Error(`File not found: ${relativePath}`);
  }
  return candidate;
}

async function runGdalBuildVrt(outputPath: string, sourcePaths: string[]): Promise<void> {
  await fs.rm(outputPath, { force: true });
  await new Promise<void>((resolve, reject) => {
    const child = spawn("gdalbuildvrt", [outputPath, ...sourcePaths], {
      stdio: ["ignore", "pipe", "pipe"]
    });

    let stderr = "";
    child.stderr.on("data", (chunk: Buffer) => {
      stderr += chunk.toString("utf8");
    });

    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve();
        return;
      }
      reject(new Error(stderr.trim() || `gdalbuildvrt failed with exit code ${code}`));
    });
  });
}

async function activateDtm(relativePath: string): Promise<string> {
  await resolveRelativeInput(relativePath, DATA_DIR);
  await writeActiveDataset(relativePath);
  return relativePath;
}

async function createMapSet(request: MapSetCreateRequest) {
  await ensureDataDirs();

  const safeName = sanitizeMapSetName(request.name);
  const manifestPath = path.join(MAPSETS_DIR, `${safeName}.json`);
  const rasterFiles = request.raster_files ?? [];
  const dtmFiles = request.dtm_files ?? [];
  const activate = request.activate_dtm ?? true;

  const rasterSources = await Promise.all(
    rasterFiles.map((relativePath) => resolveRelativeInput(relativePath, RASTER_DIR))
  );
  const dtmSources = await Promise.all(
    dtmFiles.map((relativePath) => resolveRelativeInput(relativePath, DTM_DIR))
  );

  if (rasterSources.length === 0 && dtmSources.length === 0) {
    throw new Error("Select at least one raster or DTM file");
  }

  let dtmVrt: string | null = null;
  let activeDataset: string | null = null;

  if (dtmSources.length > 0) {
    const dtmVrtPath = path.join(MAPSETS_DIR, `${safeName}.dtm.vrt`);
    await runGdalBuildVrt(dtmVrtPath, dtmSources);
    dtmVrt = relativeToData(dtmVrtPath);

    if (activate) {
      activeDataset = await activateDtm(dtmVrt);
    }
  }

  const manifest: MapSetManifest = {
    name: safeName,
    manifest_path: relativeToData(manifestPath),
    raster_files: rasterSources.map(relativeToData),
    dtm_files: dtmSources.map(relativeToData),
    dtm_vrt: dtmVrt
  };

  await fs.writeFile(manifestPath, JSON.stringify(manifest, null, 2), "utf8");

  return {
    name: safeName,
    manifest_path: manifest.manifest_path,
    rasters: manifest.raster_files,
    dtm_vrt: manifest.dtm_vrt,
    active_dataset: activeDataset
  };
}

app.get("/catalog/", async (_request, response) => {
  try {
    await ensureDataDirs();
    response.json({
      rasters: await listFiles(RASTER_DIR, new Set([".tif", ".tiff", ".vrt"])),
      dtms: await listFiles(DTM_DIR, new Set([".tif", ".tiff", ".vrt"])),
      map_sets: await readMapsetManifests(),
      active_dataset: await readActiveDataset()
    });
  } catch (error) {
    response.status(500).json({ detail: (error as Error).message });
  }
});

app.post("/activate-dtm/", async (request, response) => {
  try {
    const relativePath = request.body?.path;
    if (typeof relativePath !== "string" || !relativePath) {
      throw new Error("Expected a non-empty 'path'");
    }
    const activeDataset = await activateDtm(relativePath);
    response.json({ active_dataset: activeDataset, status: "activated" });
  } catch (error) {
    response.status(400).json({ detail: (error as Error).message });
  }
});

app.post("/map-sets/", async (request, response) => {
  try {
    const result = await createMapSet(request.body as MapSetCreateRequest);
    response.json(result);
  } catch (error) {
    response.status(400).json({ detail: (error as Error).message });
  }
});

void ensureDataDirs().then(() => {
  app.listen(PORT, "0.0.0.0", () => {
    console.log(`Map manager listening on ${PORT}`);
  });
}).catch((error: Error) => {
  console.error("Failed to initialize map manager", error);
  process.exit(1);
});
