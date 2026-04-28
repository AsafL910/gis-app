import os
from pathlib import Path
from typing import List

import numpy as np
import rasterio
from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from rasterio.enums import Resampling
from rasterio.io import MemoryFile
from titiler.core.factory import TilerFactory


app = FastAPI(
    title="Map Provider Server",
    description="Dynamic COG tile provider with a self-contained preview page",
)


@app.get("/")
def root_redirect():
    return RedirectResponse(url="/demo")


cog = TilerFactory()
app.include_router(cog.router, prefix="/cog", tags=["COG Tiles"])

DATA_DIR = Path(os.environ.get("DATA_DIR", str(Path(__file__).resolve().parent.parent / "data")))


def get_available_cogs() -> List[str]:
    paths = [
        *DATA_DIR.rglob("*.tif"),
        *DATA_DIR.rglob("*.tiff"),
        *DATA_DIR.rglob("*.vrt"),
    ]
    return sorted(
        str(path.resolve().relative_to(DATA_DIR.resolve())).replace("\\", "/")
        for path in paths
        if path.is_file()
    )


def get_tif_url(relative_path: str) -> str:
    path = (DATA_DIR / relative_path).resolve()
    if not str(path).startswith(str(DATA_DIR.resolve())) or not path.exists():
        raise HTTPException(status_code=404, detail=f"File {relative_path} not found")
    return "file:///" + str(path).replace("\\", "/")


@app.get("/layers", tags=["Metadata"])
def list_layers():
    return {
        "layers": [
            {
                "name": Path(cog_name).name,
                "path": cog_name,
                "url": get_tif_url(cog_name),
            }
            for cog_name in get_available_cogs()
        ]
    }


def _normalize_to_uint8(data: np.ndarray) -> np.ndarray:
    array = np.asarray(data)

    if array.ndim == 2:
        array = array[np.newaxis, ...]

    if array.shape[0] == 1:
        array = np.repeat(array, 3, axis=0)
    elif array.shape[0] > 3:
        array = array[:3]

    result = np.zeros_like(array, dtype=np.uint8)
    for idx in range(array.shape[0]):
        band = array[idx].astype(np.float32)
        finite = np.isfinite(band)
        if not finite.any():
            continue

        values = band[finite]
        low = float(np.percentile(values, 2))
        high = float(np.percentile(values, 98))
        if high <= low:
            low = float(values.min())
            high = float(values.max())

        if high <= low:
            continue

        scaled = np.clip((band - low) / (high - low), 0.0, 1.0) * 255.0
        result[idx] = scaled.astype(np.uint8)

    return result


@app.get("/preview", tags=["Preview"])
def preview_layer(filename: str, max_size: int = 1600):
    path = DATA_DIR / filename
    if not path.exists():
        raise HTTPException(status_code=404, detail=f"File {filename} not found")

    max_size = max(128, min(max_size, 2400))

    with rasterio.open(path) as src:
        scale = min(1.0, max_size / max(src.width, src.height))
        out_width = max(1, int(src.width * scale))
        out_height = max(1, int(src.height * scale))
        band_indexes = [1, 2, 3] if src.count >= 3 else [1]
        raster = src.read(
            band_indexes,
            out_shape=(len(band_indexes), out_height, out_width),
            resampling=Resampling.bilinear,
        )

    rgb = _normalize_to_uint8(raster)

    with MemoryFile() as memfile:
        with memfile.open(
            driver="PNG",
            width=rgb.shape[2],
            height=rgb.shape[1],
            count=rgb.shape[0],
            dtype="uint8",
        ) as dst:
            dst.write(rgb)
        return Response(content=memfile.read(), media_type="image/png")


