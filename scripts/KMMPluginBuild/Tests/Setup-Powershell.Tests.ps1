#Requires -Version 7.0
#Requires -PSEdition Core
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester shares fixture variables across setup, test, and mock blocks.'
)]
param()

BeforeAll { . (Join-Path $PSScriptRoot 'TestHelpers.ps1') }

Describe 'Shared PowerShell module setup' {
    BeforeEach {
        $Fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $Fixture 'scripts') | Out-Null
        $Module = Import-TestBuildModule -RepositoryRoot $Fixture
        $Setup = Get-Command Initialize-KMMPowerShell
        $OriginalModulePath = $env:PSModulePath
        $OriginalLocation = $PWD.Path
        Mock -ModuleName KMMPluginBuild Save-Module {
            $Directory = Join-Path $Path "$Name/$RequiredVersion"
            New-Item -ItemType Directory -Path $Directory -Force | Out-Null
            '@{}' | Set-Content (Join-Path $Directory "$Name.psd1")
        }
        Mock -ModuleName KMMPluginBuild Test-ModuleManifest {
            [pscustomobject]@{ Version = [version](Split-Path (Split-Path $Path -Parent) -Leaf) }
        }
        Mock -ModuleName KMMPluginBuild Import-Module {} -ParameterFilter { $Global }
    }

    AfterEach {
        $env:PSModulePath = $OriginalModulePath
        Set-Location -LiteralPath $OriginalLocation
    }

    It 'Downloads exact versions into the default ignored cache and imports them globally' {
        & $Setup
        $Cache = Join-Path $Fixture 'build/powershell/modules'
        Should -Invoke -ModuleName KMMPluginBuild Save-Module -Times 3 -Exactly -ParameterFilter {
            $Repository -eq 'PSGallery' -and $Path -eq $Cache -and $RequiredVersion
        }
        Should -Invoke -ModuleName KMMPluginBuild Import-Module -Times 3 -Exactly -ParameterFilter { $Global -and $Name.StartsWith($Cache) }
        ($env:PSModulePath -split [regex]::Escape([string][IO.Path]::PathSeparator))[0] | Should -Be $Cache
    }

    It 'Reuses cached versions and does not duplicate the module search path' {
        & $Setup
        $AfterFirstSetup = $env:PSModulePath
        & $Setup
        Should -Invoke -ModuleName KMMPluginBuild Save-Module -Times 3 -Exactly
        $env:PSModulePath | Should -BeExactly $AfterFirstSetup
    }

    It 'Resolves a custom relative cache against the repository rather than the working directory' {
        Set-Location $TestDrive
        & $Setup -Path 'custom modules'
        $Cache = Join-Path $Fixture 'custom modules'
        Should -Invoke -ModuleName KMMPluginBuild Save-Module -Times 3 -Exactly -ParameterFilter { $Path -eq $Cache }
    }

    It 'Previews without writing files, downloading, importing, or changing the environment' {
        & $Setup -WhatIf
        Test-Path (Join-Path $Fixture 'build') | Should -BeFalse
        Should -Invoke -ModuleName KMMPluginBuild Save-Module -Times 0 -Exactly
        Should -Invoke -ModuleName KMMPluginBuild Import-Module -Times 0 -Exactly -ParameterFilter { $Global }
        $env:PSModulePath | Should -BeExactly $OriginalModulePath
    }

    It 'Stops on a failed download before importing modules or altering the search path' {
        Mock -ModuleName KMMPluginBuild Save-Module { throw 'Synthetic download failure' }
        { & $Setup } | Should -Throw '*Synthetic download failure*'
        Should -Invoke -ModuleName KMMPluginBuild Import-Module -Times 0 -Exactly -ParameterFilter { $Global }
        $env:PSModulePath | Should -BeExactly $OriginalModulePath
    }

    It 'Rejects a cached manifest containing a different version' {
        Mock -ModuleName KMMPluginBuild Test-ModuleManifest { [pscustomobject]@{ Version = [version]'0.0' } }
        { & $Setup } | Should -Throw '*Module cache version mismatch*'
        Should -Invoke -ModuleName KMMPluginBuild Import-Module -Times 0 -Exactly -ParameterFilter { $Global }
    }

    It 'Restores the module search path if importing fails' {
        Mock -ModuleName KMMPluginBuild Import-Module { throw 'Synthetic import failure' } -ParameterFilter { $Global }
        { & $Setup } | Should -Throw '*Synthetic import failure*'
        $env:PSModulePath | Should -BeExactly $OriginalModulePath
    }
}
