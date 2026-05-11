# Mongo Transaction Demo

This is a minimal .NET 8 worker that retries until MongoDB is ready, opens a session, writes one document inside a transaction, commits it, and then stays alive.

Default environment variables:

- `MONGO_CONNECTION_STRING=mongodb://127.0.0.1:27017/?replicaSet=glb-rs0`
- `MONGO_DATABASE=glb_demo`
- `MONGO_COLLECTION=transaction_demo`
- `TRANSACTION_RETRY_SECONDS=5`

The project uses a local [NuGet.Config](D:/Courses/MAPS/israel/glb-demo/gis-app/mongo-transaction-demo/NuGet.Config). If your build environment does not allow direct access to `nuget.org`, replace that package source with your Artifactory or internal NuGet mirror.
