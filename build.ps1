#Requires -Version 7.0
#Requires -PSEdition Core

<#
.SYNOPSIS
Single entry point for KMM Plugin Build development and CI tasks.
.DESCRIPTION
Loads the KMMPluginBuild module and its centrally versioned dependencies, then
runs the selected Invoke-Build tasks. Normal tasks restore the caller's environment;
EnterCraft intentionally retains it for an interactive PowerShell session.
.PARAMETER Tasks
Task names. Defaults to Build. Use ? to list tasks.
.PARAMETER Plugins
Plugin directory names, or all alone. Defaults to all; CI initialization overrides
this value with KMM_PLUGINS from the selected environment configuration.
.PARAMETER EnvFile
Local path configuration file, relative to the repository root.
.PARAMETER ModulePath
Optional cache directory for the centrally configured PowerShell dependencies.
.PARAMETER Target
Optional native CMake target for Build.
.PARAMETER Version
Required numeric major.minor.patch release version for Release. Sets package and
embedded plugin versions; independent of KMMAppVersion.
.PARAMETER KMMAppVersion
KMyMoney version or branch supported by Craft, passed as version to craft --set.
Defaults to KMM_APP_VERSION in the selected INI. Empty retains Craft's selection.
.PARAMETER KMMAppFile
Existing .kmy, .sqlite, or .xml file opened by Run. Relative to the repository root.
Defaults to data/sample-data.xml. Pass an empty string to use no explicit file.
.PARAMETER KMMAppArguments
Literal arguments forwarded by Run to KMyMoney.
.PARAMETER GenerateOnly
OpenWorkspace writes its local workspace without launching VS Code.
.PARAMETER Preview
Preview EnterCraft, OpenWorkspace, or UpdateTranslations without their side effects.
Dependency setup still runs before the task graph.
.EXAMPLE
./build.ps1 -Tasks FirstRun
.EXAMPLE
./build.ps1 -Tasks BuildCI -Plugins draft-transactions -EnvFile laptop.env.ini
.EXAMPLE
./build.ps1 -Tasks OpenWorkspace -GenerateOnly
.EXAMPLE
./build.ps1 -Tasks UpdateTranslations -Plugins draft-transactions -Preview
.EXAMPLE
pwsh -NoProfile -NoExit -File ./build.ps1 -Tasks EnterCraft
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Invoke-Build executes lifecycle and task blocks in a shared build scope.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingCmdletAliases', '',
    Justification = 'Invoke-Build is the module entry point and task defines the task graph.'
)]
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()][string[]]$Tasks = @('Build'),
    [ValidateNotNullOrEmpty()][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]*$')]
    [string[]]$Plugins = @('all'),
    [string]$EnvFile,
    [string]$ModulePath,
    [string]$Target,
    [ValidatePattern('^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')]
    [string]$Version,
    [string]$KMMAppVersion,
    [string]$KMMAppFile = 'data/sample-data.xml',
    [string[]]$KMMAppArguments = @(),
    [switch]$GenerateOnly,
    [switch]$Preview
)

