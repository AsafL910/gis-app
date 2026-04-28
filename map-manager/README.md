# Map Manager

The `map-manager` microservice is the application management backend written in Node.js and TypeScript.

It owns the workflow-oriented parts of the GIS app that do not need GDAL Python bindings.

## Responsibilities

- scan the shared data directory for raster and DTM files
- return a catalog of available sources
- create map-set manifests
- build DTM VRT files with `gdalbuildvrt`
- store the currently selected DTM path for the UI

## Runtime Role

This service sits between the UI and the data directory:

- `map-provider-ui` calls it to get file catalogs
- `map-provider-ui` asks it to generate VRT map sets
- `map-provider-ui` asks it to store which DTM is currently selected

It does not perform elevation calculations itself.

## Boundaries

This service should not own:

- raster math
- GDAL point sampling logic
- highest-point polygon search

Those belong to `height-server`.

## Notes

- The service expects the shared data directory at `DATA_DIR`.
- Generated manifests and VRT outputs are written under `data/mapsets`.
- Selected dataset state is stored for the application, but the height service is no longer driven by shared mutable activation state.

## Local Focus

If you are changing this service, you are usually working on:

- catalog endpoints
- map-set generation workflows
- path validation
- VRT creation process
