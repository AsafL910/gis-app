# GLB Demo

This project is a small GIS application for managing raster and DTM sources, building VRT map sets, previewing layers on a map, and running elevation queries against GDAL-backed datasets.

## Project Layout

The main application lives in [gis-app](D:/Courses/MAPS/israel/glb-demo/gis-app).

Key services:

- `map-provider-ui`: React/OpenLayers frontend for browsing layers, creating map sets, and running polygon height queries.
- `map-manager`: Node.js/TypeScript service for cataloging source files, creating VRT map sets, and storing the currently selected DTM for the UI.
- `map-provider`: FastAPI + TiTiler service for listing available rasters and serving tile layers.
- `mapproxy-service`: Separate MapProxy wrapper service that runs `mapproxy-util serve-develop` from a seeded JSON config plus YAML template.
- `height-server`: FastAPI + GDAL service for elevation lookups and highest-point calculations.
- `data-http`: Nginx file server exposing the shared `data/` directory for direct COG access.
- `mongo-transaction-demo`: .NET 8 example worker that opens a MongoDB transaction against the packaged replica set.

## Architecture

The app is intentionally split by responsibility:

- Management workflows live in Node.js/TypeScript.
  This includes file cataloging, manifest writing, VRT creation, and selected-DTM state.
- Height calculations live in Python.
  This includes GDAL dataset loading, coordinate transforms, raster sampling, and highest-point searches.

The important design point is that the Python height service is no longer responsible for map-set management. Height requests can specify the dataset they want to query, while the manager service only tracks selection state for the application.

## Running

From the project root:

```bash
cd gis-app
docker-compose up --build
```

Default ports:

- UI: `http://localhost:8013`
- Map provider API: `http://localhost:8010`
- MapProxy service: `http://localhost:8070`
- Height API: `http://localhost:8009`
- Map manager API: `http://localhost:8008`
- Shared data HTTP: `http://localhost:8011`

## Data Directories

Shared data is mounted from [gis-app/data](D:/Courses/MAPS/israel/glb-demo/gis-app/data):

- `data/raster`: source imagery and raster layers
- `data/dtm`: elevation datasets and source DTMs
- `data/mapsets`: generated manifests and VRT outputs

## Typical Flow

1. Add raster files under `data/raster` and DTM files under `data/dtm`.
2. Open the UI and create a map set from selected raster and DTM files.
3. The map manager builds a DTM VRT when needed and stores the selected dataset.
4. The UI previews rasters through the map provider.
5. Height queries are sent to the height server with the selected dataset path.

## Notes

- `map-manager` requires `gdalbuildvrt` in its runtime image because it builds VRTs directly.
- `height-server` still supports a default configured dataset for startup, but per-request dataset selection is supported for app workflows.
- Some service-specific READMEs still describe the older split and may need a follow-up refresh.