DEMO_HTML = """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Map Provider</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }

    body {
      font-family: Inter, system-ui, sans-serif;
      background: #0a0c10;
      color: #f0f2f5;
      height: 100vh;
      display: flex;
      flex-direction: column;
      overflow: hidden;
    }

    header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      padding: 16px 24px;
      background: rgba(13, 17, 23, 0.88);
      border-bottom: 1px solid rgba(255,255,255,0.08);
      box-shadow: 0 4px 20px rgba(0,0,0,0.28);
    }

    .brand {
      display: flex;
      align-items: center;
      gap: 12px;
    }

    .logo-icon {
      width: 32px;
      height: 32px;
      background: linear-gradient(135deg, #00f2fe 0%, #4facfe 100%);
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-weight: 800;
      color: white;
      font-size: 14px;
      flex: 0 0 auto;
    }

    h1 {
      font-size: 20px;
      font-weight: 600;
      color: #fff;
    }

    .layer-selector-container {
      display: flex;
      align-items: center;
      gap: 12px;
      background: rgba(255,255,255,0.05);
      padding: 8px 12px;
      border-radius: 8px;
      border: 1px solid rgba(255,255,255,0.1);
    }

    .layer-selector-container label {
      font-size: 13px;
      color: #94a3b8;
    }

    select {
      background: transparent;
      color: #fff;
      border: none;
      font-size: 14px;
      font-family: inherit;
      min-width: 220px;
      outline: none;
    }

    option {
      background: #161b22;
      color: #fff;
    }

    main {
      flex: 1;
      min-height: 0;
      padding: 20px 24px 24px;
      display: grid;
      grid-template-columns: minmax(0, 1fr) 320px;
      gap: 20px;
    }

    .viewer-shell,
    .sidebar {
      background: rgba(13, 17, 23, 0.84);
      border: 1px solid rgba(255,255,255,0.08);
      border-radius: 8px;
      overflow: hidden;
      box-shadow: 0 12px 40px rgba(0,0,0,0.28);
    }

    .viewer-shell {
      display: flex;
      flex-direction: column;
      min-height: 420px;
    }

    .viewer-toolbar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 12px 14px;
      border-bottom: 1px solid rgba(255,255,255,0.08);
      background: rgba(255,255,255,0.03);
      font-size: 13px;
      color: #94a3b8;
    }

    .viewer-stage {
      position: relative;
      flex: 1;
      min-height: 0;
      overflow: hidden;
      background:
        linear-gradient(45deg, rgba(255,255,255,0.03) 25%, transparent 25%),
        linear-gradient(-45deg, rgba(255,255,255,0.03) 25%, transparent 25%),
        linear-gradient(45deg, transparent 75%, rgba(255,255,255,0.03) 75%),
        linear-gradient(-45deg, transparent 75%, rgba(255,255,255,0.03) 75%);
      background-size: 24px 24px;
      background-position: 0 0, 0 12px, 12px -12px, -12px 0;
    }

    #preview-image {
      position: absolute;
      top: 50%;
      left: 50%;
      transform-origin: center center;
      max-width: none;
      user-select: none;
      -webkit-user-drag: none;
      cursor: grab;
      box-shadow: 0 14px 32px rgba(0,0,0,0.45);
    }

    #preview-image.dragging {
      cursor: grabbing;
    }

    .empty-state {
      position: absolute;
      inset: 0;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
      text-align: center;
      color: #8b949e;
      font-size: 14px;
    }

    .sidebar {
      padding: 18px;
      display: flex;
      flex-direction: column;
      gap: 18px;
    }

    .panel {
      display: flex;
      flex-direction: column;
      gap: 10px;
    }

    .panel h2 {
      font-size: 13px;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: #6e7681;
    }

    .metric {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      font-size: 14px;
    }

    .metric span:first-child {
      color: #94a3b8;
    }

    input[type=range] {
      -webkit-appearance: none;
      width: 100%;
      height: 4px;
      background: rgba(255,255,255,0.1);
      border-radius: 2px;
      outline: none;
    }

    input[type=range]::-webkit-slider-thumb {
      -webkit-appearance: none;
      width: 16px;
      height: 16px;
      background: #4facfe;
      border-radius: 50%;
      cursor: pointer;
      box-shadow: 0 0 10px rgba(79, 172, 254, 0.4);
    }

    .value-display {
      font-size: 14px;
      font-weight: 600;
      color: #fff;
    }

    .button-row {
      display: flex;
      gap: 8px;
    }

    button {
      flex: 1;
      border: 1px solid rgba(255,255,255,0.12);
      background: rgba(255,255,255,0.05);
      color: #fff;
      border-radius: 8px;
      padding: 10px 12px;
      cursor: pointer;
      font: inherit;
    }

    button:hover {
      background: rgba(255,255,255,0.08);
    }

    .hint {
      color: #8b949e;
      font-size: 13px;
      line-height: 1.5;
    }

    @media (max-width: 980px) {
      header {
        flex-direction: column;
        align-items: stretch;
      }

      main {
        grid-template-columns: 1fr;
      }

      .viewer-shell {
        min-height: 55vh;
      }
    }
  </style>
</head>
<body>
  <header>
    <div class="brand">
      <div class="logo-icon">M</div>
      <h1>Map Provider</h1>
    </div>

    <div class="layer-selector-container">
      <label for="layer-select">Active Layer:</label>
      <select id="layer-select">
        <option value="">Loading layers...</option>
      </select>
    </div>
  </header>

  <main>
    <section class="viewer-shell">
      <div class="viewer-toolbar">
        <span id="viewer-status">Loading preview...</span>
        <span id="viewer-zoom">100%</span>
      </div>
      <div class="viewer-stage" id="viewer-stage">
        <img id="preview-image" alt="Map preview" hidden />
        <div class="empty-state" id="empty-state">Looking for raster layers...</div>
      </div>
    </section>

    <aside class="sidebar">
      <div class="panel">
        <h2>Layer Opacity</h2>
        <input type="range" id="opacity" min="0" max="100" value="100" />
        <span class="value-display" id="opacity-val">100%</span>
      </div>

      <div class="panel">
        <h2>View</h2>
        <div class="button-row">
          <button id="zoom-out" type="button">-</button>
          <button id="reset-view" type="button">Reset</button>
          <button id="zoom-in" type="button">+</button>
        </div>
      </div>

      <div class="panel">
        <h2>Layer Info</h2>
        <div class="metric"><span>Name</span><span id="layer-name">-</span></div>
        <div class="metric"><span>Source</span><span>Local TIFF</span></div>
        <div class="metric"><span>Status</span><span id="layer-status">Waiting</span></div>
      </div>

      <div class="panel">
        <h2>Notes</h2>
        <p class="hint">
          This page renders a preview directly from your local TIFF files, so it still works when external map CDNs are blocked.
        </p>
      </div>
    </aside>
  </main>

  <script>
    const BASE = window.location.origin;
    const layersMap = {};
    const select = document.getElementById('layer-select');
    const previewImage = document.getElementById('preview-image');
    const emptyState = document.getElementById('empty-state');
    const viewerStage = document.getElementById('viewer-stage');
    const viewerStatus = document.getElementById('viewer-status');
    const viewerZoom = document.getElementById('viewer-zoom');
    const layerNameEl = document.getElementById('layer-name');
    const layerStatusEl = document.getElementById('layer-status');

    let scale = 1;
    let offsetX = 0;
    let offsetY = 0;
    let dragState = null;

    function applyTransform() {
      previewImage.style.transform = `translate(calc(-50% + ${offsetX}px), calc(-50% + ${offsetY}px)) scale(${scale})`;
      viewerZoom.textContent = `${Math.round(scale * 100)}%`;
    }

    function resetView() {
      scale = 1;
      offsetX = 0;
      offsetY = 0;
      applyTransform();
    }

    function setStatus(text, layerStatus) {
      viewerStatus.textContent = text;
      layerStatusEl.textContent = layerStatus;
    }

    async function updateLayer(layerName) {
      if (!layersMap[layerName]) {
        previewImage.hidden = true;
        emptyState.hidden = false;
        emptyState.textContent = 'No layer selected.';
        setStatus('No layer selected', 'Waiting');
        return;
      }

      const imageUrl = `${BASE}/preview?filename=${encodeURIComponent(layerName)}&max_size=1800`;
      layerNameEl.textContent = layerName;
      setStatus('Rendering preview...', 'Loading');
      emptyState.hidden = false;
      emptyState.textContent = 'Rendering TIFF preview...';
      previewImage.hidden = true;

      previewImage.onload = () => {
        previewImage.hidden = false;
        emptyState.hidden = true;
        setStatus('Preview ready', 'Ready');
        resetView();
      };

      previewImage.onerror = () => {
        previewImage.hidden = true;
        emptyState.hidden = false;
        emptyState.textContent = 'Preview could not be rendered for this layer.';
        setStatus('Preview failed', 'Error');
      };

      previewImage.src = imageUrl;
    }

    async function loadLayers() {
      try {
        const response = await fetch(`${BASE}/layers`);
        const data = await response.json();
        select.innerHTML = '';

        data.layers.forEach((layer) => {
          layersMap[layer.name] = layer.url;
          const option = document.createElement('option');
          option.value = layer.name;
          option.textContent = layer.name;
          select.appendChild(option);
        });

        if (data.layers.length > 0) {
          await updateLayer(data.layers[0].name);
        } else {
          select.innerHTML = '<option value="">No layers found</option>';
          emptyState.textContent = 'No TIFF layers were found in the data directory.';
          setStatus('No layers found', 'Empty');
        }
      } catch (error) {
        console.error(error);
        emptyState.textContent = 'Failed to load available layers.';
        setStatus('Layer request failed', 'Error');
      }
    }

    select.addEventListener('change', (event) => {
      updateLayer(event.target.value);
    });

    const opacitySlider = document.getElementById('opacity');
    const opacityVal = document.getElementById('opacity-val');
    opacitySlider.addEventListener('input', () => {
      const value = Number(opacitySlider.value);
      previewImage.style.opacity = String(value / 100);
      opacityVal.textContent = `${value}%`;
    });

    document.getElementById('zoom-in').addEventListener('click', () => {
      scale = Math.min(scale * 1.2, 8);
      applyTransform();
    });

    document.getElementById('zoom-out').addEventListener('click', () => {
      scale = Math.max(scale / 1.2, 0.25);
      applyTransform();
    });

    document.getElementById('reset-view').addEventListener('click', resetView);

    viewerStage.addEventListener('wheel', (event) => {
      event.preventDefault();
      const delta = event.deltaY < 0 ? 1.1 : 0.9;
      scale = Math.min(8, Math.max(0.25, scale * delta));
      applyTransform();
    });

    previewImage.addEventListener('pointerdown', (event) => {
      dragState = { x: event.clientX, y: event.clientY, offsetX, offsetY };
      previewImage.classList.add('dragging');
      previewImage.setPointerCapture(event.pointerId);
    });

    previewImage.addEventListener('pointermove', (event) => {
      if (!dragState) return;
      offsetX = dragState.offsetX + (event.clientX - dragState.x);
      offsetY = dragState.offsetY + (event.clientY - dragState.y);
      applyTransform();
    });

    previewImage.addEventListener('pointerup', (event) => {
      dragState = null;
      previewImage.classList.remove('dragging');
      previewImage.releasePointerCapture(event.pointerId);
    });

    loadLayers();
  </script>
</body>
</html>
"""


@app.get("/demo", response_class=HTMLResponse, tags=["Demo"])
def demo_page():
    return DEMO_HTML


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
