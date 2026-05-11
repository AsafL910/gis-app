import { API_BASE, HEIGHT_API_BASE, MANAGEMENT_API_BASE } from "./constants";
import type {
  CatalogResponse,
  HighestPointResponse,
  LayersResponse,
  MapSetCreateResponse
} from "./types";


async function readJson<T>(response: Response): Promise<T> {
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }
  return response.json() as Promise<T>;
}


export async function fetchCatalog() {
  return readJson<CatalogResponse>(await fetch(`${MANAGEMENT_API_BASE}/catalog/`));
}


export async function fetchLayers() {
  return readJson<LayersResponse>(await fetch(`${API_BASE}/layers`));
}


export async function postActivateDtm(path: string) {
  return readJson<{ active_dataset: string; status: string }>(
    await fetch(`${MANAGEMENT_API_BASE}/activate-dtm/`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ path })
    })
  );
}


export async function postCreateMapSet(payload: {
  name: string;
  raster_files: string[];
  dtm_files: string[];
  activate_dtm: boolean;
}) {
  return readJson<MapSetCreateResponse>(
    await fetch(`${MANAGEMENT_API_BASE}/map-sets/`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    })
  );
}


export async function postHighestPoint(payload: {
  dataset_path: string | null;
  geojson: object;
}) {
  return readJson<HighestPointResponse>(
    await fetch(`${HEIGHT_API_BASE}/get-highest-point-geojson/`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    })
  );
}
