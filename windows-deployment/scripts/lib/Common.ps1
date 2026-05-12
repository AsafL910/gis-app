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

function Require-ToolFile {
    param(
        [string]$Path,
        [string]$Description
    )

    if (-not (Test-Path $Path)) {
        throw "Missing bundled tool input: $Description at '$Path'. Place it under windows-deployment\tools before building."
    }
}

function Ensure-CleanDirectory {
    param([string]$Path)

    if (Test-Path $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }

    New-Item -ItemType Directory -Path $Path | Out-Null
}

function Remove-PathWithRetry {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [int]$Attempts = 3,
        [int]$DelaySeconds = 2
    )

    if (-not (Test-Path $Path)) {
        return
    }

    $lastError = $null
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        } catch {
            $lastError = $_
            Stop-ProcessesUnderPath -RootPath $Path
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    throw "Failed to remove '$Path'. Close any running Setup/install windows or other processes using files under that folder, then try again. Last error: $($lastError.Exception.Message)"
}

function Stop-ProcessesUnderPath {
    param([string]$RootPath)

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

function Set-NginxRootDirective {
    param(
        [string]$ConfigPath,
        [string]$ResolvedRoot
    )

    $normalizedRoot = $ResolvedRoot -replace '\\', '/'
    $content = Get-Content $ConfigPath -Raw
    $pattern = '(?m)^(\s*root\s+)(?:"[^"]*"|[^;]+)(;)\s*$'

    if (-not [regex]::IsMatch($content, $pattern)) {
        throw "Could not rewrite nginx root directive in $ConfigPath"
    }

    $updated = [regex]::Replace(
        $content,
        $pattern,
        "`$1`"$normalizedRoot`"`$2"
    )

    Set-Content $ConfigPath $updated
}
