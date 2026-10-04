function Invoke-KMMNativeTool {
    <#
    .SYNOPSIS
    Runs a native tool with literal arguments and preserves failure status.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Executable, [string[]]$ArgumentList = @())
    $PSNativeCommandUseErrorActionPreference = $false
    & $Executable @ArgumentList
    if ($LASTEXITCODE -ne 0) { throw "$Executable failed with exit code $LASTEXITCODE." }
}
