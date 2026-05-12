function Test-IsAdministrator {
    $principal = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )

    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-InstallContext {
    param(
        [string]$ServiceName,
        [string]$InstallDir,
        [switch]$Quiet,
        [string]$LogPath
    )

    return [PSCustomObject]@{
        ServiceName = $ServiceName
        InstallDir = $InstallDir
        QuietMode = $Quiet.IsPresent
        LogFilePath = $LogPath
    }
}

function Write-InstallLog {
    param(
        [Parameter(Mandatory)]
        [object]$Context,
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Context.LogFilePath)) {
        return
    }

    $logDir = Split-Path $Context.LogFilePath -Parent
    if (-not [string]::IsNullOrWhiteSpace($logDir) -and -not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $Context.LogFilePath -Value "[$timestamp] $Message"
}

function Write-InstallStatus {
    param(
        [Parameter(Mandatory)]
        [object]$Context,
        [string]$Message,
        [string]$Color = "White"
    )

    Write-InstallLog -Context $Context -Message $Message
    if (-not $Context.QuietMode) {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Get-DescendantProcessIds {
    param([int]$RootProcessId)

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
    param([int]$RootProcessId)

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
    param([string]$Name)

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
    param([string]$InstallDir)

    if (-not (Test-Path $InstallDir)) {
        return
    }

    function Remove-InstallItemWithRetry {
        param(
            [string]$ItemPath,
            [int]$Attempts = 3,
            [int]$DelaySeconds = 2
        )

        $lastError = $null
        for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
            try {
                Remove-Item -LiteralPath $ItemPath -Recurse -Force -ErrorAction Stop
                return
            } catch {
                $lastError = $_
                Stop-ProcessesUnderPath -RootPath $InstallDir
                Start-Sleep -Seconds $DelaySeconds
            }
        }

        throw "Failed to remove '$ItemPath' from '$InstallDir'. Close any running GLB Demo or Setup windows and try again. Last error: $($lastError.Exception.Message)"
    }

    $items = @(Get-ChildItem -LiteralPath $InstallDir -Force | Where-Object { $_.Name -ne "data" })
    foreach ($item in $items) {
        Remove-InstallItemWithRetry -ItemPath $item.FullName
    }
}

function Initialize-ServiceConfigDefaults {
    param(
        [string]$DefaultsRoot,
        [string]$TargetConfigRoot
    )

    if (-not (Test-Path $DefaultsRoot)) {
        return
    }

    New-Item -ItemType Directory -Force -Path $TargetConfigRoot | Out-Null
    $defaultsRootFull = [System.IO.Path]::GetFullPath($DefaultsRoot)
    $defaultsRootPrefix = $defaultsRootFull.TrimEnd('\') + '\'

    foreach ($item in Get-ChildItem -LiteralPath $DefaultsRoot -Recurse -File) {
        $sourcePath = [System.IO.Path]::GetFullPath($item.FullName)
        $relativePath = $sourcePath.Substring($defaultsRootPrefix.Length)
        $targetPath = Join-Path $TargetConfigRoot $relativePath
        $targetParent = Split-Path $targetPath -Parent

        if (-not (Test-Path $targetParent)) {
            New-Item -ItemType Directory -Force -Path $targetParent | Out-Null
        }

        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
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

    Stop-ProcessesUnderPath -RootPath $InstallDir
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

function Get-RecentLogFiles {
    param([string]$LogsDir)

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
        [string]$ServiceName,
        [string]$UiUrl
    )

    Write-Host ""
    Write-Host "Application did not become available at $UiUrl." -ForegroundColor Red

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
