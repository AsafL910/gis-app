# Map Provider UI

The `map-provider-ui` microservice is the frontend for the GIS demo.

It gives users a single interface for:

- browsing raster and DTM sources
- creating VRT-backed map sets
- previewing rasters on the map
- selecting the active DTM for the session
- drawing polygons and requesting highest-point calculations

## Runtime Role

This UI coordinates the other services:

- `map-manager` for cataloging, VRT generation, and DTM selection
- `map-provider` for raster listing and tile access
- `height-server` for GDAL-based height calculations
- `data-http` for direct COG loading

## Proxied APIs

In Docker, nginx serves the built app and proxies:

- `/api/*` to `map-provider`
- `/management-api/*` to `map-manager`
- `/height-api/*` to `height-server`
- `/cog-data/*` to `data-http`

## Local Focus

If you are changing this service, you are usually working on:

- React/OpenLayers map behavior
- map-set creation UX
- dataset selection UX
- request wiring between frontend and backend services
