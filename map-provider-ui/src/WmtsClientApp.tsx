import { useEffect, useRef, useState } from "react";
import "ol/ol.css";
import Map from "ol/Map";
import View from "ol/View";
import TileLayer from "ol/layer/Tile";
import WMTS, { optionsFromCapabilities } from "ol/source/WMTS";
import WMTSCapabilities from "ol/format/WMTSCapabilities";
import { defaults as defaultInteractions } from "ol/interaction";
import type { Extent } from "ol/extent";
import type { Options as WmtsOptions } from "ol/source/WMTS";


type CapabilityLayer = {
  identifier: string;
  title: string;
};

type WmtsCatalogLayer = {
  identifier: string;
  name: string;
  path: string;
  bounds?: {
    epsg4326: [number, number, number, number];
  };
};

type SkippedLayer = {
  identifier: string;
  name: string;
  path: string;
  reason: string;
};

const CAPABILITIES_URL = "/api/wmts/1.0.0/WMTSCapabilities.xml";
const WMTS_PROXY_BASE = `${window.location.origin}/api/wmts`;
const WMTS_MATRIX_SET = "EPSG4326";
const DEFAULT_CENTER: [number, number] = [34.8, 31.5];


function normalizeWmtsUrls(urls: string[] | undefined) {
  if (!urls?.length) {
    return undefined;
  }

  return urls.map((url) =>
    url
      .replace(/^https?:\/\/[^/]+\/wmts/i, WMTS_PROXY_BASE)
      .replace(/^\/wmts/i, "/api/wmts")
  );
}


function getCenterFromBounds(layer: WmtsCatalogLayer | undefined) {
  const bounds = layer?.bounds?.epsg4326;
  if (!bounds) {
    return DEFAULT_CENTER;
  }

  const [minLon, minLat, maxLon, maxLat] = bounds;
  return [(minLon + maxLon) / 2, (minLat + maxLat) / 2] as [number, number];
}


function getExtent4326(layer: WmtsCatalogLayer | undefined): Extent | undefined {
  const bounds = layer?.bounds?.epsg4326;
  if (!bounds) {
    return undefined;
  }

  return [bounds[0], bounds[1], bounds[2], bounds[3]];
}


