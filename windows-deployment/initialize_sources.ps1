[CmdletBinding()]
param(
    [string]$Manifest = "initialize_sources.example.json",
    [switch]$PlanOnly,
    [switch]$OverwriteExisting
)

$ErrorActionPreference = "Stop"

$SCRIPT_DIR = $PSScriptRoot
$PROJECT_ROOT = Split-Path $SCRIPT_DIR -Parent
$PLAN_LINES = New-Object System.Collections.Generic.List[string]

function Write-Step {
    param([string]$Message)

    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-PlanLine {
    param([string]$Message)

    $PLAN_LINES.Add($Message) | Out-Null
}

function Resolve-ProjectPath {
    param([string]$RelativePath)

    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $PROJECT_ROOT $RelativePath))
    $projectRootWithSlash = $PROJECT_ROOT.TrimEnd("\") + "\"
    if ($fullPath -ne $PROJECT_ROOT -and -not $fullPath.StartsWith($projectRootWithSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path '$RelativePath' resolves outside the project root."
    }

    return $fullPath
}

function Get-EntryNames {
    param([object]$Entries)

    return @($Entries.PSObject.Properties | ForEach-Object { $_.Name })
}

function Get-EntryValue {
    param(
        [object]$Entries,
        [string]$Name
    )

    return $Entries.PSObject.Properties[$Name].Value
}

function Test-RepoDirty {
    param([string]$RepoPath)

    $status = git -C $RepoPath status --porcelain
    return -not [string]::IsNullOrWhiteSpace(($status -join "`n"))
}

function Ensure-ParentDirectory {
    param([string]$TargetPath)

    $parent = Split-Path $TargetPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
}

function Remove-ExistingTarget {
    param([string]$TargetPath)

    if (-not (Test-Path $TargetPath)) {
        return
    }

    Remove-Item -LiteralPath $TargetPath -Recurse -Force
}

function Copy-LocalSource {
    param(
        [string]$SourcePath,
        [string]$TargetPath,
        [bool]$AllowOverwrite
    )

    if (-not (Test-Path $SourcePath)) {
        throw "Local source path '$SourcePath' does not exist."
    }

    if ((Test-Path $TargetPath) -and -not $AllowOverwrite) {
        throw "Target '$TargetPath' already exists. Re-run with -OverwriteExisting to replace it."
    }

    if ($AllowOverwrite) {
        Remove-ExistingTarget -TargetPath $TargetPath
    }

    Ensure-ParentDirectory -TargetPath $TargetPath

    $sourceItem = Get-Item -LiteralPath $SourcePath
    if ($sourceItem.PSIsContainer) {
        Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -Recurse
    } else {
        Copy-Item -LiteralPath $SourcePath -Destination $TargetPath
    }
}

function Initialize-GitSource {
    param(
        [string]$Name,
        [object]$Entry,
        [bool]$AllowOverwrite
    )

    $source = $Entry.source
    $targetPath = Resolve-ProjectPath -RelativePath $Entry.target_path
    $ref = $source.ref
    if ([string]::IsNullOrWhiteSpace($ref)) {
        $ref = $manifest.defaults.git_ref
    }

    Write-Step "Initializing git source '$Name'"

    if (-not (Test-Path $targetPath)) {
        Ensure-ParentDirectory -TargetPath $targetPath
        git clone $source.url $targetPath
    } else {
        if (-not (Test-Path (Join-Path $targetPath ".git"))) {
            throw "Target '$targetPath' exists but is not a git repository."
        }

        $repoIsDirty = Test-RepoDirty -RepoPath $targetPath
        if ($repoIsDirty -and -not $AllowOverwrite) {
            throw "Repository '$targetPath' has local changes. Re-run with -OverwriteExisting after reviewing them."
        }

        if ($repoIsDirty -and $AllowOverwrite) {
            git -C $targetPath reset --hard HEAD
            git -C $targetPath clean -fd
        }

        git -C $targetPath fetch --all --tags
    }

    git -C $targetPath checkout $ref
}

function Initialize-ArtifactSource {
    param(
        [string]$Name,
        [object]$Entry,
        [bool]$AllowOverwrite
    )

    $source = $Entry.source
    $targetPath = Resolve-ProjectPath -RelativePath $Entry.target_path

    Write-Step "Initializing artifact source '$Name'"

    if ((Test-Path $targetPath) -and -not $AllowOverwrite) {
        throw "Target '$targetPath' already exists. Re-run with -OverwriteExisting to replace it."
    }

    $cacheDir = Join-Path $SCRIPT_DIR ".downloads"
    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

    $fileName = [System.IO.Path]::GetFileName(($source.url -split "\?")[0])
    $downloadPath = Join-Path $cacheDir $fileName

    Invoke-WebRequest -Uri $source.url -OutFile $downloadPath

    if ($source.unpack) {
        if ($AllowOverwrite) {
            Remove-ExistingTarget -TargetPath $targetPath
        }

        $extractDir = Join-Path $cacheDir ([System.IO.Path]::GetFileNameWithoutExtension($fileName))
        if (Test-Path $extractDir) {
            Remove-ExistingTarget -TargetPath $extractDir
        }

        Expand-Archive -LiteralPath $downloadPath -DestinationPath $extractDir -Force

        $copySource = $extractDir
        if (-not [string]::IsNullOrWhiteSpace($source.archive_subpath)) {
            $copySource = Join-Path $extractDir $source.archive_subpath
        }

        Copy-LocalSource -SourcePath $copySource -TargetPath $targetPath -AllowOverwrite $AllowOverwrite
        return
    }

    Ensure-ParentDirectory -TargetPath $targetPath
    if ($AllowOverwrite) {
        Remove-ExistingTarget -TargetPath $targetPath
    }
    Copy-Item -LiteralPath $downloadPath -Destination $targetPath
}

function Initialize-LocalSource {
    param(
        [string]$Name,
        [object]$Entry,
        [bool]$AllowOverwrite
    )

    $source = $Entry.source
    $targetPath = Resolve-ProjectPath -RelativePath $Entry.target_path

    Write-Step "Initializing local source '$Name'"
    Copy-LocalSource -SourcePath $source.path -TargetPath $targetPath -AllowOverwrite $AllowOverwrite
}

$manifestPath = if ([System.IO.Path]::IsPathRooted($Manifest)) {
    $Manifest
} else {
    Join-Path $SCRIPT_DIR $Manifest
}
if (-not (Test-Path $manifestPath)) {
    throw "Manifest file '$manifestPath' was not found."
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$allowOverwrite = $OverwriteExisting.IsPresent

$entryNames = Get-EntryNames -Entries $manifest.entries
foreach ($name in $entryNames) {
    $entry = Get-EntryValue -Entries $manifest.entries -Name $name
    if ([string]::IsNullOrWhiteSpace($entry.target_path)) {
        throw "Entry '$name' is missing target_path."
    }

    if ($PlanOnly) {
        switch ($entry.source.type) {
            "git" {
                $ref = $entry.source.ref
                if ([string]::IsNullOrWhiteSpace($ref)) {
                    $ref = $manifest.defaults.git_ref
                }
                Write-PlanLine "[$name] git $($entry.source.url) -> $($entry.target_path) @ $ref"
            }
            "artifact" {
                $action = if ($entry.source.unpack) { "download+unpack" } else { "download" }
                Write-PlanLine "[$name] $action $($entry.source.url) -> $($entry.target_path)"
            }
            "local" {
                Write-PlanLine "[$name] local $($entry.source.path) -> $($entry.target_path)"
            }
            default {
                throw "Entry '$name' has unsupported source.type '$($entry.source.type)'."
            }
        }

        continue
    }

    switch ($entry.source.type) {
        "git" {
            Initialize-GitSource -Name $name -Entry $entry -AllowOverwrite $allowOverwrite
        }
        "artifact" {
            Initialize-ArtifactSource -Name $name -Entry $entry -AllowOverwrite $allowOverwrite
        }
        "local" {
            Initialize-LocalSource -Name $name -Entry $entry -AllowOverwrite $allowOverwrite
        }
        default {
            throw "Entry '$name' has unsupported source.type '$($entry.source.type)'."
        }
    }
}

if ($PlanOnly) {
    if ($PLAN_LINES.Count -gt 0) {
        Write-Output ($PLAN_LINES -join [Environment]::NewLine)
    }
    Write-Host ""
    Write-Host "Plan complete. No files were changed." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Initialization complete. You can now run .\build_package.ps1" -ForegroundColor Green
}
