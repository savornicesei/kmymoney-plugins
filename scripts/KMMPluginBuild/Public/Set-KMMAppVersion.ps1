function Set-KMMAppVersion {
    <#
    .SYNOPSIS
    Selects the KMyMoney blueprint version in the active Craft installation.
    .DESCRIPTION
    Uses Craft's persistent version setting on Windows, Linux, and macOS.
    Selecting a version does not itself rebuild the installed application or SDK.
    .PARAMETER KMMAppVersion
    Blueprint version or branch. Empty preserves the current Craft selection.
    .EXAMPLE
    ./build.ps1 -Tasks Build -KMMAppVersion master
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$KMMAppVersion)
    if ([string]::IsNullOrWhiteSpace($KMMAppVersion)) { return }
    if ($KMMAppVersion -match '[\r\n\x00]') { throw 'KMMAppVersion must be a single literal version or branch.' }
    if ($PSCmdlet.ShouldProcess('Craft extragear/kmymoney', "Set version=$KMMAppVersion")) {
        Invoke-KMMNativeTool -Executable $env:CRAFT_PYTHON -ArgumentList @(
            (Join-Path $env:CRAFT_ROOT 'craft/bin/craft.py'), '--set', "version=$KMMAppVersion", 'extragear/kmymoney'
        )
    }
}
