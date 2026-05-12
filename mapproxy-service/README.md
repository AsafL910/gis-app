# MapProxy Service

This service is a thin Python wrapper around:

`mapproxy-util serve-develop`

It reads a JSON config from `SERVICE_CONFIG_PATH`, renders a MapProxy YAML template with environment-variable placeholders, and launches MapProxy on the configured host and port.

## Config shape

```json
{
  "host": "0.0.0.0",
  "port": 8070,
  "mapproxy_yaml": "${DATA_DIR}\\config\\mapproxy-service\\mapproxy.yaml",
  "generated_yaml_path": "${DATA_DIR}\\config\\mapproxy-service\\mapproxy.rendered.yaml",
  "environment": {
    "PRIMARY_GPKG_PATH": "${DATA_DIR}\\raster\\primary.gpkg"
  }
}
```

Any `${VAR_NAME}` placeholders in the YAML template are replaced from the process environment plus the `environment` block in `config.json`.
