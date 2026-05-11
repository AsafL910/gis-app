# Bundled Tool Inputs

`build_package.ps1` does not download runtime tools anymore.

Before running the build, place these files in this `tools/` folder:

## Required files

- `node-v20.18.1-win-x64.zip`
- `nginx-1.30.0.zip`
- `WinSW-x64.exe`

## Optional extracted folders

The build script will also accept these extracted folders if they already exist:

- `node-v20.18.1-win-x64/`
- `nginx-1.30.0/`

If an extracted folder exists, the corresponding zip is not needed.

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