export default function WmtsClientApp() {
  const mapElementRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<Map | null>(null);
  const overlayLayerRef = useRef<TileLayer<WMTS> | null>(null);

  const [availableLayers, setAvailableLayers] = useState<CapabilityLayer[]>([]);
  const [catalogLayers, setCatalogLayers] = useState<WmtsCatalogLayer[]>([]);
  const [skippedLayers, setSkippedLayers] = useState<SkippedLayer[]>([]);
  const [selectedLayerName, setSelectedLayerName] = useState("");
  const [capabilitiesText, setCapabilitiesText] = useState("");
  const [status, setStatus] = useState("Booting");
  const [logLines, setLogLines] = useState<string[]>([]);

  function addLog(message: string) {
    const timestamp = new Date().toLocaleTimeString();
    setLogLines((current) => [`[${timestamp}] ${message}`, ...current].slice(0, 20));
  }

  useEffect(() => {
    if (!mapElementRef.current || mapRef.current) {
      return;
    }

    const map = new Map({
      target: mapElementRef.current,
      view: new View({
        projection: "EPSG:4326",
        center: DEFAULT_CENTER,
        zoom: 8,
        minZoom: 2,
        maxZoom: 20
      }),
      layers: [],
      controls: [],
      interactions: defaultInteractions({ doubleClickZoom: false }),
      moveTolerance: 50,
      maxTilesLoading: 6
    });

    mapRef.current = map;
    setStatus("Map ready");
    addLog("Initialized OpenLayers map");

    return () => {
      map.setTarget(undefined);
      mapRef.current = null;
    };
  }, []);

  useEffect(() => {
    let cancelled = false;

    async function initializeMap() {
      setStatus("Loading WMTS capabilities");
      addLog(`Fetching ${CAPABILITIES_URL}`);

      try {
        const parser = new WMTSCapabilities();
        const [capabilitiesResponse, catalogResponse] = await Promise.all([
          fetch(CAPABILITIES_URL),
          fetch("/api/wmts/layers")
        ]);

        const text = await capabilitiesResponse.text();
        const catalogPayload = await catalogResponse.json();
        if (cancelled) {
          return;
        }

        setCapabilitiesText(text);
        setCatalogLayers(catalogPayload.layers ?? []);
        setSkippedLayers(catalogPayload.skipped_layers ?? []);

        const parsed = parser.read(text) as {
          Contents?: { Layer?: Array<{ Identifier?: string; Title?: string }> };
        };

        const layers = (parsed.Contents?.Layer ?? [])
          .map((layer) => ({
            identifier: String(layer.Identifier ?? ""),
            title: String(layer.Title ?? layer.Identifier ?? "")
          }))
          .filter((layer) => layer.identifier);

        setAvailableLayers(layers);
        setSelectedLayerName((current) => current || layers[0]?.identifier || "");
        if (layers.length > 0) {
          setStatus(`Loaded ${layers.length} WMTS layer${layers.length === 1 ? "" : "s"}`);
        } else {
          setStatus("No EPSG:4326 WMTS layers available");
        }
        addLog(`Parsed ${layers.length} layer entries from GetCapabilities`);
        (catalogPayload.skipped_layers ?? []).forEach((layer: SkippedLayer) => {
          addLog(`Skipped ${layer.path}: ${layer.reason}`);
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : "Unknown error";
        setStatus("Capabilities load failed");
        addLog(`Capabilities request failed: ${message}`);
      }
    }

    void initializeMap();

    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !selectedLayerName || !capabilitiesText) {
      return;
    }

    const parser = new WMTSCapabilities();
    const parsed = parser.read(capabilitiesText);
    const layerOptions = optionsFromCapabilities(parsed, {
      layer: selectedLayerName,
      matrixSet: WMTS_MATRIX_SET
    }) as WmtsOptions | undefined;

    if (!layerOptions) {
      setStatus("Layer options unavailable");
      addLog(`Could not build WMTS options for ${selectedLayerName}`);
      return;
    }

    layerOptions.urls = normalizeWmtsUrls(layerOptions.urls);
    layerOptions.url =
      layerOptions.url
        ?.replace(/^https?:\/\/[^/]+\/wmts/i, WMTS_PROXY_BASE)
        .replace(/^\/wmts/i, "/api/wmts") ?? layerOptions.url;
    layerOptions.wrapX = true;
    layerOptions.crossOrigin = "anonymous";

    if (overlayLayerRef.current) {
      map.removeLayer(overlayLayerRef.current);
      overlayLayerRef.current = null;
    }

    const layer = new TileLayer({
      source: new WMTS(layerOptions),
      opacity: 1,
      preload: 10,
      zIndex: 1,
      extent: getExtent4326(catalogLayers.find((item) => item.identifier === selectedLayerName))
    });

    map.addLayer(layer);
    overlayLayerRef.current = layer;
    const selectedCatalogLayer = catalogLayers.find((item) => item.identifier === selectedLayerName);
    const extent4326 = getExtent4326(selectedCatalogLayer);
    if (extent4326) {
      map.getView().fit(extent4326, {
        padding: [32, 32, 32, 32],
        maxZoom: 16,
        duration: 0
      });
    } else {
      map.getView().setCenter(getCenterFromBounds(selectedCatalogLayer));
    }
    setStatus(`Showing ${selectedLayerName}`);
    addLog(`Attached WMTS layer ${selectedLayerName}`);

    return () => {
      map.removeLayer(layer);
      if (overlayLayerRef.current === layer) {
        overlayLayerRef.current = null;
      }
    };
  }, [capabilitiesText, catalogLayers, selectedLayerName]);

  return (
    <div className="wmts-client-shell">
      <aside className="wmts-client-sidebar">
        <section className="wmts-card">
          <h1>WMTS Smoke Client</h1>
          <p className="muted">
            This tiny React + OpenLayers page loads `GetCapabilities`, builds WMTS source options with
            `optionsFromCapabilities`, and renders the selected layer from the FastAPI service.
          </p>
        </section>

        <section className="wmts-card">
          <label htmlFor="wmts-layer-select">Layer</label>
          <select
            id="wmts-layer-select"
            value={selectedLayerName}
            onChange={(event) => setSelectedLayerName(event.target.value)}
          >
            <option value="">Select a WMTS layer</option>
            {availableLayers.map((layer) => (
              <option key={layer.identifier} value={layer.identifier}>
                {layer.title} ({layer.identifier})
              </option>
            ))}
          </select>
          <div className="kv">
            <span>Status</span>
            <strong>{status}</strong>
          </div>
          <div className="kv">
            <span>Capabilities</span>
            <code>{CAPABILITIES_URL}</code>
          </div>
          <div className="kv">
            <span>Matrix Set</span>
            <strong>{WMTS_MATRIX_SET}</strong>
          </div>
        </section>

        <section className="wmts-card">
          <h2>Capabilities XML</h2>
          <textarea
            className="wmts-capabilities"
            value={capabilitiesText}
            readOnly
            spellCheck={false}
          />
        </section>

        <section className="wmts-card">
          <h2>Skipped Layers</h2>
          <div className="log">
            {skippedLayers.length === 0 ? (
              <div className="log-line muted">No skipped layers.</div>
            ) : (
              skippedLayers.map((layer) => (
                <div className="log-line" key={layer.identifier}>
                  {layer.path}: {layer.reason}
                </div>
              ))
            )}
          </div>
        </section>

        <section className="wmts-card">
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
        </section>
      </aside>

      <main className="wmts-client-map-panel">
        <div ref={mapElementRef} className="map" />
      </main>
    </div>
  );
}
