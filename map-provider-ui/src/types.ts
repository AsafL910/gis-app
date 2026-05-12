export type LayerRecord = {
  name: string;
  path: string;
  url: string;
  provider?: "cog" | "wmts";
  tile_url?: string;
  capabilities_url?: string;
  demo_url?: string;
  source_modes?: SourceMode[];
};

export type LayersResponse = {
  layers: LayerRecord[];
};

export type CatalogFile = {
  name: string;
  path: string;
  size: number;
};

export type MapSetManifest = {
  name: string;
  manifest_path: string;
  raster_files: string[];
  dtm_files: string[];
  dtm_vrt: string | null;
};

export type CatalogResponse = {
  rasters: CatalogFile[];
  dtms: CatalogFile[];
  map_sets: MapSetManifest[];
  active_dataset: string | null;
};

export type MapSetCreateResponse = {
  name: string;
  manifest_path: string;
  rasters: string[];
  dtm_vrt: string | null;
  active_dataset: string | null;
};

export type HighestPointResponse = {
  type: "FeatureCollection";
  features: Array<{
    type: "Feature";
    geometry: { type: "Point"; coordinates: [number, number] };
    properties: { highest_elevation: number; dataset_path: string };
  }>;
  highest_elevation: number;
  dataset_path: string;
};

export type SourceMode = "proxy" | "direct";
export type RasterMode = "terrain-rgb" | "single-band" | "imagery";
export type HoverState = {
  x: number;
  y: number;
  value: number;
} | null;

export type RasterStyle = { color: unknown };
