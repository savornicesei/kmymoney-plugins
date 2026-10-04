#Requires -Version 7.0
#Requires -PSEdition Core

function Get-KMMCraftReleaseHost {
    <#
    .SYNOPSIS
    Reads installed Craft host provenance without changing the selected package.
    .DESCRIPTION
    Craft's version setting alone is not evidence of the installed SDK. Export its
    installed-package inventory and match the requested target, SDK version and
    installed revision before allowing release packaging.
    .EXAMPLE
    Get-KMMCraftReleaseHost -Context $Context -Directory $InspectionDirectory
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][hashtable]$Context, [Parameter(Mandatory)][string]$Directory)
    $ErrorActionPreference = 'Stop'
    $null = New-Item -ItemType Directory -Path $Directory -Force
    $Inventory = Join-Path $Directory 'craft-installed.ini'
    Invoke-KMMNativeTool $env:CRAFT_PYTHON @((Join-Path $env:CRAFT_ROOT 'craft/bin/craft.py'), '-q', '--shelve', $Inventory) | Out-Null
    $Installed = @{}
    $InHost = $false
    foreach ($Line in Get-Content -LiteralPath $Inventory -Encoding utf8) {
        if ($Line -match '^\[(.+)\]$') { $InHost = $Matches[1] -ceq 'extragear/kmymoney'; continue }
        if ($InHost -and $Line -match '^\s*(version|revision)\s*=\s*(.*?)\s*$') { $Installed[$Matches[1]] = $Matches[2] }
    }
    $Target = $Installed.version
    if (-not $Target -or $Target -notmatch '^([A-Za-z][A-Za-z0-9_-]*|[0-9]+\.[0-9]+(?:\.[0-9]+)?)$') {
        throw 'Craft did not report a supported installed KMyMoney target. Provision the host with FirstRun.'
    }
    if ($Context.KMMAppVersion -and $Context.KMMAppVersion -cne $Target) {
        throw "Requested KMyMoney '$($Context.KMMAppVersion)' but Craft has '$Target' installed. Run FirstRun with the requested -KMMAppVersion and matching EnvFile before Release."
    }
    $HostBuild = $env:KMYMONEY_BUILD_DIR
    if (-not $HostBuild) { $HostBuild = Join-Path $env:CRAFT_ROOT 'build/extragear/kmymoney/work/build' }
    $Header = Join-Path $HostBuild 'config-kmymoney-version.h'
    $HeaderText = Get-Content -LiteralPath $Header -Raw
    if ($HeaderText -notmatch '(?m)^#define VERSION "([^"]+)"') { throw "Cannot read the matching host version from $Header." }
    $HostVersion = $Matches[1]
    if ($HostVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9._-]+)?$') { throw "Invalid host SDK version: $HostVersion" }
    $Cache = Get-Content -LiteralPath (Join-Path $HostBuild 'CMakeCache.txt') -Raw
    if ($Cache -notmatch '(?m)^BUILD_WITH_QT6:BOOL=(ON|TRUE|1)\r?$') {
        throw 'The installed host SDK is not a Qt 6 build. KMyMoney 5.1/Qt 5 is incompatible with this plugin project.'
    }
    $CoreVersion = ($HostVersion -split '-', 2)[0]
    if ($Target -match '^[0-9]+\.[0-9]+$' -and -not $CoreVersion.StartsWith("$Target.", [StringComparison]::Ordinal)) {
        throw "Host SDK $HostVersion does not belong to installed Craft target $Target."
    }
    if ($Target -match '^[0-9]+\.[0-9]+\.[0-9]+$' -and $Target -cne $CoreVersion) {
        throw "Host SDK $HostVersion does not match installed Craft release $Target."
    }
    if ($Installed.revision) {
        if ($HostVersion -notmatch '-([0-9a-fA-F]{7,40})$') { throw 'Host SDK version does not identify the installed Craft revision.' }
        $HeaderRevision = $Matches[1]
        if (-not $Installed.revision.StartsWith($HeaderRevision, [StringComparison]::OrdinalIgnoreCase) -and
            -not $HeaderRevision.StartsWith($Installed.revision, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Host SDK revision differs from the installed Craft package. Rebuild the matching host SDK before Release.'
        }
    } elseif ($Target -match '^[A-Za-z]' -or $Target.Split('.').Count -eq 2) {
        throw 'Craft did not record an installed revision for this branch. Provision it from source with FirstRun.'
    }
    return @{ Target = $Target; Version = $HostVersion; Revision = [string]$Installed.revision; BuildDirectory = $HostBuild }
}
