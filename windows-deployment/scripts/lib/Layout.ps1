function Get-DeploymentLayout {
    param(
        [Parameter(Mandatory)]
        [string]$BaseDir
    )

    $resolvedBase = [System.IO.Path]::GetFullPath($BaseDir)
    $projectRoot = Split-Path $resolvedBase -Parent

    return [PSCustomObject]@{
        BaseDir = $resolvedBase
        ProjectRoot = $projectRoot
        ConfigDir = Join-Path $resolvedBase 'config'
        ScriptsDir = Join-Path $resolvedBase 'scripts'
        ToolsDir = Join-Path $resolvedBase 'tools'
        DeployPackageDir = Join-Path $resolvedBase 'deploy_package'
        BootstrapperDir = Join-Path $resolvedBase 'bootstrapper'
    }
}

function Import-DeploymentEnvironment {
    param(
        [Parameter(Mandatory)]
        [string]$BaseDir,
        [string]$EnvironmentName = 'default'
    )

    $layout = Get-DeploymentLayout -BaseDir $BaseDir
    $environmentPath = Join-Path (Join-Path $layout.ConfigDir 'environments') "$EnvironmentName.psd1"
    if (-not (Test-Path $environmentPath)) {
        throw "Deployment environment '$EnvironmentName' was not found at '$environmentPath'."
    }

    return Import-PowerShellDataFile -Path $environmentPath
}

function Resolve-DeploymentConfigPath {
    param(
        [Parameter(Mandatory)]
        [string]$BaseDir,
        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    return [System.IO.Path]::GetFullPath((Join-Path $BaseDir $RelativePath))
}