#####################################################
# initialization: Invoke-Build module
#####################################################
$ErrorActionPreference = 'Stop'
if ('Release' -in $Tasks -and -not $Version) { throw 'Release requires -Version major.minor.patch.' }
if ($Version -and 'Release' -notin $Tasks) { throw 'Version can only be used with the Release task.' }
if ($PSBoundParameters.ContainsKey('KMMAppFile') -and $KMMAppFile -and 'Run' -notin $Tasks) {
    throw 'KMMAppFile can only be used with the Run task.'
}
if ($KMMAppArguments.Count -and 'Run' -notin $Tasks) { throw 'KMMAppArguments can only be used with the Run task.' }
if ($Target -and 'Build' -notin $Tasks) { throw 'Target can only be used with the Build task.' }
if ($GenerateOnly -and 'OpenWorkspace' -notin $Tasks) { throw 'GenerateOnly requires the OpenWorkspace task.' }
if ($Preview -and @($Tasks | Where-Object { $_ -notin 'EnterCraft', 'OpenWorkspace', 'UpdateTranslations' }).Count) {
    throw 'Preview supports only EnterCraft, OpenWorkspace, and UpdateTranslations.'
}
# Reload edited functions in persistent IDE terminals. Invoke-Build's internal
# invocation reuses that instance so task state and module mocks stay intact.
Import-Module (Join-Path $PSScriptRoot 'scripts/KMMPluginBuild/KMMPluginBuild.psd1') -Global `
    -Force:($MyInvocation.ScriptName -notlike '*Invoke-Build.ps1')
if ($MyInvocation.ScriptName -notlike '*Invoke-Build.ps1') {
    Initialize-KMMPowerShell -Path $ModulePath -Confirm:$false
    Invoke-Build -Task $Tasks -File $MyInvocation.MyCommand.Path @PSBoundParameters
    # Returning keeps pwsh -NoExit and an existing interactive shell alive.
    return
}

#####################################################
# initialization: global variables
#####################################################
$IsCIBuild = $env:CI -match '^(true|1)$' -or $env:TF_BUILD -eq 'True' -or $env:GITHUB_ACTIONS -eq 'true'
$SRC_DIR = $PSScriptRoot
$EnvironmentValues = Get-KMMBuildEnvironment -EnvFile $EnvFile -AllowMissing:('FirstRun' -in $Tasks)
if ($IsCIBuild) {
    $Selection = if ($env:KMM_PLUGINS) { $env:KMM_PLUGINS } else { $EnvironmentValues.KMM_PLUGINS }
    $Plugins = @($Selection.Split(',') | ForEach-Object { $_.Trim() })
    $EnvironmentValues.KMM_PLUGINS = $Selection
}
if (-not $PSBoundParameters.ContainsKey('KMMAppVersion')) { $KMMAppVersion = $EnvironmentValues.KMM_APP_VERSION }
$EnvironmentValues.KMM_APP_VERSION = $KMMAppVersion
$BuildState = New-KMMBuildContext -Plugins $Plugins -EnvFile $EnvFile
$BuildState.KMMAppVersion = $KMMAppVersion
$BuildState.EnvironmentValues = $EnvironmentValues
$BuildState.KeepEnvironment = $false
Enter-Build { Start-KMMBuildSession -Context $BuildState }
Exit-Build { Stop-KMMBuildSession -Context $BuildState -KeepEnvironment:$BuildState.KeepEnvironment }

#####################################
# Functions
#####################################
# Implementation lives in scripts/KMMPluginBuild/Public and Private.

#####################################
# Tasks
#####################################
task Init { Invoke-KMMBuildStep -Context $BuildState -Step Init }
task Clean Init, { Invoke-KMMBuildStep -Context $BuildState -Step Clean }
task Build Init, { Invoke-KMMBuildStep -Context $BuildState -Step Build -Target $Target }
task Test Build, { Invoke-KMMBuildStep -Context $BuildState -Step Test }
task Stage Build, { Invoke-KMMBuildStep -Context $BuildState -Step Stage }
task Release { Invoke-KMMRelease -Context $BuildState -Version $Version }

#####################################
# Additional Tasks
#####################################
task Setup { Initialize-KMMPowerShell -Path $ModulePath -Confirm:$false }
task FirstRun { Initialize-KMMLocalEnvironment -EnvFile $EnvFile -ModulePath $ModulePath -KMMAppVersion $KMMAppVersion }
task Configure Init
task Install Stage
task Run { Invoke-KMMDevelopment -Action Run -EnvFile $EnvFile -KMMAppArguments $KMMAppArguments -KMMAppFile $KMMAppFile }
task EnterCraft {
    Enter-KMMCraftEnvironment -EnvFile $EnvFile -WhatIf:$Preview -Confirm:$false
    $BuildState.KeepEnvironment = -not $Preview
}
task OpenWorkspace { Open-KMMWorkspace -EnvFile $EnvFile -GenerateOnly:$GenerateOnly -WhatIf:$Preview -Confirm:$false }
task UpdateTranslations {
    foreach ($Plugin in $BuildState.Plugins) {
        Update-KMMTranslation -Plugin $Plugin -EnvFile $EnvFile -WhatIf:$Preview -Confirm:$false
    }
}
task Check {
    Enter-KMMCraftEnvironment -EnvFile $BuildState.EnvFile -Confirm:$false
    Invoke-KMMCheck
}
task PrepareCI { Initialize-KMMCIEnvironment -Context $BuildState }
task CI PrepareCI, Check, BuildCI

#####################################
# Default Task(s)
#####################################
#region Default Task
task . Build
task BuildCI Build, Test, Stage
#endregion
