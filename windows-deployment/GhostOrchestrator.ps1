$ErrorActionPreference = "Stop"

$BASE = $PSScriptRoot
$MANIFEST = Join-Path $BASE "deployment_manifest.json"
$DATA_DIR = Join-Path $BASE "data"
$NGINX_DIR = Join-Path $BASE "nginx"
$NODE = Join-Path (Join-Path $BASE "node") "node.exe"
$LOG_DIR = Join-Path $BASE "logs"

if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR | Out-Null }

if (-not (Test-Path $MANIFEST)) {
    Write-Error "FATAL: deployment_manifest.json not found at $MANIFEST"
    exit 1
}
$manifest = Get-Content $MANIFEST -Raw | ConvertFrom-Json

function Start-ServiceProcess {
    param(
        [string]$Name,
        [string]$Exe,
        [string]$Arguments,
        [string]$WorkDir,
        [hashtable]$EnvVars
    )

    $envCommands = @("set `"DATA_DIR=$DATA_DIR`"")
    foreach ($key in $EnvVars.Keys) {
        $envCommands += "set `"$key=$([string]$EnvVars[$key])`""
    }

    $quotedExe = '"' + $Exe + '"'
    $stdoutLog = Join-Path $LOG_DIR "$Name.out.log"
    $stderrLog = Join-Path $LOG_DIR "$Name.err.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $stdoutLog -Value @(
        "[$timestamp] Launching $Name",
        "  exe: $Exe",
        "  args: $Arguments",
        "  workdir: $WorkDir",
        ""
    )
    $commandWithLogs = "$quotedExe $Arguments 1>> `"$stdoutLog`" 2>> `"$stderrLog`""
    $cmdSegments = $envCommands + @($commandWithLogs)
    $cmdLine = [string]::Join(" && ", $cmdSegments)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c $cmdLine"
    $psi.WorkingDirectory = $WorkDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    try {
        $proc.Start() | Out-Null
        Write-Host "[OK]  $Name  PID=$($proc.Id)"
        return $proc
    } catch {
        Write-Error "[FAIL] $Name - $_"
        return $null
    }
}

function Start-ManifestService {
    param(
        [string]$Name,
        [object]$Cfg
    )

    $envHash = @{}
    if ($Cfg.env) {
        foreach ($e in $Cfg.env.PSObject.Properties) {
            $envHash[$e.Name] = $e.Value
        }
    }

    switch ($Cfg.type) {
        "nginx" {
            $exe = Join-Path $NGINX_DIR "nginx.exe"
            $args = "-c conf\$($Cfg.nginx_conf)"
            return Start-ServiceProcess -Name $Name -Exe $exe -Arguments $args -WorkDir $NGINX_DIR -EnvVars $envHash
        }
        "python" {
            $workDir = Join-Path $BASE $Cfg.working_dir
            $exe = Join-Path $BASE $Cfg.python_exe
            $envRoot = Split-Path $exe -Parent
            $sitePackages = Join-Path (Join-Path $envRoot "Lib") "site-packages"
            $envPathParts = @(
                (Join-Path $envRoot "Library\bin"),
                (Join-Path $envRoot "Scripts"),
                $envRoot,
                "%PATH%"
            )
            $envHash["PATH"] = [string]::Join(";", $envPathParts)
            $envHash["USE_PATH_FOR_GDAL_PYTHON"] = "1"
            foreach ($candidate in @(
                (Join-Path (Join-Path $envRoot "Library") "share\gdal"),
                (Join-Path $sitePackages "rasterio\gdal_data")
            )) {
                if (Test-Path $candidate) {
                    $envHash["GDAL_DATA"] = $candidate
                    break
                }
            }
            foreach ($candidate in @(
                (Join-Path (Join-Path $envRoot "Library") "share\proj"),
                (Join-Path $sitePackages "rasterio\proj_data"),
                (Join-Path (Join-Path (Join-Path $sitePackages "pyproj") "proj_dir") "share\proj")
            )) {
                if (Test-Path $candidate) {
                    $envHash["PROJ_LIB"] = $candidate
                    break
                }
            }
            $args = "-m uvicorn $($Cfg.module) --host 0.0.0.0 --port $($Cfg.internal_port)"
            return Start-ServiceProcess -Name $Name -Exe $exe -Arguments $args -WorkDir $workDir -EnvVars $envHash
        }
        "node" {
            $workDir = Join-Path $BASE $Cfg.working_dir
            $entry = Join-Path $workDir $Cfg.entry
            $args = "`"$entry`""
            return Start-ServiceProcess -Name $Name -Exe $NODE -Arguments $args -WorkDir $workDir -EnvVars $envHash
        }
        default {
            Write-Warning "Unknown service type '$($Cfg.type)' for $Name - skipping."
            return $null
        }
    }
}

$children = @{}
foreach ($prop in $manifest.services.PSObject.Properties) {
    $proc = Start-ManifestService -Name $prop.Name -Cfg $prop.Value
    if ($proc) { $children[$prop.Name] = $proc }
}

Write-Host "`nAll services launched. Entering monitor loop...`n"

try {
    while ($true) {
        Start-Sleep -Seconds 5

        foreach ($name in @($children.Keys)) {
            $proc = $children[$name]
            if ($proc.HasExited) {
                Write-Warning "$name (PID $($proc.Id)) exited with code $($proc.ExitCode). Restarting..."
                $restartProc = Start-ManifestService -Name $name -Cfg $manifest.services.$name
                if ($restartProc) { $children[$name] = $restartProc }
            }
        }
    }
} finally {
    Write-Host "`nShutting down all services..."
    foreach ($name in $children.Keys) {
        $proc = $children[$name]
        if (-not $proc.HasExited) {
            Write-Host "  Stopping $name (PID $($proc.Id))..."
            try { $proc.Kill() } catch { }
        }
    }
    Write-Host "All services stopped."
}
