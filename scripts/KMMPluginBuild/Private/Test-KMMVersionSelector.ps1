#Requires -Version 7.0
#Requires -PSEdition Core

function Test-KMMVersionSelector {
    <#
    .SYNOPSIS
    Matches a Craft target and resolved host version against a compatibility selector.
    .DESCRIPTION
    Named targets match exactly. Numeric targets can match an exact target/version,
    a numeric glob (* or ?), or an inclusive range. A two-component upper range
    endpoint includes all patches of that minor series. Numeric selectors never
    grant support to master or other named development branches.
    .EXAMPLE
    Test-KMMVersionSelector -Selector '5.0 - 5.3' -Target 5.2 -HostVersion 5.2.1
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Selector,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$HostVersion
    )
    $Numeric = '^([0-9]+)\.([0-9]+)(?:\.([0-9]+))?$'
    if ($Selector -match '^[A-Za-z][A-Za-z0-9_-]*$') { return $Selector -ceq $Target }
    if ($Target -notmatch $Numeric) { return $false }
    $CoreVersion = ($HostVersion -split '-', 2)[0]
    if ($CoreVersion -notmatch $Numeric) { throw "Invalid resolved host version: $HostVersion" }
    if ($CoreVersion.Split('.').Count -eq 2) { $CoreVersion += '.0' }
    $Resolved = [version]$CoreVersion
    if ($Selector -match '^([0-9]+\.[0-9]+(?:\.[0-9]+)?) - ([0-9]+\.[0-9]+(?:\.[0-9]+)?)$') {
        $Lower = $Matches[1]
        $Upper = $Matches[2]
        if ($Lower.Split('.').Count -eq 2) { $Lower += '.0' }
        if ($Upper.Split('.').Count -eq 2) { $Upper += '.2147483647' }
        if ([version]$Lower -gt [version]$Upper) { throw "Reversed KMyMoney version interval: $Selector" }
        return $Resolved -ge [version]$Lower -and $Resolved -le [version]$Upper
    }
    if ($Selector -match '^[0-9*?]+(\.[0-9*?]+){1,2}$' -and $Selector -match '[*?]') {
        return $CoreVersion -like $Selector
    }
    if ($Selector -match $Numeric) {
        if ($Selector -ceq $Target) { return $true }
        if ($Selector.Split('.').Count -eq 2) { $Selector += '.0' }
        return $Resolved -eq [version]$Selector
    }
    throw "Invalid KMyMoney compatibility selector: $Selector"
}
