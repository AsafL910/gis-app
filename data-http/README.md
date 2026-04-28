# Data HTTP

The `data-http` microservice is a very small static file server for the shared `data/` directory.

Its purpose is to expose raster files over HTTP so the frontend can load Cloud Optimized GeoTIFFs directly when needed.

## Responsibilities

- serve files from the shared `data/` directory
- provide direct HTTP access for frontend COG loading
- stay read-only

## Runtime Role

This service is mainly used by `map-provider-ui` when the app is in direct COG mode.

- the UI requests `/cog-data/...`
- nginx proxies those requests to `data-http`
- OpenLayers can then read raster files directly over HTTP

## Boundaries

This service does not:

- inspect or catalog files
- build VRTs
- serve tiles
- calculate heights

It is only a thin HTTP wrapper around the shared data volume and nginx config.
