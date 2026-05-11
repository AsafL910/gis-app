import { promises as fs } from "node:fs";
import { DATA_DIR, DTM_DIR, MAPSETS_DIR, RASTER_DIR } from "../config.js";
import type { MapSetCreateRequest, MapSetManifest } from "../types.js";
import {
  ensureDataDirs,
  readActiveDataset,
  readMapsetManifests,
  relativeToData,
  resolveRelativeInput,
  runGdalBuildVrt,
  sanitizeMapSetName,
  writeActiveDataset,
  listFiles
} from "./files.js";


export async function getCatalog() {
  await ensureDataDirs();
  return {
    rasters: await listFiles(RASTER_DIR, new Set([".tif", ".tiff", ".vrt"])),
    dtms: await listFiles(DTM_DIR, new Set([".tif", ".tiff", ".vrt"])),
    map_sets: await readMapsetManifests(),
    active_dataset: await readActiveDataset()
  };
}


export async function activateDtm(relativePath: string): Promise<string> {
  await resolveRelativeInput(relativePath, DATA_DIR);
  await writeActiveDataset(relativePath);
  return relativePath;
}


export async function createMapSet(request: MapSetCreateRequest) {
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
