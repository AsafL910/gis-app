function Invoke-WithCleanPythonEnv {
    param([scriptblock]$Command)

    $previousPath = $env:PATH
    $previousGdalData = $env:GDAL_DATA
    $previousProjLib = $env:PROJ_LIB
    $previousUsePathForGdalPython = $env:USE_PATH_FOR_GDAL_PYTHON

    try {
        Remove-Item Env:GDAL_DATA -ErrorAction SilentlyContinue
        Remove-Item Env:PROJ_LIB -ErrorAction SilentlyContinue
        Remove-Item Env:USE_PATH_FOR_GDAL_PYTHON -ErrorAction SilentlyContinue
        & $Command
    } finally {
        $env:PATH = $previousPath

        if ($null -ne $previousGdalData) { $env:GDAL_DATA = $previousGdalData } else { Remove-Item Env:GDAL_DATA -ErrorAction SilentlyContinue }
        if ($null -ne $previousProjLib) { $env:PROJ_LIB = $previousProjLib } else { Remove-Item Env:PROJ_LIB -ErrorAction SilentlyContinue }
        if ($null -ne $previousUsePathForGdalPython) { $env:USE_PATH_FOR_GDAL_PYTHON = $previousUsePathForGdalPython } else { Remove-Item Env:USE_PATH_FOR_GDAL_PYTHON -ErrorAction SilentlyContinue }
    }
}

function Test-PythonEnv {
    param(
        [string]$Name,
        [string]$PythonExe,
        [string]$InlineCheck
    )

    $previousPath = $env:PATH
    $previousGdalData = $env:GDAL_DATA
    $previousProjLib = $env:PROJ_LIB
    $previousUsePathForGdalPython = $env:USE_PATH_FOR_GDAL_PYTHON
    $envRoot = Split-Path $PythonExe -Parent
    $sitePackages = Join-Path (Join-Path $envRoot "Lib") "site-packages"
    $projCandidates = @(
        (Join-Path (Join-Path $envRoot "Library") "share\proj"),
        (Join-Path $sitePackages "rasterio\proj_data"),
        (Join-Path (Join-Path (Join-Path $sitePackages "pyproj") "proj_dir") "share\proj")
    )
    $gdalCandidates = @(
        (Join-Path (Join-Path $envRoot "Library") "share\gdal"),
        (Join-Path $sitePackages "rasterio\gdal_data")
    )

    $env:PATH = [string]::Join(";", @(
        (Join-Path $envRoot "Library\bin"),
        (Join-Path $envRoot "Scripts"),
        $envRoot,
        $env:PATH
    ))
    $env:USE_PATH_FOR_GDAL_PYTHON = "1"

    foreach ($candidate in $gdalCandidates) {
        if (Test-Path $candidate) {
            $env:GDAL_DATA = $candidate
            break
        }
    }

    foreach ($candidate in $projCandidates) {
        if (Test-Path $candidate) {
            $env:PROJ_LIB = $candidate
            break
        }
    }

    try {
        Invoke-Step -Description "runtime smoke test ($Name)" -Command {
            & $PythonExe -c $InlineCheck
        }
    } finally {
        $env:PATH = $previousPath

        if ($null -ne $previousGdalData) { $env:GDAL_DATA = $previousGdalData } else { Remove-Item Env:GDAL_DATA -ErrorAction SilentlyContinue }
        if ($null -ne $previousProjLib) { $env:PROJ_LIB = $previousProjLib } else { Remove-Item Env:PROJ_LIB -ErrorAction SilentlyContinue }
        if ($null -ne $previousUsePathForGdalPython) { $env:USE_PATH_FOR_GDAL_PYTHON = $previousUsePathForGdalPython } else { Remove-Item Env:USE_PATH_FOR_GDAL_PYTHON -ErrorAction SilentlyContinue }
    }
}

function Invoke-WithDotnetEnv {
    param(
        [string]$BaseDir,
        [scriptblock]$Command
    )

    $previousDotnetCliHome = $env:DOTNET_CLI_HOME
    $previousDotnetTelemetry = $env:DOTNET_CLI_TELEMETRY_OPTOUT
    $previousDotnetLookup = $env:DOTNET_MULTILEVEL_LOOKUP
    $previousNugetPackages = $env:NUGET_PACKAGES
    $previousAppData = $env:APPDATA
    $previousLocalAppData = $env:LOCALAPPDATA
    $dotnetCliHome = Join-Path $BaseDir ".dotnet-cli"
    $nugetPackages = Join-Path $BaseDir ".nuget-packages"
    $appDataRoot = Join-Path $BaseDir ".appdata"
    $roamingAppData = Join-Path $appDataRoot "Roaming"
    $localAppData = Join-Path $appDataRoot "Local"

    try {
        New-Item -ItemType Directory -Force -Path $dotnetCliHome | Out-Null
        New-Item -ItemType Directory -Force -Path $nugetPackages | Out-Null
        New-Item -ItemType Directory -Force -Path $roamingAppData | Out-Null
        New-Item -ItemType Directory -Force -Path $localAppData | Out-Null
        $env:DOTNET_CLI_HOME = $dotnetCliHome
        $env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
        $env:DOTNET_MULTILEVEL_LOOKUP = "0"
        $env:NUGET_PACKAGES = $nugetPackages
        $env:APPDATA = $roamingAppData
        $env:LOCALAPPDATA = $localAppData
        & $Command
    } finally {
        if ($null -ne $previousDotnetCliHome) { $env:DOTNET_CLI_HOME = $previousDotnetCliHome } else { Remove-Item Env:DOTNET_CLI_HOME -ErrorAction SilentlyContinue }
        if ($null -ne $previousDotnetTelemetry) { $env:DOTNET_CLI_TELEMETRY_OPTOUT = $previousDotnetTelemetry } else { Remove-Item Env:DOTNET_CLI_TELEMETRY_OPTOUT -ErrorAction SilentlyContinue }
        if ($null -ne $previousDotnetLookup) { $env:DOTNET_MULTILEVEL_LOOKUP = $previousDotnetLookup } else { Remove-Item Env:DOTNET_MULTILEVEL_LOOKUP -ErrorAction SilentlyContinue }
        if ($null -ne $previousNugetPackages) { $env:NUGET_PACKAGES = $previousNugetPackages } else { Remove-Item Env:NUGET_PACKAGES -ErrorAction SilentlyContinue }
        if ($null -ne $previousAppData) { $env:APPDATA = $previousAppData } else { Remove-Item Env:APPDATA -ErrorAction SilentlyContinue }
        if ($null -ne $previousLocalAppData) { $env:LOCALAPPDATA = $previousLocalAppData } else { Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue }
    }
}
