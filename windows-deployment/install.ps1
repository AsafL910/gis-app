# ============================================================
# install.ps1
# ============================================================
# Run this on the TARGET machine (offline, no internet needed).
# Must be run as Administrator.
#
# What it does:
#   1. Copies everything to C:\Program Files\GlbDemo\
#   2. Rewrites Nginx config placeholders with real paths
#   3. Registers the Windows Service via WinSW
#   4. Starts the service
#
# Usage:
#   Right-click PowerShell → "Run as Administrator"
#   .\install.ps1
#
# To uninstall:
#   .\install.ps1 -Uninstall
# ============================================================

param(
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

# ── Config ───────────────────────────────────────────────────
$SERVICE_NAME = "GlbDemoService"
$INSTALL_DIR  = "C:\Program Files\GlbDemo"

function Stop-InstallProcesses {
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

function Get-DescendantProcessIds {
    param(
        [int]$RootProcessId
    )

    $allProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    if ($allProcesses.Count -eq 0) {
        return @()
    }

    $childrenByParent = @{}
    foreach ($proc in $allProcesses) {
        $parentId = [int]$proc.ParentProcessId
        if (-not $childrenByParent.ContainsKey($parentId)) {
            $childrenByParent[$parentId] = New-Object System.Collections.Generic.List[int]
        }
        $childrenByParent[$parentId].Add([int]$proc.ProcessId) | Out-Null
    }

    $result = New-Object System.Collections.Generic.List[int]
    $queue = New-Object System.Collections.Generic.Queue[int]
    $queue.Enqueue($RootProcessId)

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if (-not $childrenByParent.ContainsKey($current)) {
            continue
        }

        foreach ($childId in $childrenByParent[$current]) {
            $result.Add($childId) | Out-Null
            $queue.Enqueue($childId)
        }
    }

    return @($result | Select-Object -Unique)
}

function Stop-ProcessTree {
    param(
        [int]$RootProcessId
    )

    $descendants = @(Get-DescendantProcessIds -RootProcessId $RootProcessId)
    foreach ($pid in ($descendants | Sort-Object -Descending)) {
        try {
            Stop-Process -Id $pid -Force -ErrorAction Stop
            Write-Host "  Stopped child process PID $pid" -ForegroundColor DarkYellow
        } catch {
        }
    }

    try {
        Stop-Process -Id $RootProcessId -Force -ErrorAction Stop
        Write-Host "  Stopped root process PID $RootProcessId" -ForegroundColor DarkYellow
    } catch {
    }
}

function Wait-ForServiceStopped {
    param(
        [string]$Name,
        [int]$TimeoutSeconds = 20
    )

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $service) {
        return
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $service.Refresh()
        if ($service.Status -eq "Stopped") {
            return
        }

        Start-Sleep -Milliseconds 500
    }
}

function Get-ServiceProcessId {
    param(
        [string]$Name
    )

    try {
        $svc = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction Stop
        return [int]$svc.ProcessId
    } catch {
        return 0
    }
}

function Wait-ForPathReleased {
    param(
        [string]$Path,
        [int]$TimeoutSeconds = 20
    )

    if (-not (Test-Path $Path)) {
        return
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $item = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (-not $item.PSIsContainer) {
                $stream = [System.IO.File]::Open($item.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
                $stream.Dispose()
                return
            }

            $probeFile = Get-ChildItem -LiteralPath $item.FullName -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $probeFile) {
                return
            }

            $stream = [System.IO.File]::Open($probeFile.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $stream.Dispose()
            return
        } catch {
            Start-Sleep -Milliseconds 500
        }
    }

    throw "Timed out waiting for file handles under '$Path' to be released."
}

function Remove-InstallContents {
    param(
        [string]$InstallDir
    )

    if (-not (Test-Path $InstallDir)) {
        return
    }

    $items = @(Get-ChildItem -LiteralPath $InstallDir -Force | Where-Object { $_.Name -ne "data" })
    foreach ($item in $items) {
        Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
    }
}

