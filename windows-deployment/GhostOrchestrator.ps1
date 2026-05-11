$ErrorActionPreference = "Stop"

$BASE = $PSScriptRoot
$MANIFEST = Join-Path $BASE "deployment_manifest.json"
$DATA_DIR = Join-Path $BASE "data"
$NGINX_DIR = Join-Path $BASE "nginx"
$NODE = Join-Path (Join-Path $BASE "node") "node.exe"
$LOG_DIR = Join-Path $BASE "logs"
$MONGO_DIR = Join-Path $BASE "mongodb"

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
        "mongo" {
            $exe = Join-Path (Join-Path $MONGO_DIR "bin") "mongod.exe"
            $dbPath = Join-Path $BASE $Cfg.db_path
            $logPath = Join-Path $BASE $Cfg.log_path
            $logDir = Split-Path $logPath -Parent
            if (-not (Test-Path $dbPath)) { New-Item -ItemType Directory -Path $dbPath -Force | Out-Null }
            if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
            $args = "--port $($Cfg.port) --bind_ip $($Cfg.bind_ip) --replSet $($Cfg.repl_set) --dbpath `"$dbPath`" --logpath `"$logPath`" --logappend"
            return Start-ServiceProcess -Name $Name -Exe $exe -Arguments $args -WorkDir $BASE -EnvVars $envHash
        }
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

function Wait-ForTcpPort {
    param(
        [string]$Host,
        [int]$Port,
        [int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $async = $client.BeginConnect($Host, $Port, $null, $null)
            if ($async.AsyncWaitHandle.WaitOne(1000) -and $client.Connected) {
                $client.EndConnect($async)
                return $true
            }
        } catch {
        } finally {
            $client.Dispose()
        }

        Start-Sleep -Milliseconds 500
    }

    return $false
}

function Ensure-MongoReplicaSet {
    param(
        [string]$Name,
        [object]$Cfg
    )

    $shellPath = Join-Path $BASE $Cfg.shell_exe
    if (-not (Test-Path $shellPath)) {
        Write-Warning "Mongo shell not found at '$shellPath'. Replica set initialization skipped for $Name."
        return
    }

    if (-not (Wait-ForTcpPort -Host $Cfg.bind_ip -Port ([int]$Cfg.port) -TimeoutSeconds 30)) {
        Write-Warning "MongoDB did not become ready on $($Cfg.bind_ip):$($Cfg.port). Replica set initialization skipped."
        return
    }

    $memberHost = "$($Cfg.bind_ip):$($Cfg.port)"
    $js = @"
try {
  rs.status();
  print('Replica set already initialized');
} catch (err) {
  if ((err.codeName && err.codeName === 'NotYetInitialized') || /not yet initialized|no replset config/i.test(err.message || '')) {
    rs.initiate({
      _id: '$($Cfg.repl_set)',
      members: [{ _id: 0, host: '$memberHost' }]
    });
    print('Replica set initialized');
  } else {
    throw err;
  }
}
"@

    $stdoutLog = Join-Path $LOG_DIR "$Name.init.out.log"
    $stderrLog = Join-Path $LOG_DIR "$Name.init.err.log"
    Add-Content -Path $stdoutLog -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Checking replica set state"

    & $shellPath --quiet --host $Cfg.bind_ip --port $Cfg.port --eval $js 1>> $stdoutLog 2>> $stderrLog
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Replica set initialization command for $Name exited with code $LASTEXITCODE. Check $stderrLog."
    } else {
        Write-Host "[OK]  $Name replica set ready"
    }
}

$children = @{}
foreach ($prop in $manifest.services.PSObject.Properties) {
    $proc = Start-ManifestService -Name $prop.Name -Cfg $prop.Value
    if ($proc) { $children[$prop.Name] = $proc }
}

foreach ($prop in $manifest.services.PSObject.Properties) {
    if ($prop.Value.type -eq "mongo" -and $children.ContainsKey($prop.Name)) {
        Ensure-MongoReplicaSet -Name $prop.Name -Cfg $prop.Value
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
                $restartProc = Start-ManifestService -Name $name -Cfg $cfg
                if ($restartProc) {
                    $children[$name] = $restartProc
                    if ($cfg.type -eq "mongo") {
                        Ensure-MongoReplicaSet -Name $name -Cfg $cfg
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
            try { $proc.Kill() } catch { }
        }
    }
    Write-Host "All services stopped."
}
