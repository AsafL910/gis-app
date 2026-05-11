import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import "ol/ol.css";
import GeoJSON from "ol/format/GeoJSON";
import Map from "ol/Map";
import View from "ol/View";
import Draw from "ol/interaction/Draw";
import TileLayer from "ol/layer/Tile";
import VectorLayer from "ol/layer/Vector";
import WebGLTileLayer from "ol/layer/WebGLTile";
import XYZ from "ol/source/XYZ";
import OSM from "ol/source/OSM";
import GeoTIFF from "ol/source/GeoTIFF";
import VectorSource from "ol/source/Vector";
import { fromLonLat } from "ol/proj";
import { fetchCatalog, fetchLayers, postActivateDtm, postCreateMapSet, postHighestPoint } from "./api";
import { DEFAULT_CENTER, DIRECT_DATA_BASE, API_BASE, drawLayerStyle, highestPointStyle } from "./constants";
import { FileSelectionTable } from "./components/FileSelectionTable";
import { MapSetTable } from "./components/MapSetTable";
import type { CatalogResponse, HoverState, LayerRecord, RasterMode, RasterStyle, SourceMode } from "./types";
import { decodeDirectCog, decodeTerrainRgb, encodeDataPath, getColorExpression, getDefaultRasterMode } from "./utils/raster";

