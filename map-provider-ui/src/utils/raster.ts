import type { RasterMode } from "../types";
import { singleBandElevation, terrainRgbElevation } from "../constants";


export function getElevationExpression(rasterMode: RasterMode) {
  return rasterMode === "single-band" ? singleBandElevation : terrainRgbElevation;
}


export function getColorExpression(rasterMode: RasterMode, level: number) {
  const elevation = getElevationExpression(rasterMode);

  return [
    "case",
    ["<=", ["-", level, elevation], 100],
    [255, 0, 0, 1],
    ["between", ["-", level, elevation], 100, 250],
    [255, 255, 0, 1],
    [">=", ["-", level, elevation], 400],
    [0, 255, 0, 1],
    [0, 0, 0, 0]
  ];
}


export function decodeTerrainRgb(sample: ArrayLike<number>) {
  const r = sample[0] ?? 0;
  const g = sample[1] ?? 0;
  const b = sample[2] ?? 0;
  return r * 256 * 256 * 0.1 + g * 256 * 0.1 + b * 0.1 - 10000;
}


export function decodeDirectCog(sample: ArrayLike<number>) {
  if (sample.length >= 3) {
    return decodeTerrainRgb(sample);
  }

  return Number(sample[0] ?? 0);
}


export function getDefaultRasterMode(layerName: string): RasterMode {
  if (/raster\.vrt$/i.test(layerName) || /(^|\/)raster\//i.test(layerName) || /rgb/i.test(layerName)) {
    return "imagery";
  }

  return "single-band";
}


export function formatBytes(size: number) {
  if (size < 1024) {
    return `${size} B`;
  }
  if (size < 1024 * 1024) {
    return `${(size / 1024).toFixed(1)} KB`;
  }
  return `${(size / (1024 * 1024)).toFixed(1)} MB`;
}


export function encodeDataPath(path: string) {
  return path.split("/").map(encodeURIComponent).join("/");
}
