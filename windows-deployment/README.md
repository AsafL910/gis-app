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

## Build

Run this on a developer machine after pre-populating `windows-deployment/tools/`.

```powershell
cd gis-app\windows-deployment
.\build_package.ps1
```

The script does not download runtime tools anymore. You must place these files in `windows-deployment/tools/` first:

- Node.js portable zip
- Nginx portable zip
- `WinSW-x64.exe`

The build script will:

- use bundled portable Node.js, Nginx, and WinSW inputs
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
- If you update Python dependencies, rebuild the package so the copied `.pixi` environments stay in sync.
- WinSW is bundled into `deploy_package` as `GlbDemoService.exe`, so the target machine does not need separate access to WinSW.
- The same offline treatment applies to other portable runtime tools in the package, such as Node.js and Nginx.
