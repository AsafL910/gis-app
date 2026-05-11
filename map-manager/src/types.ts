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

export type MapSetCreateRequest = {
  name: string;
  raster_files?: string[];
  dtm_files?: string[];
  activate_dtm?: boolean;
};
