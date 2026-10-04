@{
    RootModule = 'KMMPluginBuild.psm1'
    ModuleVersion = '1.0.0'
    GUID = '726cbe90-8e34-42f7-b1f4-b62c254be63a'
    Author = 'KMyMoney plugin contributors'
    Description = 'KMM Plugin Build: development, translation, and CI tasks called by build.ps1.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @(
        'Initialize-KMMPowerShell', 'Initialize-KMMLocalEnvironment',
        'Enter-KMMCraftEnvironment', 'Invoke-KMMDevelopment', 'Open-KMMWorkspace',
        'Update-KMMTranslation', 'Initialize-KMMCIEnvironment', 'Set-KMMAppVersion', 'Invoke-KMMCheck',
        'New-KMMBuildContext', 'Get-KMMBuildEnvironment', 'Invoke-KMMBuildStep',
        'Start-KMMBuildSession', 'Stop-KMMBuildSession'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{ PSData = @{ Tags = @('KMyMoney', 'Craft', 'Build') } }
}
