# Map Provider UI

A small React + Vite + TypeScript + OpenLayers app for debugging the `map-provider` backend.

## What it does

- shows a plain OpenStreetMap basemap
- fetches available layers from `/api/layers`
- lets you switch between:
  - proxy tiles via `/api/cog/tiles/...`
  - direct COG loading via OpenLayers `GeoTIFF` from `/cog-data/<filename>`
- keeps a visible in-app event log for layer fetches and tile load events

## Expected backend

By default, the Vite dev server proxies `/api/*` to:

`http://127.0.0.1:8010`

And proxies `/cog-data/*` to:

`http://127.0.0.1:8011`

That matches:

- `map-provider` on port `8010`
- `data-http` on port `8011`

## Run Locally

```bash
cd map-provider-ui
npm install
npm run dev
```

Then open:

`http://127.0.0.1:5173`

For direct COG mode, also start the HTTP file server for `./data`, for example with:

```bash
docker compose up data-http map-provider
```

## Run In Docker

The full stack can now run in Docker, including the client served by nginx:

```bash
docker compose up --build
```

Then open:

`http://127.0.0.1:8013`

The nginx container serves the built app and proxies:

- `/api/*` -> `map-provider`
- `/cog-data/*` -> `data-http`
- `/height-api/*` -> `height-server`

## Debugging tips

- open the browser devtools network tab and watch `/api/layers`
- if the basemap appears but the raster does not, watch for `/api/cog/tiles/...` requests
- in direct mode, watch for `/cog-data/<filename>` requests
- the sidebar log will also show tile load errors from OpenLayers
