# Map Generation Service

This service provides a simple API to handle map generation tasks, including reprojecting GeoTIFF files, creating RGB tiles, and generating zoom-level folders for mapping layers.

## Features
- Reprojects GeoTIFF files to EPSG:4326.
- Generates RGB tiles from the GeoTIFF.
- Creates a tile pyramid with configurable zoom levels.
- Handles duplicate output directories with customizable options.

---

## How to Run

### Using Docker
Since setting up a Python environment with all dependencies can be challenging, we use Docker for simplicity.

1. Clone the repository.
2. Ensure all volumes are correctly linked to the necessary directories.
3. Run the service using Docker Compose:

   ```bash
   docker-compose up
   ```

   Alternatively, to run the service interactively:

   ```bash
   docker-compose run hat-generator-server
   ```

4. The service will start on `localhost:9000` with hot-reloading enabled, so any file changes will restart the service automatically.

---

## API Documentation

### Endpoint: `POST /generate-tiles/`

#### Request Body
Send a JSON payload with the following structure:

```json
{
    "tif_name": "israel.tif",                 // Name of the GeoTIFF file (must be in the data directory)
    "output_directory": "output",            // Path to the output directory
    "min_zoom": 8,                           // (Optional) Minimum zoom level, defaults to 8
    "max_zoom": 10,                          // (Optional) Maximum zoom level, defaults to 10
    "duplicate_option": "error"              // (Optional) Options: 'skip', 'override', or 'error'. Defaults to 'error'
}
```

#### Parameters Description:
| Parameter         | Type      | Description                                                                                     | Default  |
|-------------------|-----------|-------------------------------------------------------------------------------------------------|----------|
| `tif_name`        | `string`  | Name of the GeoTIFF file (located in the `data` directory).                                     | Required |
| `output_directory`| `string`  | Absolute or relative path to the directory where the output tiles will be stored.               | Required |
| `min_zoom`        | `integer` | Minimum zoom level. Must be between `1` and `20`.                                               | `8`      |
| `max_zoom`        | `integer` | Maximum zoom level. Must be between `1` and `20`.                                               | `10`     |
| `duplicate_option`| `string`  | How to handle duplicate output directories: `'skip'`, `'override'`, or `'error'`.               | `'error'`|

---

### Example Request

```bash
curl -X POST http://localhost:9000/generate-tiles/ \
-H "Content-Type: application/json" \
-d '{
    "tif_name": "israel.tif",
    "output_directory": "output",
    "min_zoom": 8,
    "max_zoom": 10,
    "duplicate_option": "override"
}'
```

---

## Output Structure

In the specified `output_directory`, you will find multiple subdirectories for each zoom level (e.g., `8`, `9`, `10`). These directories contain tiles ready for use as mapping layers in tools like Globus or other GIS platforms.

---

## Notes
- **Dependencies**: This service uses `FastAPI`, `GDAL`, and `rasterio`. These are bundled in the Docker container for easy deployment.
- **Development**: The service uses `uvicorn --reload` for hot-reloading during development.

---

### Contribution Guidelines
1. Fork the repository and create a feature branch.
2. Open a pull request with your changes.
3. Ensure all tests pass before submitting.

---

## License

This project is licensed under the [MIT License](LICENSE).

