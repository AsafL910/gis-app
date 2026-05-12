[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$SkipCopy,
    [switch]$PrepareOnly,
    [switch]$SkipPackageRemoval,
    [string]$InstallDir,
    [switch]$Quiet,
    [string]$LogPath,
    [string]$EnvironmentName = 'default'
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "scripts\lib\Layout.ps1")
. (Join-Path $PSScriptRoot "scripts\lib\Common.ps1")
. (Join-Path $PSScriptRoot "scripts\lib\Install.Helpers.ps1")

$layout = Get-DeploymentLayout -BaseDir $PSScriptRoot
$environment = Import-DeploymentEnvironment -BaseDir $PSScriptRoot -EnvironmentName $EnvironmentName
$effectiveInstallDir = if ([string]::IsNullOrWhiteSpace($InstallDir)) { $environment.DefaultInstallDir } else { $InstallDir }
$context = New-InstallContext -ServiceName $environment.ServiceName -InstallDir $effectiveInstallDir -Quiet:$Quiet -LogPath $LogPath
$packageDir = $layout.BaseDir
$uiUrl = $environment.UiUrl

function Invoke-InstallStage {
    param(
        [int]$Step,
        [int]$Total,
        [string]$Title,
        [scriptblock]$Action
    )

    Write-InstallStatus -Context $context -Message "[$Step/$Total] $Title..." -Color Yellow
    & $Action
    Write-InstallStatus -Context $context -Message "  Done." -Color Green
}

if (-not (Test-IsAdministrator)) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell -> 'Run as Administrator', then try again." -ForegroundColor Yellow
    exit 1
}

if ($Uninstall) {
    Write-InstallStatus -Context $context -Message "Uninstalling $($environment.ServiceName)..." -Color Yellow
    if (Test-Path $context.InstallDir) {
        Stop-InstalledServiceAndChildren -ServiceName $environment.ServiceName -InstallDir $context.InstallDir
        Unregister-InstalledService -ServiceName $environment.ServiceName -InstallDir $context.InstallDir
        Write-InstallStatus -Context $context -Message "Service unregistered." -Color Green
    }
    if (-not $SkipPackageRemoval -and (Test-Path $context.InstallDir)) {
        Remove-Item -Recurse -Force $context.InstallDir
        Write-InstallStatus -Context $context -Message "Removed $($context.InstallDir)" -Color Green
    }
    Write-InstallStatus -Context $context -Message "Uninstall complete." -Color Green
    exit 0
}

if ($PrepareOnly) {
    Write-InstallStatus -Context $context -Message "Preparing existing installation at $($context.InstallDir)..." -Color Yellow
    if (Test-Path $context.InstallDir) {
        Stop-InstalledServiceAndChildren -ServiceName $environment.ServiceName -InstallDir $context.InstallDir
    }
    Write-InstallStatus -Context $context -Message "Preparation complete." -Color Green
    exit 0
}

Write-InstallStatus -Context $context -Message "========================================" -Color Cyan
Write-InstallStatus -Context $context -Message "  GLB Demo - Installing Windows Service" -Color Cyan
Write-InstallStatus -Context $context -Message "========================================" -Color Cyan
Write-InstallStatus -Context $context -Message ""
Write-InstallStatus -Context $context -Message "Source:      $packageDir"
Write-InstallStatus -Context $context -Message "Destination: $($context.InstallDir)"
Write-InstallStatus -Context $context -Message ""

Invoke-InstallStage -Step 1 -Total 6 -Title "Preparing target machine" -Action {
    if (Test-Path $context.InstallDir) {
        Stop-InstalledServiceAndChildren -ServiceName $environment.ServiceName -InstallDir $context.InstallDir
        if (-not $SkipCopy) {
            Remove-InstallContents -InstallDir $context.InstallDir
        }
    }
    if (-not (Test-Path $context.InstallDir)) {
        New-Item -ItemType Directory -Path $context.InstallDir | Out-Null
    }
}

