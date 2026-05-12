[CmdletBinding()]
param(
    [string]$EnvironmentName = 'default'
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "scripts\lib\Layout.ps1")
. (Join-Path $PSScriptRoot "scripts\lib\Common.ps1")
. (Join-Path $PSScriptRoot "scripts\lib\Build.Helpers.ps1")

$layout = Get-DeploymentLayout -BaseDir $PSScriptRoot
$environment = Import-DeploymentEnvironment -BaseDir $layout.BaseDir -EnvironmentName $EnvironmentName
$packageDir = $layout.DeployPackageDir
$toolsDir = $layout.ToolsDir
$projectRoot = $layout.ProjectRoot

function Initialize-BundledTool {
    param(
        [string]$Label,
        [string]$ZipPath,
        [string]$TargetPath,
        [string]$Description,
        [scriptblock]$ExtractCommand
    )

    if (Test-Path $TargetPath) {
        Write-Host "$Label cached." -ForegroundColor Green
        return
    }

    Write-Host "$Label..." -ForegroundColor Yellow
    Require-ToolFile -Path $ZipPath -Description $Description
    & $ExtractCommand
    Write-Host "  Done." -ForegroundColor Green
}

function Copy-ServiceFolder {
    param(
        [string]$Name,
        [scriptblock]$CopyCommand
    )

    Write-Host "  Copying $Name..." -ForegroundColor Yellow
    & $CopyCommand
}

if (Test-Path $packageDir) {
    Stop-ProcessesUnderPath -RootPath $packageDir
    Start-Sleep -Seconds 1
    Remove-PathWithRetry -Path $packageDir
}

