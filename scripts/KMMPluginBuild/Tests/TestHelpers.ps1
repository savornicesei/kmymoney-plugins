function Import-TestBuildModule {
    <#
    .SYNOPSIS
    Imports the real module, optionally copied into a synthetic repository.
    #>
    [CmdletBinding()]
    param([string]$RepositoryRoot)
    $Source = Split-Path -Parent $PSScriptRoot
    $Destination = $Source
    if ($RepositoryRoot) {
        Copy-Item -LiteralPath (Join-Path ([IO.Path]::GetFullPath('../../..', $PSScriptRoot)) 'env.example.ini') -Destination $RepositoryRoot
        $Destination = Join-Path $RepositoryRoot 'scripts/KMMPluginBuild'
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        foreach ($Item in 'Public', 'Private', 'KMMPluginBuild.psd1', 'KMMPluginBuild.psm1') {
            Copy-Item -LiteralPath (Join-Path $Source $Item) -Destination $Destination -Recurse -Force
        }
    }
    Get-Module KMMPluginBuild -All | Remove-Module -Force
    Import-Module (Join-Path $Destination 'KMMPluginBuild.psd1') -Force -Global -PassThru
}
