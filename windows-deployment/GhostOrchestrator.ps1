$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "scripts\lib\Layout.ps1")
. (Join-Path $PSScriptRoot "scripts\lib\Runtime.Helpers.ps1")

$layout = Get-DeploymentLayout -BaseDir $PSScriptRoot
$environment = Import-DeploymentEnvironment -BaseDir $PSScriptRoot -EnvironmentName 'default'
$manifestPath = Resolve-DeploymentConfigPath -BaseDir $PSScriptRoot -RelativePath $environment.Config.DeploymentManifest
$dataDir = Join-Path $PSScriptRoot "data"
$nginxDir = Join-Path $PSScriptRoot "nginx"
$nodeExe = Join-Path (Join-Path $PSScriptRoot "node") "node.exe"
$logDir = Join-Path $PSScriptRoot "logs"
$mongoDir = Join-Path $PSScriptRoot "mongodb"

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
if (-not (Test-Path $manifestPath)) {
    Write-Error "FATAL: deployment manifest not found at $manifestPath"
    exit 1
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$children = @{}

foreach ($prop in $manifest.services.PSObject.Properties) {
    $proc = Start-ManifestService -Name $prop.Name -Cfg $prop.Value -BaseDir $PSScriptRoot -MongoDir $mongoDir -NginxDir $nginxDir -NodeExe $nodeExe -DataDir $dataDir -LogDir $logDir
    if ($proc) { $children[$prop.Name] = $proc }
}

foreach ($prop in $manifest.services.PSObject.Properties) {
    if ($prop.Value.type -eq "mongo" -and $children.ContainsKey($prop.Name)) {
        Ensure-MongoReplicaSet -Name $prop.Name -Cfg $prop.Value -BaseDir $PSScriptRoot -LogDir $logDir
    }
}

Write-Host "`nAll services launched. Entering monitor loop...`n"

try {
    while ($true) {
        Start-Sleep -Seconds 5
        foreach ($name in @($children.Keys)) {
            $proc = $children[$name]
            if ($proc.HasExited) {
                Write-Warning "$name (PID $($proc.Id)) exited with code $($proc.ExitCode). Restarting..."
                $cfg = $manifest.services.PSObject.Properties[$name].Value
                $restartProc = Start-ManifestService -Name $name -Cfg $cfg -BaseDir $PSScriptRoot -MongoDir $mongoDir -NginxDir $nginxDir -NodeExe $nodeExe -DataDir $dataDir -LogDir $logDir
                if ($restartProc) {
                    $children[$name] = $restartProc
                    if ($cfg.type -eq "mongo") {
                        Ensure-MongoReplicaSet -Name $name -Cfg $cfg -BaseDir $PSScriptRoot -LogDir $logDir
                    }
                }
            }
        }
    }
} finally {
    Write-Host "`nShutting down all services..."
    foreach ($name in $children.Keys) {
        $proc = $children[$name]
        if (-not $proc.HasExited) {
            Write-Host "  Stopping $name (PID $($proc.Id))..."
            try { $proc.Kill() } catch {}
        }
    }
    Write-Host "All services stopped."
}
