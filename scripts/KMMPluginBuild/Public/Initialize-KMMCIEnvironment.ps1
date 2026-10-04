function Initialize-KMMCIEnvironment {
    <#
    .SYNOPSIS
    Provisions a Craft KMyMoney SDK for the shared CI task graph.
    .DESCRIPTION
    Uses the same installer as FirstRun and records the requested host version.
    .PARAMETER Context
    Build context including the selected configuration and application version.
    .EXAMPLE
    ./build.ps1 -Tasks CI -KMMAppVersion master -EnvFile env.ci.ini
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Explicit CI task delegates provisioning to the shared installer.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Context)
    Install-KMMApplication -Context $Context
    $ReportDirectory = Join-Path $Context.Source 'build/ci'
    New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
    $Context.KMMAppVersion | Set-Content -LiteralPath (Join-Path $ReportDirectory 'kmymoney-version.txt')
}
