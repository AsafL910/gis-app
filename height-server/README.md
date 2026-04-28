# Height Calculation Server

A FastAPI service that provides elevation queries over GeoTIFF files using GDAL. It can
also auto-build a VRT mosaic from split top/bottom elevation COGs and query that merged
surface.

## Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/dataset-info/` | Show the currently loaded dataset path and metadata |
| `POST` | `/reload-dataset/` | Rebuild/reload the configured dataset |
| `POST` | `/get-elevation/` | Get elevation at a lat/lon coordinate |
| `POST` | `/get-highest-point/` | Find highest point within a polygon |

### `POST /get-elevation/`
```json
// Request
{ "latitude": 32.0853, "longitude": 34.7818 }

// Response
{ "latitude": 32.0853, "longitude": 34.7818, "elevation": 50 }
```

### `POST /get-highest-point/`
```json
// Request
{
  "coordinates": [
    { "latitude": 32.0853, "longitude": 34.7818 },
    { "latitude": 32.0850, "longitude": 34.7820 },
    { "latitude": 32.0845, "longitude": 34.7815 }
  ]
}

// Response
{ "highest_elevation": 120, "coordinate": { "latitude": 32.0851, "longitude": 34.7819 } }
```

## Running

### Docker (recommended — run from root with sibling map-provider)
```bash
# From d:/Courses/MAPS/israel/
docker compose up height-server
```

### Local (pixi)
```bash
cd height-server
pixi run start
```

Set `DATA_DIR` env var to point to the shared data folder.  
Default: `./data` relative to the service root.

By default the server now uses:

- `israel_merged.vrt`

If that VRT does not exist and `ELEV_FILENAME` ends with `.vrt`, the server will try to
build it automatically from:

- `israel_top_cog.tif`
- `israel_bottom_cog.tif`

## Dependencies

- **GDAL / OGR**: Core geospatial library (installed via apt in Docker, via conda in pixi)
- **FastAPI + Uvicorn**: HTTP server

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `DATA_DIR` | `./data` | Path to the shared data directory |
| `ELEV_FILENAME` | `israel_merged.vrt` | Elevation dataset filename within DATA_DIR |
| `ELEV_VRT_FILENAME` | `israel_merged.vrt` | Output VRT filename to build when needed |
| `TOP_ELEV_FILENAME` | `israel_top_cog.tif` | Top half source for VRT building |
| `BOTTOM_ELEV_FILENAME` | `israel_bottom_cog.tif` | Bottom half source for VRT building |
