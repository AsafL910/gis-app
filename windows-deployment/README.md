# Windows Deployment

This folder builds the offline Windows package for the GLB demo and keeps the deployment logic organized for day-to-day maintenance.

The rule of thumb is:

- root files are entrypoints people run
- `config/` holds canonical configuration
- `scripts/` holds reusable implementation
- `tools/` holds bundled build-time inputs
- `deploy_package/` is the final assembled payload

## Folder Map

```text
windows-deployment/
  build_package.ps1
  build_installer_exe.ps1
  initialize_sources.ps1
  install.ps1
  RunPackage.ps1
  GhostOrchestrator.ps1
  README.md
  config/
    deployment/
      deployment_manifest.json
      GlbDemoService.xml
      nginx-data.conf
      nginx-ui.conf
    environments/
      default.psd1
    sources/
      initialize_sources.example.json
  scripts/
    lib/
  bootstrapper/
  tools/
  deploy_package/
```

## What To Run

Normal packaging flow:

```powershell
cd D:\Courses\MAPS\israel\glb-demo\gis-app\windows-deployment
.\initialize_sources.ps1 -Manifest .\config\sources\initialize_sources.example.json
.\build_package.ps1
.\build_installer_exe.ps1
```

Target-machine install:

```powershell
.\Setup.exe
```

SCCM-style silent install:

```text
Setup.exe /quiet /log C:\Windows\Temp\GlbDemoInstall.log
```

## Service Lifecycle Rules

When you remove a service:

- delete its build/package logic from [`scripts/build/Build-Package.ps1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/scripts/build/Build-Package.ps1)
- delete its runtime entry from [`config/deployment/deployment_manifest.json`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/config/deployment/deployment_manifest.json)
- rebuild and reinstall

What the installer does:

- it removes the old installed runtime tree under `C:\Program Files\GlbDemo` except `data/`
- that means removed service binaries disappear automatically on reinstall
- it preserves `data/`, so service data and config are not deleted automatically

That last rule is intentional. If you remove a service permanently, you can manually clean:

```text
C:\Program Files\GlbDemo\data\config\<service-name>\
```

after you confirm you no longer need it.

## Clear Build And Install Order

Build order:

1. `initialize_sources.ps1`
   Populates repos, runtime zips, and artifacts before packaging.
2. `build_package.ps1`
   Resolves service dependencies, builds services, and assembles `deploy_package\`.
3. `build_installer_exe.ps1`
   Compiles `Setup.exe` and drops it into `deploy_package\`.

Install order inside `install.ps1`:

1. Stop the existing service and release file locks.
2. Copy package files into the install directory.
3. Patch Nginx config paths for the target machine.
4. Create logs and register the Windows service.
5. Start the service and verify the UI comes up.

That order is implemented in [`install.ps1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/install.ps1).

## Where Junior Devs Should Edit

When adding or changing a service, start here:

- [`config/deployment/deployment_manifest.json`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/config/deployment/deployment_manifest.json)
  Add the runtime service definition used by the orchestrator.
- [`build_package.ps1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/build_package.ps1)
  Add the build step and package-copy step for the new service.
- [`config/environments/default.psd1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/config/environments/default.psd1)
  Update shared settings like ports, tool versions, install defaults, and key config paths.
- [`config/service-defaults/README.md`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/config/service-defaults/README.md)
  Add the default `config.json` template that should be seeded for new installs.

Checklist for adding a new service:

1. Add the service runtime definition in [`config/deployment/deployment_manifest.json`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/config/deployment/deployment_manifest.json).
2. Add its build and package copy logic in [`scripts/build/Build-Package.ps1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/scripts/build/Build-Package.ps1).
3. Add a default config template under [`config/service-defaults/`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/config/service-defaults/).
4. Set `SERVICE_CONFIG_PATH` in the service `env` block so the runtime knows where to read config from.
5. If the service needs a new external port, add it to [`config/environments/default.psd1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/config/environments/default.psd1).

