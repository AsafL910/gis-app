import { spawn } from "node:child_process";
import { promises as fs } from "node:fs";
import path from "node:path";

import { ACTIVE_DATASET_STATE, DATA_DIR, DTM_DIR, MAPSETS_DIR, RASTER_DIR } from "../config.js";
import type { CatalogFile, MapSetManifest } from "../types.js";


export async function ensureDataDirs(): Promise<void> {
  await Promise.all([
    fs.mkdir(RASTER_DIR, { recursive: true }),
    fs.mkdir(DTM_DIR, { recursive: true }),
    fs.mkdir(MAPSETS_DIR, { recursive: true })
  ]);
}

export function normalizeRelativePath(filePath: string): string {
  return filePath.split(path.sep).join("/");
}

export function relativeToData(filePath: string): string {
  return normalizeRelativePath(path.relative(DATA_DIR, filePath));
}

export async function listFiles(directory: string, suffixes: Set<string>): Promise<CatalogFile[]> {
  const rows: CatalogFile[] = [];
  await walkFiles(directory, async (filePath, stat) => {
    const ext = path.extname(filePath).toLowerCase();
    if (!suffixes.has(ext)) {
      return;
    }
    rows.push({
      name: path.basename(filePath),
      path: relativeToData(filePath),
      size: Number(stat.size)
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

export async function readMapsetManifests(): Promise<MapSetManifest[]> {
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

export async function readActiveDataset(): Promise<string | null> {
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

export async function writeActiveDataset(relativePath: string): Promise<void> {
  await fs.writeFile(
    ACTIVE_DATASET_STATE,
    JSON.stringify({ path: relativePath }, null, 2),
    "utf8"
  );
}

export function sanitizeMapSetName(name: string): string {
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

export async function resolveRelativeInput(relativePath: string, allowedRoot: string): Promise<string> {
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

export async function runGdalBuildVrt(outputPath: string, sourcePaths: string[]): Promise<void> {
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
