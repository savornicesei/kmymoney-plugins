#Requires -Version 7.0
#Requires -PSEdition Core

function Get-KMMReleaseCompatibility {
    <#
    .SYNOPSIS
    Validates the release matrix and returns the selected plugin-version policies.
    .EXAMPLE
    Get-KMMReleaseCompatibility -Context $Context -Version 0.1.0
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][hashtable]$Context, [Parameter(Mandatory)][string]$Version)
    $ErrorActionPreference = 'Stop'
    $Path = Join-Path $Context.Source 'release-compatibility.json'
    $Json = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    if (-not (Test-Json -Json $Json -SchemaFile (Join-Path $Context.Source 'release-compatibility.schema.json') -ErrorAction Stop)) {
        throw "Invalid release compatibility matrix: $Path"
    }
    $Matrix = ConvertFrom-Json -InputObject $Json -AsHashtable
    $Selected = @{}
    foreach ($Plugin in $Context.Plugins) {
        if (-not $Matrix.plugins.ContainsKey($Plugin) -or -not $Matrix.plugins[$Plugin].ContainsKey($Version)) {
            throw "No release compatibility entry for $Plugin $Version. Update release-compatibility.json before releasing."
        }
        $Policy = $Matrix.plugins[$Plugin][$Version]
        if ($Policy.qtMajor -ne 6) { throw "$Plugin $Version requires Qt $($Policy.qtMajor); this build supports only Qt 6/KF6." }
        # Validate all intervals even if an earlier selector would match.
        foreach ($Selector in $Policy.kmymoney) {
            $null = Test-KMMVersionSelector -Selector $Selector -Target '0.0.0' -HostVersion '0.0.0'
        }
        $Selected[$Plugin] = $Policy
    }
    return $Selected
}