function Stop-InstalledServiceAndChildren {
    param(
        [string]$ServiceName,
        [string]$InstallDir
    )

    $serviceProcessId = Get-ServiceProcessId -Name $ServiceName
    try { Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue } catch {}
    Wait-ForServiceStopped -Name $ServiceName

    if ($serviceProcessId -gt 0) {
        Stop-ProcessTree -RootProcessId $serviceProcessId
    }

    $winsw = Join-Path $InstallDir "$ServiceName.exe"
    if (Test-Path $winsw) {
        try { & $winsw stop | Out-Null } catch {}
    }

    Stop-InstallProcesses -RootPath $InstallDir
    Start-Sleep -Seconds 2
    Wait-ForPathReleased -Path $InstallDir
}

function Unregister-InstalledService {
    param(
        [string]$ServiceName,
        [string]$InstallDir
    )

    $winsw = Join-Path $InstallDir "$ServiceName.exe"
    if (Test-Path $winsw) {
        try { & $winsw uninstall } catch {}
    }
}

function Copy-PackageContents {
    param(
        [string]$SourceDir,
        [string]$DestinationDir
    )

    $items = @(Get-ChildItem -Path $SourceDir -Force | Where-Object { $_.Name -ne "data" })
    $totalItems = [Math]::Max($items.Count, 1)

    for ($index = 0; $index -lt $items.Count; $index++) {
        $item = $items[$index]
        $percent = [int](($index / $totalItems) * 100)
        Write-Progress -Id 1 -Activity "Copying package files" -Status $item.Name -PercentComplete $percent

        if ($item.PSIsContainer -and $item.Name -eq "services") {
            $servicesDest = Join-Path $DestinationDir "services"
            if (-not (Test-Path $servicesDest)) {
                New-Item -ItemType Directory -Path $servicesDest | Out-Null
            }

            $serviceDirs = @(Get-ChildItem -Path $item.FullName -Directory -Force)
            $serviceTotal = [Math]::Max($serviceDirs.Count, 1)

            for ($serviceIndex = 0; $serviceIndex -lt $serviceDirs.Count; $serviceIndex++) {
                $serviceDir = $serviceDirs[$serviceIndex]
                $servicePercent = [int](($serviceIndex / $serviceTotal) * 100)
                Write-Progress -Id 2 -ParentId 1 -Activity "Copying services" -Status $serviceDir.Name -PercentComplete $servicePercent
                Write-Host "  Copying services\\$($serviceDir.Name)..." -ForegroundColor DarkGray
                Copy-Item -Path $serviceDir.FullName -Destination $servicesDest -Recurse -Force
            }

            Write-Progress -Id 2 -ParentId 1 -Activity "Copying services" -Completed
            continue
        }

        Copy-Item -Path $item.FullName -Destination $DestinationDir -Recurse -Force
    }

    Write-Progress -Id 1 -Activity "Copying package files" -Completed

    $sourceDataDir = Join-Path $SourceDir "data"
    $targetDataDir = Join-Path $DestinationDir "data"
    if (-not (Test-Path $sourceDataDir)) {
        return
    }

    if (Test-Path $targetDataDir) {
        $hasTargetDataFiles = @(Get-ChildItem -Path $targetDataDir -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1).Count -gt 0
        if ($hasTargetDataFiles) {
            Write-Host "  Skipped data copy because $targetDataDir already contains files." -ForegroundColor DarkYellow
            return
        }

        Write-Host "  Data directory exists but is empty. Copying package data..." -ForegroundColor DarkYellow
    } else {
        New-Item -ItemType Directory -Path $targetDataDir | Out-Null
    }

    Write-Progress -Id 3 -Activity "Copying package data" -Status "data" -PercentComplete 0
    Get-ChildItem -Path $sourceDataDir -Force | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $targetDataDir -Recurse -Force
    }
    Write-Progress -Id 3 -Activity "Copying package data" -Completed
    Write-Host "  Copied data directory." -ForegroundColor Green
}