Invoke-InstallStage -Step 2 -Total 6 -Title "Copying files to $($context.InstallDir)" -Action {
    if (-not $SkipCopy) {
        Copy-PackageContents -SourceDir $packageDir -DestinationDir $context.InstallDir
        $installedScript = Join-Path $context.InstallDir "install.ps1"
        if (Test-Path $installedScript) {
            Remove-Item $installedScript
        }
    } else {
        Write-InstallStatus -Context $context -Message "  Skipped copy step because files were already laid down by the caller." -Color DarkGray
    }
}

Invoke-InstallStage -Step 3 -Total 6 -Title "Seeding default service configuration" -Action {
    $packageConfigDir = Join-Path $packageDir "config"
    $serviceDefaultsDir = Join-Path $packageConfigDir "service-defaults"
    $installDataConfigDir = Join-Path (Join-Path $context.InstallDir "data") "config"
    Initialize-ServiceConfigDefaults -DefaultsRoot $serviceDefaultsDir -TargetConfigRoot $installDataConfigDir
}

Invoke-InstallStage -Step 4 -Total 6 -Title "Patching Nginx configs with install paths" -Action {
    $dataDir = Join-Path $context.InstallDir "data"
    $uiDistDir = Join-Path (Join-Path (Join-Path $context.InstallDir "services") "map-provider-ui") "dist"
    $dataConf = Join-Path (Join-Path (Join-Path $context.InstallDir "nginx") "conf") "nginx-data.conf"
    $uiConf = Join-Path (Join-Path (Join-Path $context.InstallDir "nginx") "conf") "nginx-ui.conf"
    Set-NginxRootDirective -ConfigPath $dataConf -ResolvedRoot $dataDir
    Set-NginxRootDirective -ConfigPath $uiConf -ResolvedRoot $uiDistDir
}

Invoke-InstallStage -Step 5 -Total 6 -Title "Preparing logs and registering the Windows service" -Action {
    $logsDir = Join-Path $context.InstallDir "logs"
    if (-not (Test-Path $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir | Out-Null
    }
    $winsw = Join-Path $context.InstallDir "$($environment.ServiceName).exe"
    & $winsw install
}

Invoke-InstallStage -Step 6 -Total 6 -Title "Starting the service and verifying startup" -Action {
    Start-Service -Name $environment.ServiceName
}

$logsDir = Join-Path $context.InstallDir "logs"
$uiReady = Wait-ForUi -Url $uiUrl -TimeoutSeconds 30

Write-InstallStatus -Context $context -Message ""
if ($uiReady) {
    Write-InstallStatus -Context $context -Message "========================================" -Color Green
    Write-InstallStatus -Context $context -Message "  Installation complete!" -Color Green
    Write-InstallStatus -Context $context -Message "========================================" -Color Green
    Write-InstallStatus -Context $context -Message ""
    Write-InstallStatus -Context $context -Message "Service name:  $($environment.ServiceName)"
    Write-InstallStatus -Context $context -Message "Install path:  $($context.InstallDir)"
    Write-InstallStatus -Context $context -Message ""
    Write-InstallStatus -Context $context -Message "Access the application at:"
    Write-InstallStatus -Context $context -Message "  $uiUrl" -Color Cyan
    Write-InstallStatus -Context $context -Message ""
    Write-InstallStatus -Context $context -Message "Manage the service with:"
    Write-InstallStatus -Context $context -Message "  Start-Service $($environment.ServiceName)" -Color Cyan
    Write-InstallStatus -Context $context -Message "  Stop-Service  $($environment.ServiceName)" -Color Cyan
    Write-InstallStatus -Context $context -Message "  Restart-Service $($environment.ServiceName)" -Color Cyan
} else {
    Show-StartupDiagnostics -LogsDir $logsDir -ServiceName $environment.ServiceName -UiUrl $uiUrl
}
