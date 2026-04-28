# Height Server

The `height-server` microservice is the GDAL-backed calculation service.

Its job is intentionally narrow:

- open elevation datasets with GDAL
- transform coordinates into the dataset spatial reference system
- sample elevations at a point
- find the highest point inside a polygon

It is not responsible for cataloging files, creating map sets, or managing VRT workflows. Those responsibilities live in `map-manager`.

## Responsibilities

- `POST /get-elevation/`
- `POST /get-highest-point/`
- `POST /get-highest-point-geojson/`
- `GET /dataset-info/`
- `POST /reload-dataset/`

Requests can include `dataset_path` so the caller can choose which DTM or VRT to query.

## Runtime Role

This service is used when the application needs actual elevation results.

- The UI selects a DTM through `map-manager`.
- The selected dataset path is sent along with height requests.
- `height-server` loads that dataset and performs the GDAL work.

## Notes

- `DATA_DIR` points to the shared `/data` mount.
- If no explicit `dataset_path` is sent, the service falls back to `ELEV_FILENAME`.
- If the default dataset is a missing `.vrt`, the server can still build the configured default VRT from the top and bottom source files.

## Local Focus

If you are changing this service, you are usually working on:

- GDAL dataset loading
- raster sampling logic
- polygon scan logic
- coordinate transforms
