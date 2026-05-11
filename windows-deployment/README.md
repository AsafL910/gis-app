# Windows Deployment - GLB Demo

This folder builds an offline Windows deployment package that runs the full GIS stack as a single Windows Service.

## Important Change

The Python services now use their own copied Pixi environments instead of a shared embedded Python with `pip install`.

That means the offline package is built from the already-resolved service environments:

- `height-server/.pixi`
- `map-provider/.pixi`

No runtime `pip install` is needed on the target Windows machine.

## Runtime Architecture

```text
Windows SCM
  -> GlbDemoService (WinSW)
    -> GhostOrchestrator.ps1
      -> mongod.exe             mongo-db (single-node replica set)
      -> nginx.exe              data-http
      -> nginx.exe              map-provider-ui
      -> .pixi Python           height-server
      -> .pixi Python           map-provider
      -> node.exe               map-manager
```

## Package Layout

```text
deploy_package/
  GlbDemoService.exe
  GlbDemoService.xml
  GhostOrchestrator.ps1
  RunPackage.ps1
  deployment_manifest.json
  install.ps1
  node/
    node.exe
  mongodb/
    bin/
      mongod.exe
  mongosh/
    bin/
      mongosh.exe
  nginx/
    nginx.exe
    conf/
  services/
    height-server/
      src/
      pixi.toml
      pixi.lock
      .pixi/
    map-provider/
      src/
      pixi.toml
      .pixi/
    map-manager/
      dist/
      node_modules/
      package.json
    map-provider-ui/
      dist/
  data/
```

## Initialize And Build

Run this on a developer machine after preparing an initialization manifest.

```powershell
cd gis-app\windows-deployment
.\initialize_sources.ps1 -Manifest .\initialize_sources.example.json
.\build_package.ps1
```

The initializer is the setup step before packaging. It can:

- clone service repos from git
- download runtime tools from Artifactory or another artifact store
- download MongoDB portable runtimes from Artifactory or another artifact store
- unpack exported environments such as `.pixi`
- copy local inputs such as shared data folders

By default it does not overwrite existing content. If you want it to replace an existing repo, file, or folder, run it with:

```powershell
.\initialize_sources.ps1 -Manifest .\initialize_sources.example.json -OverwriteExisting
```

`build_package.ps1` still expects these runtime inputs to exist under `windows-deployment/tools/`:

- Node.js portable zip
- Nginx portable zip
- `WinSW-x64.exe`
- MongoDB portable zip
- mongosh portable zip

After initialization, the build script will:

- use bundled portable Node.js, Nginx, and WinSW inputs
- use bundled portable MongoDB and mongosh inputs
- run `pixi install` in `height-server` and `map-provider`
- run runtime smoke checks for the bundled Python environments before packaging
- build the frontend and map-manager
- assemble `deploy_package/`

## Install

Copy `deploy_package/` to the target Windows machine and run:

```powershell
.\install.ps1
```

Run it as Administrator.

## Local Package Debug

Before installing the Windows Service, you can validate the package directly:

```powershell
.\RunPackage.ps1
```

This runs `GhostOrchestrator.ps1` in the foreground and is the recommended first check when debugging package startup. It avoids WinSW and makes it easier to confirm whether the packaged services themselves can start.

## Notes

- The Python executables used at runtime are the service-local Pixi interpreters referenced in `deployment_manifest.json`.
- MongoDB is bundled as a portable runtime and started by the orchestrator with `--replSet` so future services can rely on replica-set-only features such as transactions or change streams.
- For this packaging model, MongoDB does not need an MSI installer. The portable zip plus `mongosh` is enough.
- If you update Python dependencies, rebuild the package so the copied `.pixi` environments stay in sync.
- WinSW is bundled into `deploy_package` as `GlbDemoService.exe`, so the target machine does not need separate access to WinSW.
- The same offline treatment applies to other portable runtime tools in the package, such as Node.js and Nginx.
