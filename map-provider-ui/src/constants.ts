import Fill from "ol/style/Fill";
import Stroke from "ol/style/Stroke";
import Style from "ol/style/Style";
import CircleStyle from "ol/style/Circle";


export const DEFAULT_CENTER: [number, number] = [34.8, 31.5];
export const API_BASE = "/api";
export const DIRECT_DATA_BASE = "/cog-data";
export const HEIGHT_API_BASE = "/height-api";
export const MANAGEMENT_API_BASE = "/management-api";

export const terrainRgbElevation = [
  "+",
  -10000,
  ["*", 0.1 * 255 * 256 * 256, ["band", 1]],
  ["*", 0.1 * 255 * 256, ["band", 2]],
  ["*", 0.1 * 255, ["band", 3]]
];

export const singleBandElevation = ["band", 1];

export const drawLayerStyle = new Style({
  stroke: new Stroke({
    color: "#38bdf8",
    width: 2
  }),
  fill: new Fill({
    color: "rgba(56, 189, 248, 0.16)"
  })
});

export const highestPointStyle = new Style({
  image: new CircleStyle({
    radius: 7,
    fill: new Fill({ color: "#ef4444" }),
    stroke: new Stroke({ color: "#ffffff", width: 2 })
  })
});
