$ErrorActionPreference = "Stop"

$SCRIPT_DIR = $PSScriptRoot
$PROJECT_ROOT = Split-Path $SCRIPT_DIR -Parent
$PKG = Join-Path $SCRIPT_DIR "deploy_package"
$TOOLS = Join-Path $SCRIPT_DIR "tools"

function Require-ToolFile {
    param(
        [string]$Path,
        [string]$Description
    )

    if (Test-Path $Path) {
        return
    }

    throw "Missing bundled tool input: $Description at '$Path'. Place it under windows-deployment\tools before building."
}

function Invoke-Step {
    param(
        [string]$Description,
        [scriptblock]$Command
    )

    Write-Host "    $Description" -ForegroundColor DarkGray
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

function Stop-ProcessesUnderPath {
    param(
        [string]$RootPath
    )

    if (-not (Test-Path $RootPath)) {
        return
    }

    $normalizedRoot = $RootPath.ToLowerInvariant()
    $processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue
    foreach ($proc in $processes) {
        $exePath = $proc.ExecutablePath
        $commandLine = $proc.CommandLine
        $matchesRoot = $false

        if (-not [string]::IsNullOrWhiteSpace($exePath) -and $exePath.ToLowerInvariant().StartsWith($normalizedRoot)) {
            $matchesRoot = $true
        }

        if (-not $matchesRoot -and -not [string]::IsNullOrWhiteSpace($commandLine) -and $commandLine.ToLowerInvariant().Contains($normalizedRoot)) {
            $matchesRoot = $true
        }

        if (-not $matchesRoot) {
            continue
        }

        try {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
            Write-Host "  Stopped process $($proc.Name) (PID $($proc.ProcessId)) using $RootPath" -ForegroundColor DarkYellow
        } catch {
        }
    }
}

function Invoke-WithCleanPythonEnv {
    param(
        [scriptblock]$Command
    )

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

        if ($null -ne $previousGdalData) {
            $env:GDAL_DATA = $previousGdalData
        } else {
            Remove-Item Env:GDAL_DATA -ErrorAction SilentlyContinue
        }

        if ($null -ne $previousProjLib) {
            $env:PROJ_LIB = $previousProjLib
        } else {
            Remove-Item Env:PROJ_LIB -ErrorAction SilentlyContinue
        }

        if ($null -ne $previousUsePathForGdalPython) {
            $env:USE_PATH_FOR_GDAL_PYTHON = $previousUsePathForGdalPython
        } else {
            Remove-Item Env:USE_PATH_FOR_GDAL_PYTHON -ErrorAction SilentlyContinue
        }
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

        if ($null -ne $previousGdalData) {
            $env:GDAL_DATA = $previousGdalData
        } else {
            Remove-Item Env:GDAL_DATA -ErrorAction SilentlyContinue
        }

        if ($null -ne $previousProjLib) {
            $env:PROJ_LIB = $previousProjLib
        } else {
            Remove-Item Env:PROJ_LIB -ErrorAction SilentlyContinue
        }

        if ($null -ne $previousUsePathForGdalPython) {
            $env:USE_PATH_FOR_GDAL_PYTHON = $previousUsePathForGdalPython
        } else {
            Remove-Item Env:USE_PATH_FOR_GDAL_PYTHON -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-WithDotnetEnv {
    param(
        [scriptblock]$Command
    )

    $previousDotnetCliHome = $env:DOTNET_CLI_HOME
    $previousDotnetTelemetry = $env:DOTNET_CLI_TELEMETRY_OPTOUT
    $previousDotnetLookup = $env:DOTNET_MULTILEVEL_LOOKUP
    $previousNugetPackages = $env:NUGET_PACKAGES
    $previousAppData = $env:APPDATA
    $previousLocalAppData = $env:LOCALAPPDATA
    $dotnetCliHome = Join-Path $SCRIPT_DIR ".dotnet-cli"
    $nugetPackages = Join-Path $SCRIPT_DIR ".nuget-packages"
    $appDataRoot = Join-Path $SCRIPT_DIR ".appdata"
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

if (Test-Path $PKG) {
    Stop-ProcessesUnderPath -RootPath $PKG
    Start-Sleep -Seconds 1
    Remove-Item -Recurse -Force $PKG
}
New-Item -ItemType Directory -Path $PKG | Out-Null
if (-not (Test-Path $TOOLS)) { New-Item -ItemType Directory -Path $TOOLS | Out-Null }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  GLB Demo - Building deploy package" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$NODE_VERSION = "20.18.1"
$NODE_ZIP = Join-Path $TOOLS "node-v${NODE_VERSION}-win-x64.zip"
$NODE_DIR = Join-Path $TOOLS "node-v${NODE_VERSION}-win-x64"
$NPM_CMD = Join-Path $NODE_DIR "npm.cmd"

if (-not (Test-Path $NODE_DIR)) {
    Write-Host "[1/3] Preparing Node.js v$NODE_VERSION..." -ForegroundColor Yellow
    Require-ToolFile -Path $NODE_ZIP -Description "Node.js portable archive"
    Expand-Archive -Path $NODE_ZIP -DestinationPath $TOOLS -Force
    Write-Host "  Done." -ForegroundColor Green
} else {
    Write-Host "[1/3] Node.js v$NODE_VERSION cached." -ForegroundColor Green
}

$NGINX_VERSION = "1.30.0"
$NGINX_ZIP = Join-Path $TOOLS "nginx-${NGINX_VERSION}.zip"
$NGINX_DIR = Join-Path $TOOLS "nginx-${NGINX_VERSION}"

if (-not (Test-Path $NGINX_DIR)) {
    Write-Host "[2/3] Preparing Nginx v$NGINX_VERSION..." -ForegroundColor Yellow
    Require-ToolFile -Path $NGINX_ZIP -Description "Nginx portable archive"
    Expand-Archive -Path $NGINX_ZIP -DestinationPath $TOOLS -Force
    Write-Host "  Done." -ForegroundColor Green
} else {
    Write-Host "[2/3] Nginx v$NGINX_VERSION cached." -ForegroundColor Green
}

$WINSW_VERSION = "2.12.0"
$WINSW_EXE = Join-Path $TOOLS "WinSW-x64.exe"

if (-not (Test-Path $WINSW_EXE)) {
    Write-Host "[3/3] Preparing WinSW v$WINSW_VERSION..." -ForegroundColor Yellow
    Require-ToolFile -Path $WINSW_EXE -Description "WinSW executable"
    Write-Host "  Done." -ForegroundColor Green
} else {
    Write-Host "[3/3] WinSW v$WINSW_VERSION cached." -ForegroundColor Green
}

$MONGODB_VERSION = "8.3.1"
$MONGODB_ZIP = Join-Path $TOOLS "mongodb-windows-x86_64-$MONGODB_VERSION.zip"
$MONGODB_DIR = Join-Path $TOOLS "mongodb-win32-x86_64-windows-$MONGODB_VERSION"
if (-not (Test-Path $MONGODB_DIR)) {
    Write-Host "[mongo] Preparing MongoDB v$MONGODB_VERSION..." -ForegroundColor Yellow
    Require-ToolFile -Path $MONGODB_ZIP -Description "MongoDB portable archive"
    Expand-Archive -Path $MONGODB_ZIP -DestinationPath $TOOLS -Force
    Write-Host "  Done." -ForegroundColor Green
} else {
    Write-Host "[mongo] MongoDB v$MONGODB_VERSION cached." -ForegroundColor Green
}

$MONGOSH_VERSION = "2.8.3"
$MONGOSH_ZIP = Join-Path $TOOLS "mongosh-$MONGOSH_VERSION-win32-x64.zip"
$MONGOSH_DIR = Join-Path $TOOLS "mongosh-$MONGOSH_VERSION-win32-x64"
if (-not (Test-Path $MONGOSH_DIR)) {
    Write-Host "[mongo] Preparing mongosh v$MONGOSH_VERSION..." -ForegroundColor Yellow
    Require-ToolFile -Path $MONGOSH_ZIP -Description "mongosh portable archive"
    Expand-Archive -Path $MONGOSH_ZIP -DestinationPath $TOOLS -Force
    Write-Host "  Done." -ForegroundColor Green
} else {
    Write-Host "[mongo] mongosh v$MONGOSH_VERSION cached." -ForegroundColor Green
}

$DOTNET_VERSION = "8.0.420"
$DOTNET_ZIP = Join-Path $TOOLS "dotnet-sdk-$DOTNET_VERSION-win-x64.zip"
$DOTNET_DIR = Join-Path $TOOLS "dotnet-sdk-$DOTNET_VERSION-win-x64"
if (-not (Test-Path (Join-Path $DOTNET_DIR "dotnet.exe"))) {
    Write-Host "[dotnet] Preparing .NET SDK v$DOTNET_VERSION..." -ForegroundColor Yellow
    Require-ToolFile -Path $DOTNET_ZIP -Description ".NET SDK archive"
    if (-not (Test-Path $DOTNET_DIR)) { New-Item -ItemType Directory -Path $DOTNET_DIR | Out-Null }
    Expand-Archive -Path $DOTNET_ZIP -DestinationPath $DOTNET_DIR -Force
    Write-Host "  Done." -ForegroundColor Green
} else {
    Write-Host "[dotnet] .NET SDK v$DOTNET_VERSION cached." -ForegroundColor Green
}

$DOTNET_EXE = Join-Path $DOTNET_DIR "dotnet.exe"

Write-Host ""
Write-Host "Building application services..." -ForegroundColor Cyan

$HS_DIR = Join-Path $PROJECT_ROOT "height-server"
$MP_DIR = Join-Path $PROJECT_ROOT "map-provider"
$UI_DIR = Join-Path $PROJECT_ROOT "map-provider-ui"
$MM_DIR = Join-Path $PROJECT_ROOT "map-manager"
$MTD_DIR = Join-Path $PROJECT_ROOT "mongo-transaction-demo"

Write-Host "  Resolving Pixi env for height-server..." -ForegroundColor Yellow
Push-Location $HS_DIR
Invoke-WithCleanPythonEnv -Command {
    Invoke-Step -Description "pixi install (height-server)" -Command { pixi install }
}
Test-PythonEnv -Name "height-server" -PythonExe (Join-Path $HS_DIR ".pixi\envs\default\python.exe") -InlineCheck "from osgeo import gdal; import pyproj; print('height-server runtime ok')"
Pop-Location
Write-Host "    Done." -ForegroundColor Green

Write-Host "  Resolving Pixi env for map-provider..." -ForegroundColor Yellow
Push-Location $MP_DIR
Invoke-WithCleanPythonEnv -Command {
    Invoke-Step -Description "pixi install (map-provider)" -Command { pixi install }
}
Test-PythonEnv -Name "map-provider" -PythonExe (Join-Path $MP_DIR ".pixi\envs\default\python.exe") -InlineCheck "import rasterio, titiler.core, uvicorn; print('map-provider runtime ok')"
Pop-Location
Write-Host "    Done." -ForegroundColor Green

Write-Host "  Building map-provider-ui..." -ForegroundColor Yellow
Push-Location $UI_DIR
Invoke-Step -Description "npm install (map-provider-ui)" -Command { & $NPM_CMD install --silent }
Invoke-Step -Description "npm run build (map-provider-ui)" -Command { & $NPM_CMD run build }
Pop-Location
Write-Host "    Done." -ForegroundColor Green

Write-Host "  Building map-manager..." -ForegroundColor Yellow
Push-Location $MM_DIR
Invoke-Step -Description "npm install (map-manager)" -Command { & $NPM_CMD install --silent }
Invoke-Step -Description "npm run build (map-manager)" -Command { & $NPM_CMD run build }
Pop-Location
Write-Host "    Done." -ForegroundColor Green

$MTD_PUBLISH_DIR = Join-Path $MTD_DIR "bin\Release\net8.0\publish"
$MTD_NUGET_CONFIG = Join-Path $MTD_DIR "NuGet.Config"
Write-Host "  Publishing mongo-transaction-demo..." -ForegroundColor Yellow
Push-Location $MTD_DIR
Invoke-WithDotnetEnv -Command {
    Invoke-Step -Description "dotnet restore (mongo-transaction-demo)" -Command { & $DOTNET_EXE restore --configfile $MTD_NUGET_CONFIG }
    Invoke-Step -Description "dotnet publish (mongo-transaction-demo)" -Command { & $DOTNET_EXE publish --no-restore -c Release -o $MTD_PUBLISH_DIR }
}
Pop-Location
Write-Host "    Done." -ForegroundColor Green

Write-Host ""
Write-Host "Assembling deploy_package..." -ForegroundColor Cyan

$pkgNode = Join-Path $PKG "node"
New-Item -ItemType Directory -Path $pkgNode | Out-Null
Copy-Item (Join-Path $NODE_DIR "node.exe") $pkgNode
$pkgDotnet = Join-Path $PKG "dotnet"
New-Item -ItemType Directory -Path $pkgDotnet | Out-Null
Copy-Item -Recurse (Join-Path $DOTNET_DIR "*") $pkgDotnet

Copy-Item -Recurse $NGINX_DIR (Join-Path $PKG "nginx")
$pkgMongo = Join-Path $PKG "mongodb"
$pkgMongoShell = Join-Path $PKG "mongosh"
New-Item -ItemType Directory -Path $pkgMongo | Out-Null
New-Item -ItemType Directory -Path $pkgMongoShell | Out-Null
Copy-Item -Recurse (Join-Path $MONGODB_DIR "*") $pkgMongo
Copy-Item -Recurse (Join-Path $MONGOSH_DIR "*") $pkgMongoShell

$nginxConf = Join-Path (Join-Path $PKG "nginx") "conf"
if (-not (Test-Path $nginxConf)) { New-Item -ItemType Directory -Path $nginxConf | Out-Null }
Copy-Item (Join-Path $SCRIPT_DIR "nginx-data.conf") (Join-Path $nginxConf "nginx-data.conf")
Copy-Item (Join-Path $SCRIPT_DIR "nginx-ui.conf") (Join-Path $nginxConf "nginx-ui.conf")

$svcDir = Join-Path $PKG "services"
New-Item -ItemType Directory -Path $svcDir | Out-Null

Write-Host "  Copying height-server source + Pixi env..." -ForegroundColor Yellow
$hsDest = Join-Path $svcDir "height-server"
New-Item -ItemType Directory -Path $hsDest | Out-Null
Copy-Item -Recurse (Join-Path $HS_DIR "src") (Join-Path $hsDest "src")
Copy-Item (Join-Path $HS_DIR "pixi.toml") $hsDest
Copy-Item (Join-Path $HS_DIR "pixi.lock") $hsDest
Copy-Item -Recurse (Join-Path $HS_DIR ".pixi") (Join-Path $hsDest ".pixi")
Get-ChildItem -Path $hsDest -Recurse -Directory -Filter "__pycache__" | Remove-Item -Recurse -Force

Write-Host "  Copying map-provider source + Pixi env..." -ForegroundColor Yellow
$mpDest = Join-Path $svcDir "map-provider"
New-Item -ItemType Directory -Path $mpDest | Out-Null
Copy-Item -Recurse (Join-Path $MP_DIR "src") (Join-Path $mpDest "src")
Copy-Item (Join-Path $MP_DIR "pixi.toml") $mpDest
Copy-Item (Join-Path $MP_DIR "pixi.lock") $mpDest
Copy-Item -Recurse (Join-Path $MP_DIR ".pixi") (Join-Path $mpDest ".pixi")
Get-ChildItem -Path $mpDest -Recurse -Directory -Filter "__pycache__" | Remove-Item -Recurse -Force

Write-Host "  Copying map-manager..." -ForegroundColor Yellow
$mmDest = Join-Path $svcDir "map-manager"
New-Item -ItemType Directory -Path $mmDest | Out-Null
Copy-Item -Recurse (Join-Path $MM_DIR "dist") (Join-Path $mmDest "dist")
Copy-Item -Recurse (Join-Path $MM_DIR "node_modules") (Join-Path $mmDest "node_modules")
Copy-Item (Join-Path $MM_DIR "package.json") (Join-Path $mmDest "package.json")

Write-Host "  Copying map-provider-ui..." -ForegroundColor Yellow
$uiDest = Join-Path $svcDir "map-provider-ui"
New-Item -ItemType Directory -Path $uiDest | Out-Null
Copy-Item -Recurse (Join-Path $UI_DIR "dist") (Join-Path $uiDest "dist")

Write-Host "  Copying mongo-transaction-demo publish output..." -ForegroundColor Yellow
$mtdDest = Join-Path $svcDir "mongo-transaction-demo"
New-Item -ItemType Directory -Path $mtdDest | Out-Null
Copy-Item -Recurse (Join-Path $MTD_PUBLISH_DIR "*") $mtdDest

Copy-Item (Join-Path $SCRIPT_DIR "GhostOrchestrator.ps1") $PKG
Copy-Item (Join-Path $SCRIPT_DIR "RunPackage.ps1") $PKG
Copy-Item (Join-Path $SCRIPT_DIR "deployment_manifest.json") $PKG
Copy-Item (Join-Path $SCRIPT_DIR "GlbDemoService.xml") $PKG
Copy-Item $WINSW_EXE (Join-Path $PKG "GlbDemoService.exe")
Copy-Item (Join-Path $SCRIPT_DIR "install.ps1") $PKG

New-Item -ItemType Directory -Path (Join-Path $PKG "data") | Out-Null
New-Item -ItemType Directory -Path (Join-Path (Join-Path $PKG "data") "mongodb") | Out-Null
New-Item -ItemType Directory -Path (Join-Path (Join-Path (Join-Path $PKG "data") "mongodb") "db") | Out-Null

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Build complete!" -ForegroundColor Green
Write-Host "  Output: $PKG" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Copy your raster and DTM data into deploy_package\data\" -ForegroundColor White
Write-Host "  2. Copy the entire deploy_package folder to the target machine" -ForegroundColor White
Write-Host "  3. On the target machine, run .\install.ps1 as Administrator" -ForegroundColor White
