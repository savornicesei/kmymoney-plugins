function Stop-KMMBuildSession {
    <#
    .SYNOPSIS
    Restores the build caller's environment and location.
    .DESCRIPTION
    KeepEnvironment retains successful EnterCraft changes for interactive shells.
    .EXAMPLE
    Stop-KMMBuildSession -Context $Context
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Mandatory lifecycle cleanup must restore the caller without confirmation.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Context, [switch]$KeepEnvironment)
    if ($null -eq $Context.Environment) { return }
    if (-not $KeepEnvironment) {
        foreach ($Name in @([Environment]::GetEnvironmentVariables().Keys)) {
            if (-not $Context.Environment.Contains($Name)) { Remove-Item -LiteralPath "Env:$Name" }
        }
        foreach ($Name in $Context.Environment.Keys) {
            [Environment]::SetEnvironmentVariable($Name, $Context.Environment[$Name], 'Process')
        }
        if ($Context.CraftFunction) { Set-Item Function:global:craft $Context.CraftFunction }
        else { Remove-Item Function:global:craft -ErrorAction SilentlyContinue }
    }
    Set-Location -LiteralPath $Context.Location
}
