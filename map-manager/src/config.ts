import path from "node:path";

export const DATA_DIR = path.resolve(process.env.DATA_DIR ?? path.join(process.cwd(), "data"));
export const RASTER_DIR = path.join(DATA_DIR, process.env.RASTER_DIRNAME ?? "raster");
export const DTM_DIR = path.join(DATA_DIR, process.env.DTM_DIRNAME ?? "dtm");
export const MAPSETS_DIR = path.join(DATA_DIR, process.env.MAPSETS_DIRNAME ?? "mapsets");
export const ACTIVE_DATASET_STATE = path.join(
  DATA_DIR,
  process.env.ACTIVE_DATASET_STATE_FILENAME ?? "active-dataset.json"
);
export const PORT = Number(process.env.PORT ?? 8002);