New-Item -ItemType Directory -Path $packageDir | Out-Null
if (-not (Test-Path $toolsDir)) {
    New-Item -ItemType Directory -Path $toolsDir | Out-Null
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  GLB Demo - Building deploy package" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$versions = $environment.ToolVersions
$nodeVersion = $versions.Node
$nginxVersion = $versions.Nginx
$winswVersion = $versions.WinSW
$mongoVersion = $versions.MongoDb
$mongoshVersion = $versions.MongoShell
$dotnetVersion = $versions.DotnetSdk

$nodeZip = Join-Path $toolsDir "node-v${nodeVersion}-win-x64.zip"
$nodeDir = Join-Path $toolsDir "node-v${nodeVersion}-win-x64"
$npmCmd = Join-Path $nodeDir "npm.cmd"

$nginxZip = Join-Path $toolsDir "nginx-${nginxVersion}.zip"
$nginxDir = Join-Path $toolsDir "nginx-${nginxVersion}"

$winswExe = Join-Path $toolsDir "WinSW-x64.exe"

$mongoZip = Join-Path $toolsDir "mongodb-windows-x86_64-$mongoVersion.zip"
$mongoDir = Join-Path $toolsDir "mongodb-win32-x86_64-windows-$mongoVersion"

$mongoshZip = Join-Path $toolsDir "mongosh-$mongoshVersion-win32-x64.zip"
$mongoshDir = Join-Path $toolsDir "mongosh-$mongoshVersion-win32-x64"

$dotnetZip = Join-Path $toolsDir "dotnet-sdk-$dotnetVersion-win-x64.zip"
$dotnetDir = Join-Path $toolsDir "dotnet-sdk-$dotnetVersion-win-x64"
$dotnetExe = Join-Path $dotnetDir "dotnet.exe"

Write-Host "[1/6] Preparing bundled build tools..." -ForegroundColor Cyan
Initialize-BundledTool -Label "  Node.js v$nodeVersion" -ZipPath $nodeZip -TargetPath $nodeDir -Description "Node.js portable archive" -ExtractCommand {
    Expand-Archive -Path $nodeZip -DestinationPath $toolsDir -Force
}
Initialize-BundledTool -Label "  Nginx v$nginxVersion" -ZipPath $nginxZip -TargetPath $nginxDir -Description "Nginx portable archive" -ExtractCommand {
    Expand-Archive -Path $nginxZip -DestinationPath $toolsDir -Force
}
if (-not (Test-Path $winswExe)) {
    Write-Host "  WinSW v$winswVersion..." -ForegroundColor Yellow
    Require-ToolFile -Path $winswExe -Description "WinSW executable"
    Write-Host "  Done." -ForegroundColor Green
} else {
    Write-Host "  WinSW v$winswVersion cached." -ForegroundColor Green
}
Initialize-BundledTool -Label "  MongoDB v$mongoVersion" -ZipPath $mongoZip -TargetPath $mongoDir -Description "MongoDB portable archive" -ExtractCommand {
    Expand-Archive -Path $mongoZip -DestinationPath $toolsDir -Force
}
Initialize-BundledTool -Label "  mongosh v$mongoshVersion" -ZipPath $mongoshZip -TargetPath $mongoshDir -Description "mongosh portable archive" -ExtractCommand {
    Expand-Archive -Path $mongoshZip -DestinationPath $toolsDir -Force
}
Initialize-BundledTool -Label "  .NET SDK v$dotnetVersion" -ZipPath $dotnetZip -TargetPath (Join-Path $dotnetDir "dotnet.exe") -Description ".NET SDK archive" -ExtractCommand {
    if (-not (Test-Path $dotnetDir)) { New-Item -ItemType Directory -Path $dotnetDir | Out-Null }
    Expand-Archive -Path $dotnetZip -DestinationPath $dotnetDir -Force
}

Write-Host ""
Write-Host "[2/6] Building application services..." -ForegroundColor Cyan

$heightServerDir = Join-Path $projectRoot "height-server"
$mapProviderDir = Join-Path $projectRoot "map-provider"
$mapProviderUiDir = Join-Path $projectRoot "map-provider-ui"
$mapManagerDir = Join-Path $projectRoot "map-manager"
$mongoTransactionDemoDir = Join-Path $projectRoot "mongo-transaction-demo"

Write-Host "  Resolving Pixi env for height-server..." -ForegroundColor Yellow
Push-Location $heightServerDir
Invoke-WithCleanPythonEnv -Command {
    Invoke-Step -Description "pixi install (height-server)" -Command { pixi install }
}
Test-PythonEnv -Name "height-server" -PythonExe (Join-Path $heightServerDir ".pixi\envs\default\python.exe") -InlineCheck "from osgeo import gdal; import pyproj; print('height-server runtime ok')"
Pop-Location
Write-Host "    Done." -ForegroundColor Green

Write-Host "  Resolving Pixi env for map-provider..." -ForegroundColor Yellow
Push-Location $mapProviderDir
Invoke-WithCleanPythonEnv -Command {
    Invoke-Step -Description "pixi install (map-provider)" -Command { pixi install }
}
Test-PythonEnv -Name "map-provider" -PythonExe (Join-Path $mapProviderDir ".pixi\envs\default\python.exe") -InlineCheck "import rasterio, titiler.core, uvicorn; print('map-provider runtime ok')"
Pop-Location
Write-Host "    Done." -ForegroundColor Green

Write-Host "  Building map-provider-ui..." -ForegroundColor Yellow
Push-Location $mapProviderUiDir
Invoke-Step -Description "npm install (map-provider-ui)" -Command { & $npmCmd install --silent }
Invoke-Step -Description "npm run build (map-provider-ui)" -Command { & $npmCmd run build }
Pop-Location
Write-Host "    Done." -ForegroundColor Green

Write-Host "  Building map-manager..." -ForegroundColor Yellow
Push-Location $mapManagerDir
Invoke-Step -Description "npm install (map-manager)" -Command { & $npmCmd install --silent }
Invoke-Step -Description "npm run build (map-manager)" -Command { & $npmCmd run build }
Pop-Location
Write-Host "    Done." -ForegroundColor Green

$mongoTransactionPublishDir = Join-Path $mongoTransactionDemoDir "bin\Release\net8.0\publish"
$mongoTransactionNugetConfig = Join-Path $mongoTransactionDemoDir "NuGet.Config"
Write-Host "  Publishing mongo-transaction-demo..." -ForegroundColor Yellow
Push-Location $mongoTransactionDemoDir
Invoke-WithDotnetEnv -BaseDir $layout.BaseDir -Command {
    Invoke-Step -Description "dotnet restore (mongo-transaction-demo)" -Command { & $dotnetExe restore --configfile $mongoTransactionNugetConfig }
    Invoke-Step -Description "dotnet publish (mongo-transaction-demo)" -Command { & $dotnetExe publish --no-restore -c Release -o $mongoTransactionPublishDir }
}
Pop-Location
Write-Host "    Done." -ForegroundColor Green

Write-Host ""
Write-Host "[3/6] Creating runtime layout..." -ForegroundColor Cyan

$packageNodeDir = Join-Path $packageDir "node"
$packageDotnetDir = Join-Path $packageDir "dotnet"
$packageMongoDir = Join-Path $packageDir "mongodb"
$packageMongoShellDir = Join-Path $packageDir "mongosh"
$packageServiceDir = Join-Path $packageDir "services"
$packageConfigDir = Join-Path $packageDir "config"
$packageScriptsDir = Join-Path $packageDir "scripts"

New-Item -ItemType Directory -Path $packageNodeDir | Out-Null
New-Item -ItemType Directory -Path $packageDotnetDir | Out-Null
New-Item -ItemType Directory -Path $packageMongoDir | Out-Null
New-Item -ItemType Directory -Path $packageMongoShellDir | Out-Null
New-Item -ItemType Directory -Path $packageServiceDir | Out-Null
New-Item -ItemType Directory -Path $packageConfigDir | Out-Null
New-Item -ItemType Directory -Path $packageScriptsDir | Out-Null

Copy-Item (Join-Path $nodeDir "node.exe") $packageNodeDir
Copy-Item -Recurse (Join-Path $dotnetDir "*") $packageDotnetDir
Copy-Item -Recurse $nginxDir (Join-Path $packageDir "nginx")
Copy-Item -Recurse (Join-Path $mongoDir "*") $packageMongoDir
Copy-Item -Recurse (Join-Path $mongoshDir "*") $packageMongoShellDir

Write-Host "[4/6] Copying deployment configuration..." -ForegroundColor Cyan
Copy-Item -Recurse (Join-Path $layout.ConfigDir "*") $packageConfigDir
Copy-Item (Resolve-DeploymentConfigPath -BaseDir $layout.BaseDir -RelativePath $environment.Config.ServiceXml) (Join-Path $packageDir "GlbDemoService.xml")

$nginxConfDir = Join-Path (Join-Path $packageDir "nginx") "conf"
if (-not (Test-Path $nginxConfDir)) { New-Item -ItemType Directory -Path $nginxConfDir | Out-Null }
Copy-Item (Resolve-DeploymentConfigPath -BaseDir $layout.BaseDir -RelativePath $environment.Config.NginxData) (Join-Path $nginxConfDir "nginx-data.conf")
Copy-Item (Resolve-DeploymentConfigPath -BaseDir $layout.BaseDir -RelativePath $environment.Config.NginxUi) (Join-Path $nginxConfDir "nginx-ui.conf")

Write-Host "[5/6] Copying packaged services..." -ForegroundColor Cyan

Copy-ServiceFolder -Name "height-server source + Pixi env" -CopyCommand {
    $destination = Join-Path $packageServiceDir "height-server"
    New-Item -ItemType Directory -Path $destination | Out-Null
    Copy-Item -Recurse (Join-Path $heightServerDir "src") (Join-Path $destination "src")
    Copy-Item (Join-Path $heightServerDir "pixi.toml") $destination
    Copy-Item (Join-Path $heightServerDir "pixi.lock") $destination
    Copy-Item -Recurse (Join-Path $heightServerDir ".pixi") (Join-Path $destination ".pixi")
    Get-ChildItem -Path $destination -Recurse -Directory -Filter "__pycache__" | Remove-Item -Recurse -Force
}

Copy-ServiceFolder -Name "map-provider source + Pixi env" -CopyCommand {
    $destination = Join-Path $packageServiceDir "map-provider"
    New-Item -ItemType Directory -Path $destination | Out-Null
    Copy-Item -Recurse (Join-Path $mapProviderDir "src") (Join-Path $destination "src")
    Copy-Item (Join-Path $mapProviderDir "pixi.toml") $destination
    Copy-Item (Join-Path $mapProviderDir "pixi.lock") $destination
    Copy-Item -Recurse (Join-Path $mapProviderDir ".pixi") (Join-Path $destination ".pixi")
    Get-ChildItem -Path $destination -Recurse -Directory -Filter "__pycache__" | Remove-Item -Recurse -Force
}

Copy-ServiceFolder -Name "map-manager" -CopyCommand {
    $destination = Join-Path $packageServiceDir "map-manager"
    New-Item -ItemType Directory -Path $destination | Out-Null
    Copy-Item -Recurse (Join-Path $mapManagerDir "dist") (Join-Path $destination "dist")
    Copy-Item -Recurse (Join-Path $mapManagerDir "node_modules") (Join-Path $destination "node_modules")
    Copy-Item (Join-Path $mapManagerDir "package.json") (Join-Path $destination "package.json")
}

Copy-ServiceFolder -Name "map-provider-ui" -CopyCommand {
    $destination = Join-Path $packageServiceDir "map-provider-ui"
    New-Item -ItemType Directory -Path $destination | Out-Null
    Copy-Item -Recurse (Join-Path $mapProviderUiDir "dist") (Join-Path $destination "dist")
}

Copy-ServiceFolder -Name "mongo-transaction-demo publish output" -CopyCommand {
    $destination = Join-Path $packageServiceDir "mongo-transaction-demo"
    New-Item -ItemType Directory -Path $destination | Out-Null
    Copy-Item -Recurse (Join-Path $mongoTransactionPublishDir "*") $destination
}

Write-Host "[6/6] Copying deployment entrypoints and support scripts..." -ForegroundColor Cyan
Copy-Item -Recurse (Join-Path $layout.ScriptsDir "lib") $packageScriptsDir
Copy-Item (Join-Path $layout.BaseDir "GhostOrchestrator.ps1") $packageDir
Copy-Item (Join-Path $layout.BaseDir "RunPackage.ps1") $packageDir
Copy-Item (Join-Path $layout.BaseDir "install.ps1") $packageDir
Copy-Item $winswExe (Join-Path $packageDir "GlbDemoService.exe")

New-Item -ItemType Directory -Path (Join-Path $packageDir "data") | Out-Null
New-Item -ItemType Directory -Path (Join-Path (Join-Path $packageDir "data") "mongodb") | Out-Null
New-Item -ItemType Directory -Path (Join-Path (Join-Path (Join-Path $packageDir "data") "mongodb") "db") | Out-Null

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Build complete!" -ForegroundColor Green
Write-Host "  Output: $packageDir" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Copy your raster and DTM data into deploy_package\data\" -ForegroundColor White
Write-Host "  2. Run .\build_installer_exe.ps1 to add Setup.exe to the package" -ForegroundColor White
Write-Host "  3. Send deploy_package\ to the target machine and run Setup.exe or install.ps1" -ForegroundColor White
