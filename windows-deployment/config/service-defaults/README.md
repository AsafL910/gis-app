# Service Config Defaults

This folder defines default config files that are seeded into:

`data/config/<service>/...`

during installation.

Rules:

- Keep only default templates here.
- The installer rewrites these files into `data/config/` on install and reinstall.
- That means package config changes replace prior installed config automatically.
- If a service is removed later, its old config under `data/config/<service>/` is left in place on purpose so data is not lost unexpectedly.

Recommended pattern for a new service:

```text
config/service-defaults/my-service/config.json
```

Services can also seed extra companion files next to `config.json`, for example:

```text
config/service-defaults/my-service/config.json
config/service-defaults/my-service/mapproxy.yaml
```

At runtime, the service should read:

```text
SERVICE_CONFIG_PATH
```

from the deployment manifest environment block.
