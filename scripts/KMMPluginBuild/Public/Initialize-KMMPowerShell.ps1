function Initialize-KMMPowerShell {
    <#
    .SYNOPSIS
    Downloads and imports the repository's required PowerShell modules.
    .DESCRIPTION
    Defines all module versions in one place. Saves missing versions from PSGallery
    into a local module directory and imports those versions into the calling session.
    Existing cached versions are validated and reused without downloading them again.
    Does not change PSGallery trust or install modules into the user's profile.
    .PARAMETER Path
    Module cache directory. Defaults to build/powershell/modules in this repository.
    Relative paths are resolved against the repository root, not the current directory.
    .EXAMPLE
    ./build.ps1 -Tasks Setup
    .EXAMPLE
    ./build.ps1 -Tasks Setup -ModulePath .cache/powershell -Verbose
    .EXAMPLE
    Get-Help ./build.ps1 -Full
    .NOTES
    Adds the cache to this process's PSModulePath so child pwsh processes can find it.
    Downloads remain cached after a failure. Start a new pwsh session after changing
    versions of modules whose assemblies are already loaded. Use an ignored directory
    for custom caches. The default cache is already ignored by Git.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [string]$Path = ''
    )

    $ErrorActionPreference = 'Stop'
    $RepositoryRoot = $script:RepositoryRoot
    $ModuleRoot = if ([string]::IsNullOrWhiteSpace($Path)) {
        Join-Path $RepositoryRoot 'build/powershell/modules'
    } else {
        [IO.Path]::GetFullPath($Path, $RepositoryRoot)
    }

    # This is the single source of module versions for development and CI.
    $RequiredModules = [ordered]@{
        InvokeBuild = '5.11.0'
        Pester = '6.0.1'
        PSScriptAnalyzer = '1.24.0'
    }

    if (-not $PSCmdlet.ShouldProcess($ModuleRoot, 'Download and import required PowerShell modules')) { return }
    New-Item -ItemType Directory -Path $ModuleRoot -Force | Out-Null
    foreach ($Name in $RequiredModules.Keys) {
        $Version = $RequiredModules[$Name]
        $Manifest = Join-Path $ModuleRoot "$Name/$Version/$Name.psd1"
        if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) {
            Write-Verbose "Downloading $Name $Version to $ModuleRoot"
            Save-Module -Name $Name -RequiredVersion $Version -Repository PSGallery -Path $ModuleRoot -Force -ErrorAction Stop
        }
        $Metadata = Test-ModuleManifest -Path $Manifest -ErrorAction Stop
        if ($Metadata.Version -ne [version]$Version) {
            throw "Module cache version mismatch for ${Name}: expected $Version at $Manifest."
        }
    }

    $OriginalModulePath = $env:PSModulePath
    try {
        $Entries = @($OriginalModulePath -split [regex]::Escape([string][IO.Path]::PathSeparator))
        $env:PSModulePath = (@($ModuleRoot) + @($Entries | Where-Object { $_ -and $_ -ne $ModuleRoot })) -join [IO.Path]::PathSeparator
        foreach ($Name in $RequiredModules.Keys) {
            $Version = $RequiredModules[$Name]
            $Manifest = Join-Path $ModuleRoot "$Name/$Version/$Name.psd1"
            Import-Module -Name $Manifest -Global -ErrorAction Stop
        }
    } catch {
        $env:PSModulePath = $OriginalModulePath
        throw
    }
}
