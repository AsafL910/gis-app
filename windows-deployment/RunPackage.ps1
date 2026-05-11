$ErrorActionPreference = "Stop"

$BASE = $PSScriptRoot
$orchestrator = Join-Path $BASE "GhostOrchestrator.ps1"
$uiUrl = "http://localhost:8013"
$logsDir = Join-Path $BASE "logs"
$serviceName = "GlbDemoService"
$requiredPorts = @(8000, 8001, 8002, 8011, 8013)

function Patch-NginxConfigsForLocalRun {
    param(
        [string]$PackageDir
    )

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

    $dataDir = Join-Path $PackageDir "data"
    $uiDistDir = Join-Path (Join-Path (Join-Path $PackageDir "services") "map-provider-ui") "dist"

    $dataConf = Join-Path (Join-Path (Join-Path $PackageDir "nginx") "conf") "nginx-data.conf"
    $uiConf = Join-Path (Join-Path (Join-Path $PackageDir "nginx") "conf") "nginx-ui.conf"

    if (Test-Path $dataConf) {
        Set-NginxRootDirective -ConfigPath $dataConf -ResolvedRoot $dataDir
    }

    if (Test-Path $uiConf) {
        Set-NginxRootDirective -ConfigPath $uiConf -ResolvedRoot $uiDistDir
    }
}

function Get-ListeningPortOwners {
    param(
        [int[]]$Ports
    )

    $owners = @()
    $portPattern = (($Ports | ForEach-Object { ":$_" }) -join "|")
    $netstatLines = @(netstat -ano | Select-String $portPattern)
    foreach ($line in $netstatLines) {
        $text = $line.ToString().Trim()
        if ($text -match '^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$') {
            $port = [int]$Matches[1]
            $pid = [int]$Matches[2]
            $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
            $owners += [PSCustomObject]@{
                Port = $port
                Pid = $pid
                ProcessName = if ($proc) { $proc.ProcessName } else { "<unknown>" }
                Path = if ($proc -and $proc.Path) { $proc.Path } else { "" }
            }
        }
    }

    $owners | Sort-Object Port,Pid -Unique
}

function Assert-PackagePortsAvailable {
    param(
        [int[]]$Ports
    )

    $owners = @(Get-ListeningPortOwners -Ports $Ports)
    if ($owners.Count -eq 0) {
        return
    }

    Write-Host "The package cannot be started because required ports are already in use:" -ForegroundColor Red
    foreach ($owner in $owners) {
        $pathSuffix = if ([string]::IsNullOrWhiteSpace($owner.Path)) { "" } else { " - $($owner.Path)" }
        Write-Host "  Port $($owner.Port): PID $($owner.Pid) $($owner.ProcessName)$pathSuffix" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Stop the existing GLB Demo service or the conflicting processes, then run .\\RunPackage.ps1 again." -ForegroundColor Yellow
    exit 1
}

function Assert-ServiceNotRunning {
    param(
        [string]$Name
    )

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne "Stopped") {
        Write-Host "$Name is currently $($service.Status)." -ForegroundColor Red
        Write-Host "Stop it before running the package in foreground:" -ForegroundColor Yellow
        Write-Host "  Stop-Service $Name" -ForegroundColor Cyan
        exit 1
    }
}

if (-not (Test-Path $orchestrator)) {
    throw "GhostOrchestrator.ps1 was not found at $orchestrator"
}

if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir | Out-Null
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  GLB Demo - Run Package Locally" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Package: $BASE" -ForegroundColor White
Write-Host "UI URL:  $uiUrl" -ForegroundColor White
Write-Host "Logs:    $logsDir" -ForegroundColor White
Write-Host ""
Assert-ServiceNotRunning -Name $serviceName
Assert-PackagePortsAvailable -Ports $requiredPorts
Patch-NginxConfigsForLocalRun -PackageDir $BASE
Write-Host "Running GhostOrchestrator.ps1 in the foreground." -ForegroundColor Yellow
Write-Host "Use Ctrl+C to stop all child processes." -ForegroundColor Yellow
Write-Host ""

& powershell.exe -ExecutionPolicy Bypass -NoProfile -File $orchestrator
