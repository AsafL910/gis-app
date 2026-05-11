# Bundled Tool Inputs

`build_package.ps1` does not download runtime tools anymore.

Before running the build, place these files in this `tools/` folder:

## Required files

- `node-v20.18.1-win-x64.zip`
- `nginx-1.30.0.zip`
- `WinSW-x64.exe`
- `dotnet-sdk-8.0.420-win-x64.zip`
- `mongodb-windows-x86_64-8.3.1.zip`
- `mongosh-2.8.3-win32-x64.zip`

## Optional extracted folders

The build script will also accept these extracted folders if they already exist:

- `node-v20.18.1-win-x64/`
- `nginx-1.30.0/`
- `dotnet-sdk-8.0.420-win-x64/`
- `mongodb-win32-x86_64-windows-8.3.1/`
- `mongosh-2.8.3-win32-x64/`

If an extracted folder exists, the corresponding zip is not needed.

For MongoDB specifically, the downloaded zip is named `mongodb-windows-x86_64-8.3.1.zip`, but it extracts into `mongodb-win32-x86_64-windows-8.3.1/`.

## Typical flow

1. Populate `tools/` on a machine that has internet access.
2. Keep those files under your private build storage or source archive.
3. Run:

```powershell
.\build_package.ps1
```

## Notes

- These are build-time bundled inputs.
- `deploy_package/` will include the runtime pieces needed on the target machine.
- `WinSW-x64.exe` is copied into the package as `GlbDemoService.exe`.
- The portable .NET SDK is used as the build tool and is also bundled so packaged .NET services can run via `dotnet.exe`.
- MongoDB runs from the portable zip layout in the package; no MSI install is required for this deployment model.
