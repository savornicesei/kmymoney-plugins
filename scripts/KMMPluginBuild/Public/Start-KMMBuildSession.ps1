function Start-KMMBuildSession {
    <#
    .SYNOPSIS
    Captures the caller's environment and applies the selected INI configuration.
    .EXAMPLE
    Start-KMMBuildSession -Context $Context
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Build lifecycle initialization applies configuration with automatic cleanup.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Context)
    $Context.Environment = [Environment]::GetEnvironmentVariables()
    $ExistingCraft = Get-Item Function:craft -ErrorAction SilentlyContinue
    $Context.CraftFunction = if ($ExistingCraft) { $ExistingCraft.ScriptBlock } else { $null }
    $Context.Location = $PWD.Path
    if ($Context.EnvironmentValues) {
        foreach ($Name in $Context.EnvironmentValues.Keys) {
            $Value = $Context.EnvironmentValues[$Name]
            if ($Value) { [Environment]::SetEnvironmentVariable($Name, $Value, 'Process') }
            else { Remove-Item -LiteralPath "Env:$Name" -ErrorAction SilentlyContinue }
        }
    }
}
