# Map Provider

A FastAPI service that dynamically discovers Cloud Optimized GeoTIFFs (COGs) in a shared data directory and serves them as XYZ tiles via TiTiler, plus an interactive Leaflet demo page.

## Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/` | Redirects to `/demo` |
| `GET` | `/layers` | Lists all discovered `.tif` files |
| `GET` | `/demo` | Interactive Leaflet map UI |
| `GET` | `/cog/tiles/...` | XYZ tiles via TiTiler |
| `GET` | `/cog/info` | COG metadata |

## Running

### Docker (recommended — run from root with sibling height-server)
```bash
# From d:/Courses/MAPS/israel/
docker compose up map-provider
```

### Local (pixi)
```bash
cd map-provider
pixi run start
```

Set `DATA_DIR` env var to point to the shared data folder.  
Default: `./data` relative to the service root.

## Dependencies

- **TiTiler**: Dynamic tile server built on rio-tiler + rasterio
- **Rasterio**: Reads GeoTIFF/COG files (ships with bundled GDAL — no system install needed)
- **FastAPI + Uvicorn**: HTTP server

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `DATA_DIR` | `./data` | Path to the shared data directory containing `.tif` files |