When changing runtime behavior, start here:

- [`GhostOrchestrator.ps1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/GhostOrchestrator.ps1)
  Main runtime startup loop.
- [`scripts/lib/Runtime.Helpers.ps1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/scripts/lib/Runtime.Helpers.ps1)
  Shared helpers for service launch, environment variables, and Mongo replica set setup.

When changing installation behavior, start here:

- [`install.ps1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/install.ps1)
  The ordered install pipeline.
- [`scripts/lib/Install.Helpers.ps1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/scripts/lib/Install.Helpers.ps1)
  Shared helpers for locking, copying, uninstall, and diagnostics.

When changing build tooling or layout, start here:

- [`scripts/lib/Layout.ps1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/scripts/lib/Layout.ps1)
  Shared path layout and environment loading.
- [`scripts/lib/Common.ps1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/scripts/lib/Common.ps1)
  Reusable generic helpers.

## Script Layout

Runnable scripts stay at the top level:

- [`build_package.ps1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/build_package.ps1)
- [`build_installer_exe.ps1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/build_installer_exe.ps1)
- [`initialize_sources.ps1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/initialize_sources.ps1)
- [`install.ps1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/install.ps1)
- [`RunPackage.ps1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/RunPackage.ps1)
- [`GhostOrchestrator.ps1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/GhostOrchestrator.ps1)

Only shared helper code lives under `scripts/lib/`.

## Runtime Architecture

```text
Windows SCM
  -> GlbDemoService (WinSW)
    -> GhostOrchestrator.ps1
      -> mongod.exe
      -> dotnet.exe
      -> nginx.exe
      -> nginx.exe
      -> .pixi Python
      -> .pixi Python
      -> node.exe
```

The service definitions that drive this are in [`config/deployment/deployment_manifest.json`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/config/deployment/deployment_manifest.json).

## Package Layout

After `build_package.ps1`, the payload is organized like this:

```text
deploy_package/
  Setup.exe
  install.ps1
  RunPackage.ps1
  GhostOrchestrator.ps1
  GlbDemoService.exe
  GlbDemoService.xml
  config/
    deployment/
    environments/
    service-defaults/
  scripts/
    lib/
  services/
  node/
  dotnet/
  mongodb/
  mongosh/
  nginx/
  data/
```

## Initialize Sources

[`config/sources/initialize_sources.example.json`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/config/sources/initialize_sources.example.json) is the reference manifest for non-monorepo setups.

It supports:

- `git` sources for service repos
- `artifact` sources for Artifactory downloads and runtime zips
- `local` sources for machine-local inputs

Plan mode:

```powershell
.\initialize_sources.ps1 -Manifest .\config\sources\initialize_sources.example.json -PlanOnly
```

Overwrite mode:

```powershell
.\initialize_sources.ps1 -Manifest .\config\sources\initialize_sources.example.json -OverwriteExisting
```

## Tools

Build-time bundled inputs live under `tools/`. See [`tools/README.md`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/tools/README.md).

## Configuration Model

The deployment now uses one standard config convention for services:

- package defaults live under [`config/service-defaults/`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/config/service-defaults/)
- install-time persisted config lives under:
  `C:\Program Files\GlbDemo\data\config\<service-name>\`
- the installer seeds defaults only when a config file does not already exist
- service upgrades do not overwrite client-edited config files

Runtime wiring:

- the deployment manifest can set `SERVICE_CONFIG_PATH`
- `${DATA_DIR}` and `${BASE_DIR}` placeholders are resolved by the orchestrator before launching the service

Example:

```json
"env": {
  "SERVICE_CONFIG_PATH": "${DATA_DIR}\\config\\my-service\\config.json"
}
```

## Local Runtime Debug

To debug the package without installing the Windows service:

```powershell
.\RunPackage.ps1
```

That runs the packaged orchestrator in the foreground and is the fastest way to see whether the assembled payload itself is healthy.
