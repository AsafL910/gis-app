# Map Provider

The `map-provider` microservice is the raster listing and tile-serving backend.

It scans the shared data directory for TIFF and VRT files and exposes them to the frontend for preview and map display. It does not manage map sets and it does not calculate heights.

## Responsibilities

- list available raster-like layers from the shared data directory
- expose TiTiler endpoints for tile access
- provide preview and metadata endpoints for the frontend

## Runtime Role

This service powers the map view:

- `map-provider-ui` calls `/layers` to discover available layers
- proxy tile mode uses TiTiler routes under `/cog`
- preview and visualization requests stay here, not in `height-server`

## Boundaries

This service should not own:

- DTM selection state
- VRT map-set creation workflows
- elevation calculations

Those concerns belong to `map-manager` and `height-server`.

## Local Focus

If you are changing this service, you are usually working on:

- layer discovery
- tile serving
- raster previews
- map-facing metadata
