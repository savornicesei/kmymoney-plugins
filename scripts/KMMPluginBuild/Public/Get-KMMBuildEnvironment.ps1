function Get-KMMBuildEnvironment {
    <#
    .SYNOPSIS
    Resolves project configuration from the example and selected local INI.
    .DESCRIPTION
    Local file entries override example defaults. Returns literal values without
    modifying the process. CI plugin overrides are applied by build.ps1.
    .PARAMETER EnvFile
    Optional INI path relative to the repository; defaults to env.ini.
    .PARAMETER AllowMissing
    Allows FirstRun to create a selected file that does not yet exist.
    .EXAMPLE
    Get-KMMBuildEnvironment -EnvFile laptop.env.ini
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([string]$EnvFile, [switch]$AllowMissing)

    $Values = Read-KMMLocalEnvironment -EnvFile (Join-Path $script:RepositoryRoot 'env.example.ini')
    $Selected = if ($EnvFile) { [IO.Path]::GetFullPath($EnvFile, $script:RepositoryRoot) }
        else { Join-Path $script:RepositoryRoot 'env.ini' }
    if ($AllowMissing -and -not (Test-Path -LiteralPath $Selected -PathType Leaf)) { return $Values }
    $Overrides = Read-KMMLocalEnvironment -EnvFile $EnvFile
    foreach ($Name in $Overrides.Keys) { $Values[$Name] = $Overrides[$Name] }
    return $Values
}
