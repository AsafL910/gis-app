# Service Config Defaults

This folder defines default config files that are seeded into:

`data/config/<service>/...`

during installation.

Rules:

- Keep only default templates here.
- The installer copies a file only if the target file does not already exist.
- That means client changes under `data/config/` survive upgrades.
- If a service is removed later, its old config under `data/config/<service>/` is left in place on purpose so data is not lost unexpectedly.

Recommended pattern for a new service:

```text
config/service-defaults/my-service/config.json
```

At runtime, the service should read:

```text
SERVICE_CONFIG_PATH
```

from the deployment manifest environment block.