function App() {
  const mapElementRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<Map | null>(null);
  const rasterLayerRef = useRef<WebGLTileLayer | null>(null);
  const attachGenerationRef = useRef(0);
  const drawSourceRef = useRef(new VectorSource());
  const resultSourceRef = useRef(new VectorSource());
  const drawInteractionRef = useRef<Draw | null>(null);
  const geoJsonFormatRef = useRef(new GeoJSON());

  const [layers, setLayers] = useState<LayerRecord[]>([]);
  const [catalog, setCatalog] = useState<CatalogResponse>({
    rasters: [],
    dtms: [],
    map_sets: [],
    active_dataset: null
  });
  const [selectedLayerPath, setSelectedLayerPath] = useState("");
  const [selectedRasterPaths, setSelectedRasterPaths] = useState<string[]>([]);
  const [selectedDtmPaths, setSelectedDtmPaths] = useState<string[]>([]);
  const [mapSetName, setMapSetName] = useState("israel-set");
  const [layerVisible, setLayerVisible] = useState(true);
  const [opacity, setOpacity] = useState(0.4);
  const [level, setLevel] = useState(0);
  const [status, setStatus] = useState("Booting");
  const [logLines, setLogLines] = useState<string[]>([]);
  const [sourceMode, setSourceMode] = useState<SourceMode>("proxy");
  const [rasterMode, setRasterMode] = useState<RasterMode>("single-band");
  const [hoverState, setHoverState] = useState<HoverState>(null);
  const [isDrawing, setIsDrawing] = useState(false);
  const [isFindingHighestPoint, setIsFindingHighestPoint] = useState(false);
  const [isCreatingMapSet, setIsCreatingMapSet] = useState(false);
  const [highestPointSummary, setHighestPointSummary] = useState<string>("-");

  const activeLayer = useMemo(
    () => layers.find((layer) => layer.path === selectedLayerPath) ?? null,
    [layers, selectedLayerPath]
  );
  const isTerrainMode = rasterMode !== "imagery";

  const directCogUrl = activeLayer
    ? `${DIRECT_DATA_BASE}/${encodeDataPath(activeLayer.path)}`
    : "";

  const proxyTileUrl = activeLayer
    ? `${API_BASE}/cog/tiles/WebMercatorQuad/{z}/{x}/{y}.png?url=${encodeURIComponent(activeLayer.url)}`
    : "";

  function addLog(message: string) {
    const timestamp = new Date().toLocaleTimeString();
    setLogLines((current) => [`[${timestamp}] ${message}`, ...current].slice(0, 24));
  }

  const refreshCatalog = useCallback(async () => {
    const data = await fetchCatalog();
    setCatalog(data);
    return data;
  }, []);

  const refreshLayers = useCallback(async (preferredPath?: string) => {
    const data = await fetchLayers();
    setLayers(data.layers);
    setSelectedLayerPath((current) => {
      if (preferredPath && data.layers.some((layer) => layer.path === preferredPath)) {
        return preferredPath;
      }
      if (current && data.layers.some((layer) => layer.path === current)) {
        return current;
      }
      return data.layers[0]?.path ?? "";
    });
    return data;
  }, []);

  function toggleSelection(path: string, selected: string[], setSelected: (value: string[]) => void) {
    setSelected(
      selected.includes(path)
        ? selected.filter((item) => item !== path)
        : [...selected, path]
    );
  }

  async function activateDtm(path: string) {
    try {
      await postActivateDtm(path);
      await refreshCatalog();
      addLog(`Activated DTM dataset ${path}`);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      addLog(`Failed to activate DTM: ${message}`);
    }
  }

  async function createMapSet() {
    setIsCreatingMapSet(true);
    setStatus("Creating map set");
    try {
      const result = await postCreateMapSet({
        name: mapSetName,
        raster_files: selectedRasterPaths,
        dtm_files: selectedDtmPaths,
        activate_dtm: true
      });
      await refreshCatalog();
      await refreshLayers(result.rasters[0] ?? result.dtm_vrt ?? undefined);
      if (result.rasters.length > 0) {
        setRasterMode("imagery");
      }
      setStatus("Map set ready");
      addLog(`Created map set ${result.name}`);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      setStatus("Map set failed");
      addLog(`Map set creation failed: ${message}`);
    } finally {
      setIsCreatingMapSet(false);
    }
  }

  function clearDrawings() {
    drawSourceRef.current.clear();
    resultSourceRef.current.clear();
    setHighestPointSummary("-");
    addLog("Cleared polygon and highest-point marker");
  }

  useEffect(() => {
    if (!activeLayer) {
      return;
    }
    setRasterMode(getDefaultRasterMode(activeLayer.name));
  }, [activeLayer?.name]);

  useEffect(() => {
    if (!mapElementRef.current || mapRef.current) {
      return;
    }

    const baseLayer = new TileLayer({
      source: new OSM()
    });

    const polygonLayer = new VectorLayer({
      source: drawSourceRef.current,
      style: drawLayerStyle
    });

    const highestPointLayer = new VectorLayer({
      source: resultSourceRef.current,
      style: highestPointStyle
    });

    const map = new Map({
      target: mapElementRef.current,
      layers: [baseLayer, polygonLayer, highestPointLayer],
      view: new View({
        center: fromLonLat(DEFAULT_CENTER),
        zoom: 8,
        minZoom: 2,
        maxZoom: 20
      })
    });

    mapRef.current = map;
    setStatus("Map ready");
    addLog("OpenLayers map initialized");

    return () => {
      map.setTarget(undefined);
      mapRef.current = null;
    };
  }, []);

  useEffect(() => {
    async function loadInitialData() {
      try {
        setStatus("Loading catalog");
        await Promise.all([refreshCatalog(), refreshLayers()]);
        setStatus("Catalog ready");
        addLog("Loaded catalog and layers");
      } catch (error) {
        const message = error instanceof Error ? error.message : "Unknown error";
        setStatus("Initial load failed");
        addLog(`Initial load failed: ${message}`);
      }
    }

    loadInitialData();
  }, [refreshCatalog, refreshLayers]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) {
      return;
    }

    attachGenerationRef.current += 1;
    const generation = attachGenerationRef.current;

    if (rasterLayerRef.current) {
      map.removeLayer(rasterLayerRef.current);
      rasterLayerRef.current = null;
      addLog("Removed previous raster layer");
    }

    setHoverState(null);

    if (!activeLayer || !layerVisible) {
      setStatus(activeLayer ? "Layer hidden" : "No layer selected");
      return;
    }

    const style: RasterStyle | undefined = isTerrainMode
      ? { color: getColorExpression(rasterMode, level) }
      : undefined;

    if (sourceMode === "proxy") {
      const source = new XYZ({
        url: proxyTileUrl,
        crossOrigin: "anonymous"
      });

      source.on("tileloadstart", () => addLog("Proxy tile load start"));
      source.on("tileloadend", () => addLog("Proxy tile load end"));
      source.on("tileloaderror", () => addLog("Proxy tile load error"));

      const rasterLayer = new WebGLTileLayer({
        source: source as any,
        opacity,
        style: style as any
      });

      map.addLayer(rasterLayer);
      rasterLayerRef.current = rasterLayer;
      setStatus("Proxy raster attached");
      addLog(`Attached proxy layer ${activeLayer.path}`);
      return;
    }

    const source = new GeoTIFF({
      sources: [
        isTerrainMode
          ? ({ url: directCogUrl } as any)
          : ({ url: directCogUrl, convertToRGB: "auto" } as any)
      ],
      interpolate: false
    });

    source.on("change", () => {
      addLog(`Direct GeoTIFF state: ${source.getState()}`);
    });
    source.on("error", () => {
      addLog("Direct GeoTIFF source error");
      setStatus("Direct COG failed");
    });

    const rasterLayer = new WebGLTileLayer({
      source,
      opacity,
      style: style as any
    });

    map.addLayer(rasterLayer);
    rasterLayerRef.current = rasterLayer;
    setStatus("Direct COG attached");
    addLog(`Attached direct layer ${activeLayer.path}`);

    source.getView().then(() => {
      if (attachGenerationRef.current !== generation) {
        return;
      }
      addLog("Direct COG ready without changing shared view");
    }).catch((error: unknown) => {
      const message = error instanceof Error ? error.message : "Unknown error";
      if (attachGenerationRef.current !== generation) {
        return;
      }
      setStatus("Direct COG failed");
      addLog(`GeoTIFF view setup failed: ${message}`);
    });
  }, [activeLayer, layerVisible, proxyTileUrl, directCogUrl, sourceMode, isTerrainMode, rasterMode]);

  useEffect(() => {
    const layer = rasterLayerRef.current;
    if (!layer) {
      return;
    }
    layer.setOpacity(opacity);
    if (isTerrainMode) {
      layer.setStyle({ color: getColorExpression(rasterMode, level) } as any);
    } else {
      layer.setStyle({} as any);
    }
  }, [opacity, level, rasterMode, isTerrainMode]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) {
      return;
    }

    const handlePointerMove = (event: { pixel: [number, number] }) => {
      const layer = rasterLayerRef.current;
      if (!layer || !layerVisible || !isTerrainMode) {
        setHoverState(null);
        return;
      }

      const data = layer.getData(event.pixel) as ArrayLike<number> | null;
      if (!data || data.length === 0) {
        setHoverState(null);
        return;
      }

      const value =
        rasterMode === "single-band"
          ? Number(data[0] ?? 0)
          : sourceMode === "proxy"
            ? decodeTerrainRgb(data)
            : decodeDirectCog(data);
      if (!Number.isFinite(value)) {
        setHoverState(null);
        return;
      }

      setHoverState({ x: event.pixel[0], y: event.pixel[1], value });
    };

    const handlePointerLeave = () => setHoverState(null);

    (map as any).on("pointermove", handlePointerMove);
    map.getViewport().addEventListener("mouseleave", handlePointerLeave);

    return () => {
      (map as any).un("pointermove", handlePointerMove);
      map.getViewport().removeEventListener("mouseleave", handlePointerLeave);
    };
  }, [layerVisible, sourceMode, rasterMode, isTerrainMode]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) {
      return;
    }

    if (drawInteractionRef.current) {
      map.removeInteraction(drawInteractionRef.current);
      drawInteractionRef.current = null;
    }

    if (!isDrawing) {
      return;
    }

    const draw = new Draw({
      source: drawSourceRef.current,
      type: "Polygon"
    });

    draw.on("drawstart", () => {
      drawSourceRef.current.clear();
      resultSourceRef.current.clear();
      setHighestPointSummary("-");
      addLog("Started drawing polygon");
    });

    draw.on("drawend", () => {
      setIsDrawing(false);
      addLog("Finished drawing polygon");
    });

    drawInteractionRef.current = draw;
    map.addInteraction(draw);

    return () => {
      map.removeInteraction(draw);
      if (drawInteractionRef.current === draw) {
        drawInteractionRef.current = null;
      }
    };
  }, [isDrawing]);

  async function findHighestPoint() {
    const polygonFeature = drawSourceRef.current.getFeatures()[0];
    if (!polygonFeature) {
      addLog("No polygon drawn");
      setStatus("Draw a polygon first");
      return;
    }

    const polygonGeoJson = geoJsonFormatRef.current.writeFeatureObject(polygonFeature, {
      dataProjection: "EPSG:4326",
      featureProjection: mapRef.current?.getView().getProjection() ?? "EPSG:3857"
    });

    setIsFindingHighestPoint(true);
    setStatus("Finding highest point");
    addLog("Posting polygon GeoJSON to height server");

    try {
      const payload = await postHighestPoint({
        dataset_path: catalog.active_dataset,
        geojson: polygonGeoJson
      });
      resultSourceRef.current.clear();
      const pointFeatures = geoJsonFormatRef.current.readFeatures(payload, {
        dataProjection: "EPSG:4326",
        featureProjection: mapRef.current?.getView().getProjection() ?? "EPSG:3857"
      });
      resultSourceRef.current.addFeatures(pointFeatures);

      const firstPoint = payload.features[0];
      const [lon, lat] = firstPoint.geometry.coordinates;
      const elevation = firstPoint.properties.highest_elevation;
      setHighestPointSummary(`${elevation} m at ${lat.toFixed(5)}, ${lon.toFixed(5)}`);
      setStatus("Highest point ready");
      addLog(`Highest point found: ${elevation} m`);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      setStatus("Highest point failed");
      addLog(`Highest point request failed: ${message}`);
    } finally {
      setIsFindingHighestPoint(false);
    }
  }

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="panel">
          <h1>Map Set Manager</h1>
          <p className="muted">
            Organize raster and DTM sources, generate VRT map sets, and preview them on the map.
          </p>
        </div>

        <div className="panel">
          <div className="panel-heading">
            <h2>Create Map Set</h2>
            <span className="muted small">Active DTM: {catalog.active_dataset ?? "-"}</span>
          </div>
          <label htmlFor="map-set-name">Name</label>
          <input
            id="map-set-name"
            className="text-input"
            value={mapSetName}
            onChange={(event) => setMapSetName(event.target.value)}
          />
          <button
            type="button"
            className="segment active"
            disabled={isCreatingMapSet}
            onClick={() => void createMapSet()}
          >
            {isCreatingMapSet ? "Generating..." : "Generate VRT Map Set"}
          </button>
        </div>

        <FileSelectionTable
          title="Raster Sources"
          rows={catalog.rasters}
          selectedPaths={selectedRasterPaths}
          onToggle={(path) => toggleSelection(path, selectedRasterPaths, setSelectedRasterPaths)}
        />

        <FileSelectionTable
          title="DTM Sources"
          rows={catalog.dtms}
          selectedPaths={selectedDtmPaths}
          onToggle={(path) => toggleSelection(path, selectedDtmPaths, setSelectedDtmPaths)}
        />

        <MapSetTable
          rows={catalog.map_sets}
          activeDataset={catalog.active_dataset}
          onPreview={(path) => setSelectedLayerPath(path)}
          onActivate={(path) => void activateDtm(path)}
        />

        <div className="panel">
          <h2>Preview Layer</h2>
          <select
            value={selectedLayerPath}
            onChange={(event) => setSelectedLayerPath(event.target.value)}
          >
            <option value="">Select a layer</option>
            {layers.map((layer) => (
              <option key={layer.path} value={layer.path}>
                {layer.path}
              </option>
            ))}
          </select>
        </div>

        <div className="panel">
          <span className="label-title">Source Mode</span>
          <div className="segmented-control" role="radiogroup" aria-label="Source mode">
            <button
              type="button"
              className={sourceMode === "proxy" ? "segment active" : "segment"}
              onClick={() => setSourceMode("proxy")}
            >
              Proxy XYZ
            </button>
            <button
              type="button"
              className={sourceMode === "direct" ? "segment active" : "segment"}
              onClick={() => setSourceMode("direct")}
            >
              Direct COG
            </button>
          </div>
        </div>

        <div className="panel">
          <span className="label-title">Raster Interpretation</span>
          <div className="segmented-control segmented-control--triple" role="radiogroup" aria-label="Raster interpretation">
            <button
              type="button"
              className={rasterMode === "terrain-rgb" ? "segment active" : "segment"}
              onClick={() => setRasterMode("terrain-rgb")}
            >
              Terrain RGB
            </button>
            <button
              type="button"
              className={rasterMode === "single-band" ? "segment active" : "segment"}
              onClick={() => setRasterMode("single-band")}
            >
              Single band
            </button>
            <button
              type="button"
              className={rasterMode === "imagery" ? "segment active" : "segment"}
              onClick={() => setRasterMode("imagery")}
            >
              Imagery
            </button>
          </div>
        </div>

        <div className="panel">
          <label className="checkbox">
            <input
              type="checkbox"
              checked={layerVisible}
              onChange={(event) => setLayerVisible(event.target.checked)}
            />
            <span>Show preview layer</span>
          </label>

          <label htmlFor="opacity">Opacity: {Math.round(opacity * 100)}%</label>
          <input
            id="opacity"
            type="range"
            min="0"
            max="100"
            value={Math.round(opacity * 100)}
            onChange={(event) => setOpacity(Number(event.target.value) / 100)}
          />

          <label htmlFor="level">Level: {level.toFixed(0)}</label>
          <input
            id="level"
            type="range"
            min="0"
            max="1000"
            value={level}
            disabled={!isTerrainMode}
            onChange={(event) => setLevel(Number(event.target.value))}
          />
        </div>

        <div className="panel">
          <h2>Highest Point</h2>
          <div className="button-stack">
            <button
              type="button"
              className={isDrawing ? "segment active" : "segment"}
              onClick={() => setIsDrawing((current) => !current)}
            >
              {isDrawing ? "Cancel drawing" : "Draw polygon"}
            </button>
            <button
              type="button"
              className="segment"
              disabled={isFindingHighestPoint}
              onClick={() => void findHighestPoint()}
            >
              {isFindingHighestPoint ? "Finding..." : "Find highest point"}
            </button>
            <button type="button" className="segment" onClick={clearDrawings}>
              Clear
            </button>
          </div>
          <div className="kv">
            <span>Result</span>
            <strong>{highestPointSummary}</strong>
          </div>
        </div>

        <div className="panel">
          <h2>Status</h2>
          <div className="kv"><span>State</span><strong>{status}</strong></div>
          <div className="kv"><span>Selected Layer</span><code>{selectedLayerPath || "-"}</code></div>
          <div className="kv"><span>Hover Height</span><strong>{hoverState ? hoverState.value.toFixed(1) : "-"}</strong></div>
        </div>

        <div className="panel">
          <h2>Debug Log</h2>
          <div className="log">
            {logLines.length === 0 ? (
              <div className="log-line muted">No events yet.</div>
            ) : (
              logLines.map((line, index) => (
                <div className="log-line" key={`${index}-${line}`}>
                  {line}
                </div>
              ))
            )}
          </div>
        </div>
      </aside>

      <main className="map-panel">
        <div className="map-wrapper">
          {hoverState ? (
            <div
              className="hover-label"
              style={{
                left: hoverState.x + 8,
                top: hoverState.y - 8
              }}
            >
              {hoverState.value.toFixed(0)}
            </div>
          ) : null}
          <div ref={mapElementRef} className="map" />
        </div>
      </main>
    </div>
  );
}

export default App;
