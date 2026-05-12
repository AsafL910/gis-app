[CmdletBinding()]
param(
    [string]$Version = "1.0.0",
    [switch]$SkipBuildPackage
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "scripts\lib\Layout.ps1")
. (Join-Path $PSScriptRoot "scripts\lib\Common.ps1")
. (Join-Path $PSScriptRoot "scripts\lib\Build.Helpers.ps1")

$layout = Get-DeploymentLayout -BaseDir $PSScriptRoot
$packageDir = $layout.DeployPackageDir
$bootstrapperRoot = $layout.BootstrapperDir
$bootstrapperProject = Join-Path $bootstrapperRoot "GlbDemoBootstrapper.csproj"
$bootstrapperNugetConfig = Join-Path $bootstrapperRoot "NuGet.Config"
$bootstrapperOut = Join-Path $bootstrapperRoot "publish"
$bootstrapperIntermediateRoot = Join-Path $layout.BaseDir "tmp\bootstrapper-obj"
$bootstrapperBaseName = "Setup"
$bootstrapperFiles = @(
    "$bootstrapperBaseName.exe",
    "$bootstrapperBaseName.dll",
    "$bootstrapperBaseName.deps.json",
    "$bootstrapperBaseName.runtimeconfig.json"
)
$finalExe = Join-Path $packageDir "Setup.exe"
$deliveryReadme = Join-Path $packageDir "SETUP_README.txt"
$deliveryMetadata = Join-Path $packageDir "setup-metadata.json"
$environment = Import-DeploymentEnvironment -BaseDir $layout.BaseDir -EnvironmentName 'default'
$dotnetVersion = $environment.ToolVersions.DotnetSdk
$toolsDotnetDir = Join-Path $layout.ToolsDir "dotnet-sdk-$dotnetVersion-win-x64"
$toolsDotnetZip = Join-Path $layout.ToolsDir "dotnet-sdk-$dotnetVersion-win-x64.zip"
$dotnetExe = Join-Path $toolsDotnetDir "dotnet.exe"

function Ensure-BundledDotnetSdk {
    if (Test-Path $dotnetExe) {
        return
    }

    Require-ToolFile -Path $toolsDotnetZip -Description ".NET SDK archive"
    if (-not (Test-Path $toolsDotnetDir)) {
        New-Item -ItemType Directory -Path $toolsDotnetDir | Out-Null
    }

    Expand-Archive -Path $toolsDotnetZip -DestinationPath $toolsDotnetDir -Force
}

function Get-DirectoryStats {
    param([string]$Root)

    $files = Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction Stop
    $bytes = ($files | Measure-Object -Property Length -Sum).Sum
    return [PSCustomObject]@{
        FileCount = $files.Count
        TotalBytes = $bytes
        TotalGB = [math]::Round($bytes / 1GB, 3)
    }
}

function Write-DeliveryReadme {
    param(
        [string]$DestinationPath,
        [string]$Version
    )

    $content = @"
GLB Demo Installer
Version: $Version

Contents:
- Setup.exe
- install.ps1
- config\
- scripts\
- services\
- runtimes already prepared in deploy_package\

How to install:
1. Keep all files in this folder together.
2. Double-click Setup.exe and allow elevation, or run Setup.exe from SCCM.

Common commands:
  Setup.exe
  Setup.exe /quiet /log C:\Temp\GlbDemoInstall.log
  Setup.exe /uninstall /quiet /log C:\Temp\GlbDemoUninstall.log
  Setup.exe /installDir "D:\Apps\GlbDemo"
"@

    Set-Content -LiteralPath $DestinationPath -Value $content -Encoding ASCII
}

function Write-DeliveryMetadata {
    param(
        [string]$DestinationPath,
        [string]$Version,
        [object]$PayloadStats
    )

    $metadata = [PSCustomObject]@{
        delivery_root = "deploy_package"
        version = $Version
        setup_exe = "Setup.exe"
        install_script = "install.ps1"
        payload_file_count = $PayloadStats.FileCount
        payload_total_bytes = $PayloadStats.TotalBytes
        generated_at_utc = [DateTime]::UtcNow.ToString("o")
    }

    $metadata | ConvertTo-Json | Set-Content -LiteralPath $DestinationPath -Encoding UTF8
}

if (-not $SkipBuildPackage) {
    Write-Host "Running build_package.ps1 first..." -ForegroundColor Cyan
    Invoke-Step -Description "build_package.ps1" -Command { & (Join-Path $layout.BaseDir "build_package.ps1") }
}

if (-not (Test-Path $packageDir)) {
    throw "deploy_package was not found at '$packageDir'. Run build_package.ps1 first or omit -SkipBuildPackage."
}

Ensure-CleanDirectory -Path $bootstrapperOut
Ensure-CleanDirectory -Path $bootstrapperIntermediateRoot
Ensure-BundledDotnetSdk

Write-Host "Compiling bootstrapper..." -ForegroundColor Cyan
Invoke-WithDotnetEnv -BaseDir $layout.BaseDir -Command {
    Invoke-Step -Description "dotnet restore (bootstrapper)" -Command {
        & $dotnetExe restore $bootstrapperProject --configfile $bootstrapperNugetConfig -p:BaseIntermediateOutputPath=$bootstrapperIntermediateRoot\
    }

    Invoke-Step -Description "dotnet build (bootstrapper)" -Command {
        & $dotnetExe build $bootstrapperProject --no-restore -c Release -p:BaseIntermediateOutputPath=$bootstrapperIntermediateRoot\ -o $bootstrapperOut
    }
}

$stats = Get-DirectoryStats -Root $packageDir
Write-Host "Preparing deploy_package for delivery..." -ForegroundColor Cyan
Write-Host "  Payload size: $($stats.TotalGB) GB across $($stats.FileCount) files" -ForegroundColor DarkGray

Write-Host "Placing Setup.exe into deploy_package..." -ForegroundColor Cyan
foreach ($fileName in $bootstrapperFiles) {
    $sourcePath = Join-Path $bootstrapperOut $fileName
    if (-not (Test-Path $sourcePath)) {
        throw "Expected bootstrapper output was not found: $sourcePath"
    }

    $destinationPath = Join-Path $packageDir $fileName
    if (Test-Path $destinationPath) {
        Remove-Item -LiteralPath $destinationPath -Force
    }
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
}

Write-DeliveryReadme -DestinationPath $deliveryReadme -Version $Version
Write-DeliveryMetadata -DestinationPath $deliveryMetadata -Version $Version -PayloadStats $stats

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Installer build complete!" -ForegroundColor Green
Write-Host "  Deliverable folder: $packageDir" -ForegroundColor Green
Write-Host "  Setup: $finalExe" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
