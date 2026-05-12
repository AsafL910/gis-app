# Mongo Transaction Demo

This is a minimal .NET 8 worker that retries until MongoDB is ready, opens a session, writes one document inside a transaction, commits it, and then stays alive.

Default configuration can be read from `SERVICE_CONFIG_PATH`, for example:

```json
{
  "serviceName": "mongo-transaction-demo",
  "mongo": {
    "connectionString": "mongodb://127.0.0.1:27017/?replicaSet=glb-rs0",
    "database": "glb_demo",
    "collection": "transaction_demo",
    "retrySeconds": 5
  }
}
```

When deployed through the Windows package, the manifest points `SERVICE_CONFIG_PATH` at:

- `C:\Program Files\GlbDemo\data\config\mongo-transaction-demo\config.json`

Environment variables still override the JSON values when they are present.

Supported environment variables:

- `MONGO_CONNECTION_STRING=mongodb://127.0.0.1:27017/?replicaSet=glb-rs0`
- `MONGO_DATABASE=glb_demo`
- `MONGO_COLLECTION=transaction_demo`
- `TRANSACTION_RETRY_SECONDS=5`

The project uses a local [NuGet.Config](D:/Courses/MAPS/israel/glb-demo/gis-app/mongo-transaction-demo/NuGet.Config). If your build environment does not allow direct access to `nuget.org`, replace that package source with your Artifactory or internal NuGet mirror.
