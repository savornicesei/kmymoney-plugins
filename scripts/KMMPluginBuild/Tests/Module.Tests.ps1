#Requires -Version 7.0
#Requires -PSEdition Core
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester shares variables between setup and test blocks.')]
param()

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $Module = Import-TestBuildModule
    $ModuleRoot = Split-Path -Parent $PSScriptRoot
    $RepositoryRoot = [IO.Path]::GetFullPath('../../..', $PSScriptRoot)
}

Describe 'KMM Plugin Build module boundary' {
    It 'Exports exactly the public functions and no private helpers, variables, or aliases' {
        $Public = @(Get-ChildItem (Join-Path $ModuleRoot 'Public') -Filter '*.ps1' | ForEach-Object BaseName)
        @(Compare-Object $Public @($Module.ExportedFunctions.Keys)).Count | Should -Be 0
        $Module.ExportedVariables.Count | Should -Be 0
        $Module.ExportedAliases.Count | Should -Be 0
        Get-Command Read-KMMLocalEnvironment -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command Invoke-KMMNativeTool -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'Does not set up Craft, load build dependencies, or change environment variables when imported' {
        $Before = [Environment]::GetEnvironmentVariables()
        $DependenciesBefore = @(Get-Module InvokeBuild, Pester, PSScriptAnalyzer | ForEach-Object Path)
        $null = Import-TestBuildModule
        $After = [Environment]::GetEnvironmentVariables()
        $After.Count | Should -Be $Before.Count
        foreach ($Name in $Before.Keys) { $After[$Name] | Should -BeExactly $Before[$Name] }
        @(Get-Module InvokeBuild, Pester, PSScriptAnalyzer | ForEach-Object Path) | Should -Be $DependenciesBefore
    }

    It 'Keeps module implementation and tests under their own folders' {
        @(Get-ChildItem (Join-Path $RepositoryRoot 'scripts') -Filter '*.ps1').Count | Should -Be 0
        Test-Path (Join-Path $ModuleRoot 'KMMPluginBuild.psd1') | Should -BeTrue
        Test-Path (Join-Path $ModuleRoot 'KMMPluginBuild.psm1') | Should -BeTrue
    }

    It 'Routes every shared workspace process task and terminal profile through build.ps1' {
        $Workspace = Get-Content (Join-Path $RepositoryRoot 'kmymoney-plugin.code-workspace') -Raw | ConvertFrom-Json -AsHashtable
        foreach ($Task in $Workspace.tasks.tasks) {
            $Task.args | Should -Contain '${workspaceFolder:Plugins}/build.ps1'
            $Task.args | Should -Contain '-Tasks'
        }
        foreach ($Platform in 'windows', 'linux', 'osx') {
            $Arguments = $Workspace.settings["terminal.integrated.profiles.$Platform"]['KDE Craft (PowerShell 7)'].args
            $Arguments | Should -Contain '${workspaceFolder:Plugins}/build.ps1'
            $Arguments | Should -Contain 'EnterCraft'
            $Arguments | Should -Contain '-NoExit'
        }
    }

    It 'Routes Linux CI through the shared CI build task' {
        Get-Content (Join-Path $RepositoryRoot '.gitlab-ci.yml') -Raw | Should -Match '-File build\.ps1 -Tasks CI'
    }
}