function Set-NginxRootDirective {
    param(
        [string]$ConfigPath,
        [string]$ResolvedRoot
    )

    $normalizedRoot = $ResolvedRoot -replace '\\', '/'
    $content = Get-Content $ConfigPath -Raw
    $updated = [regex]::Replace(
        $content,
        '(?m)^(\s*root\s+)(?:"[^"]*"|[^;]+)(;)\s*$',
        "`$1`"$normalizedRoot`"`$2",
        1
    )

    if ($updated -eq $content) {
        throw "Could not rewrite nginx root directive in $ConfigPath"
    }

    Set-Content $ConfigPath $updated
}

function Get-RecentLogFiles {
    param(
        [string]$LogsDir
    )

    if (-not (Test-Path $LogsDir)) {
        return @()
    }

    @(Get-ChildItem -Path $LogsDir -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 6)
}

function Show-StartupDiagnostics {
    param(
        [string]$LogsDir,
        [string]$ServiceName
    )

    Write-Host ""
    Write-Host "Application did not become available at http://localhost:8013." -ForegroundColor Red

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        Write-Host "Service status: $($service.Status)" -ForegroundColor Yellow
    } catch {
        Write-Host "Service status: unavailable ($_)" -ForegroundColor Yellow
    }

    $recentLogs = Get-RecentLogFiles -LogsDir $LogsDir
    if ($recentLogs.Count -eq 0) {
        Write-Host "No log files were found yet under $LogsDir" -ForegroundColor Yellow
        return
    }

    Write-Host "Relevant logs:" -ForegroundColor Yellow
    foreach ($log in $recentLogs) {
        Write-Host "  $($log.FullName)" -ForegroundColor Cyan
    }

    foreach ($log in $recentLogs | Select-Object -First 3) {
        Write-Host ""
        Write-Host "Last lines from $($log.Name):" -ForegroundColor Yellow
        try {
            Get-Content -Path $log.FullName -Tail 20 -ErrorAction Stop | ForEach-Object {
                Write-Host "  $_"
            }
        } catch {
            Write-Host "  Could not read $($log.FullName): $_" -ForegroundColor DarkYellow
        }
    }
}

function Wait-ForUi {
    param(
        [string]$Url,
        [int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $attempt = 0
    while ((Get-Date) -lt $deadline) {
        $attempt++
        $remaining = [Math]::Max([int][Math]::Ceiling(($deadline - (Get-Date)).TotalSeconds), 0)
        Write-Progress -Id 4 -Activity "Checking application startup" -Status "Attempt ${attempt}: waiting for $Url ($remaining s left)" -PercentComplete ([int]((1 - ($remaining / [Math]::Max($TimeoutSeconds, 1))) * 100))
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                Write-Progress -Id 4 -Activity "Checking application startup" -Completed
                return $true
            }
        } catch {
        }

        Start-Sleep -Seconds 2
    }

    Write-Progress -Id 4 -Activity "Checking application startup" -Completed
    return $false
}

# ── Check admin ──────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell → 'Run as Administrator', then try again." -ForegroundColor Yellow
    exit 1
}

# ── Uninstall mode ───────────────────────────────────────────
if ($Uninstall) {
    Write-Host "Uninstalling $SERVICE_NAME..." -ForegroundColor Yellow

    if (Test-Path $INSTALL_DIR) {
        Stop-InstalledServiceAndChildren -ServiceName $SERVICE_NAME -InstallDir $INSTALL_DIR
        Unregister-InstalledService -ServiceName $SERVICE_NAME -InstallDir $INSTALL_DIR
        Write-Host "Service unregistered." -ForegroundColor Green
    }

    if (Test-Path $INSTALL_DIR) {
        Remove-Item -Recurse -Force $INSTALL_DIR
        Write-Host "Removed $INSTALL_DIR" -ForegroundColor Green
    }

    Write-Host "Uninstall complete." -ForegroundColor Green
    exit 0
}

