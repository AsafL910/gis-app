# Bundled Tool Inputs

This folder holds build-time runtime inputs used by [`build_package.ps1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/build_package.ps1).

Canonical versions live in [`config/environments/default.psd1`](/D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/config/environments/default.psd1).

## Required For The Recommended Flow

- `node-v20.18.1-win-x64.zip`
- `nginx-1.30.0.zip`
- `WinSW-x64.exe`
- `dotnet-sdk-8.0.420-win-x64.zip`
- `mongodb-windows-x86_64-8.3.1.zip`
- `mongosh-2.8.3-win32-x64.zip`

## Optional Extracted Folders

If these extracted folders already exist, the matching zip is not needed:

- `node-v20.18.1-win-x64/`
- `nginx-1.30.0/`
- `dotnet-sdk-8.0.420-win-x64/`
- `mongodb-win32-x86_64-windows-8.3.1/`
- `mongosh-2.8.3-win32-x64/`

MongoDB is the odd one:

- download name: `mongodb-windows-x86_64-8.3.1.zip`
- extracted folder: `mongodb-win32-x86_64-windows-8.3.1/`

## Typical Flow

1. Populate `tools/` on a machine with internet access or via Artifactory.
2. Run:

```powershell
.\build_package.ps1
.\build_installer_exe.ps1
```

3. Deliver `deploy_package\` to the target machine.

## Notes

- These are build-time bundled inputs.
- `deploy_package\` contains the runtime pieces needed on the target machine.
- `WinSW-x64.exe` is copied into the package as `GlbDemoService.exe`.
- The portable .NET SDK is used both to build the example service and to run packaged .NET services via `dotnet.exe`.
- MongoDB runs from the portable zip layout in the package, so no MongoDB installer is needed.