# ============================================================
# Install
# ============================================================
$PACKAGE_DIR = $PSScriptRoot   # install.ps1 lives inside deploy_package/

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  GLB Demo — Installing Windows Service" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Source:      $PACKAGE_DIR" -ForegroundColor White
Write-Host "Destination: $INSTALL_DIR" -ForegroundColor White
Write-Host ""

# ── Step 1: Copy files ───────────────────────────────────────
Write-Host "[1/4] Copying files to $INSTALL_DIR..." -ForegroundColor Yellow

if (Test-Path $INSTALL_DIR) {
    Stop-InstalledServiceAndChildren -ServiceName $SERVICE_NAME -InstallDir $INSTALL_DIR
    Remove-InstallContents -InstallDir $INSTALL_DIR
}

# Create install dir and copy everything
if (-not (Test-Path $INSTALL_DIR)) {
    New-Item -ItemType Directory -Path $INSTALL_DIR | Out-Null
}
Copy-PackageContents -SourceDir $PACKAGE_DIR -DestinationDir $INSTALL_DIR

# Remove the install script itself from the install dir (not needed there)
$installedScript = Join-Path $INSTALL_DIR "install.ps1"
if (Test-Path $installedScript) { Remove-Item $installedScript }

Write-Host "  Done." -ForegroundColor Green

# ── Step 2: Patch Nginx configs with real paths ──────────────
Write-Host "[2/4] Patching Nginx configs with install paths..." -ForegroundColor Yellow

$dataDir   = Join-Path $INSTALL_DIR "data"
$uiDistDir = Join-Path (Join-Path (Join-Path $INSTALL_DIR "services") "map-provider-ui") "dist"

$dataConf = Join-Path (Join-Path (Join-Path $INSTALL_DIR "nginx") "conf") "nginx-data.conf"
Set-NginxRootDirective -ConfigPath $dataConf -ResolvedRoot $dataDir

$uiConf = Join-Path (Join-Path (Join-Path $INSTALL_DIR "nginx") "conf") "nginx-ui.conf"
Set-NginxRootDirective -ConfigPath $uiConf -ResolvedRoot $uiDistDir

Write-Host "  Done." -ForegroundColor Green

# ── Step 3: Create logs directory ────────────────────────────
$logsDir = Join-Path $INSTALL_DIR "logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir | Out-Null }

# ── Step 4: Register and start the Windows Service ───────────
Write-Host "[3/4] Registering Windows Service..." -ForegroundColor Yellow

$winsw = Join-Path $INSTALL_DIR "$SERVICE_NAME.exe"
& $winsw install
Write-Host "  Done." -ForegroundColor Green

Write-Host "[4/4] Starting service..." -ForegroundColor Yellow
Start-Service -Name $SERVICE_NAME
Write-Host "  Done." -ForegroundColor Green

$uiUrl = "http://localhost:8013"
$uiReady = Wait-ForUi -Url $uiUrl -TimeoutSeconds 30

# ── Summary ──────────────────────────────────────────────────
Write-Host ""
if ($uiReady) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Installation complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Service name:  $SERVICE_NAME" -ForegroundColor White
    Write-Host "Install path:  $INSTALL_DIR" -ForegroundColor White
    Write-Host ""
    Write-Host "Access the application at:" -ForegroundColor White
    Write-Host "  $uiUrl" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Manage the service with:" -ForegroundColor White
    Write-Host "  Start-Service $SERVICE_NAME" -ForegroundColor Cyan
    Write-Host "  Stop-Service  $SERVICE_NAME" -ForegroundColor Cyan
    Write-Host "  Restart-Service $SERVICE_NAME" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "To uninstall:" -ForegroundColor White
    Write-Host "  .\install.ps1 -Uninstall" -ForegroundColor Cyan
} else {
    Show-StartupDiagnostics -LogsDir $logsDir -ServiceName $SERVICE_NAME
}
