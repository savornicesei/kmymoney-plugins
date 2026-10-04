#Requires -Version 7.0
#Requires -PSEdition Core
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester shares setup variables with test and mock blocks.')]
param()

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $Module = Import-TestBuildModule
}

Describe 'Cross-platform Craft CI provisioning' {
    BeforeEach {
        $SavedEnvironment = [Environment]::GetEnvironmentVariables()
        $Fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $Prefix = Join-Path $Fixture 'craft prefix'
        $HostSource = Join-Path $Fixture 'host source'
        $HostBuild = Join-Path $Fixture 'host build'
        New-Item -ItemType Directory -Path (Join-Path $Prefix 'craft/bin'), $HostSource, $HostBuild | Out-Null
        '# existing Craft' | Set-Content (Join-Path $Prefix 'craft/bin/craft.py')
        $Values = Get-KMMBuildEnvironment
        $Values.CRAFT_ROOT = $Prefix
        $Values.CRAFT_PYTHON = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
        $Context = @{ Source = $Fixture; EnvironmentValues = $Values; KMMAppVersion = 'master' }
        $Calls = [Collections.Generic.List[object]]::new()
        Mock -ModuleName KMMPluginBuild Invoke-WebRequest {}
        Mock -ModuleName KMMPluginBuild Enter-KMMCraftEnvironment {}
        Mock -ModuleName KMMPluginBuild Set-KMMAppVersion {}
        Mock -ModuleName KMMPluginBuild Invoke-KMMNativeTool {
            if ($ArgumentList -contains '-c') { return }
            $Calls.Add(@($ArgumentList))
            if ($ArgumentList -contains 'sourceDir') { return $HostSource }
            if ($ArgumentList -contains 'buildDir') { return $HostBuild }
            if ($ArgumentList -contains 'buildTarget') { return '5.2' }
        }
        # Avoid needing a real bundle for the current platform's executable lookup.
        $ExecutableName = if ($IsWindows) { 'kmymoney.exe' } else { 'kmymoney' }
        New-Item -ItemType Directory -Path (Join-Path $Prefix 'bin') | Out-Null
        '' | Set-Content (Join-Path $Prefix "bin/$ExecutableName")
    }
    AfterEach {
        foreach ($Name in @([Environment]::GetEnvironmentVariables().Keys)) {
            if (-not $SavedEnvironment.Contains($Name)) { Remove-Item -LiteralPath "Env:$Name" }
        }
        foreach ($Name in $SavedEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($Name, $SavedEnvironment[$Name], 'Process')
        }
    }
    It 'Builds a source SDK with Craft and writes paths for the shared build graph' {
        Initialize-KMMCIEnvironment -Context $Context
        Should -Invoke -ModuleName KMMPluginBuild Invoke-WebRequest -Times 0 -Exactly
        Should -Invoke -ModuleName KMMPluginBuild Set-KMMAppVersion -Times 1 -Exactly -ParameterFilter {
            $KMMAppVersion -ceq 'master'
        }
        $Calls[0] | Should -Contain '--install-deps'
        $Calls[1] | Should -Contain '--no-cache'
        $Calls[1] | Should -Contain '--configure'
        $Calls[1] | Should -Contain '--qmerge'
        $Context.EnvironmentValues.KMYMONEY_SDK_SOURCE_DIR | Should -BeExactly $HostSource
        $Context.EnvironmentValues.KMYMONEY_BUILD_DIR | Should -BeExactly $HostBuild
        $env:KMYMONEY_SDK_SOURCE_DIR | Should -BeExactly $HostSource
        $env:KMYMONEY_BUILD_DIR | Should -BeExactly $HostBuild
        Test-Path -LiteralPath $Context.EnvFile | Should -BeTrue
        Should -Invoke -ModuleName KMMPluginBuild Enter-KMMCraftEnvironment -Times 2 -Exactly
    }
    It 'Records the resolved tag or branch when no version was requested' {
        $Context.KMMAppVersion = ''
        $Context.EnvironmentValues.KMM_APP_VERSION = ''
        Initialize-KMMCIEnvironment -Context $Context
        $Context.EnvironmentValues.KMM_APP_VERSION | Should -BeExactly '5.2'
        $Context.KMMAppVersion | Should -BeExactly '5.2'
        Get-Content $Context.EnvFile | Should -Contain 'KMM_APP_VERSION=5.2'
        Get-Content (Join-Path $Fixture 'build/ci/kmymoney-version.txt') | Should -BeExactly '5.2'
    }

    It 'Rejects an empty resolved target instead of publishing a blank version' {
        Mock -ModuleName KMMPluginBuild Invoke-KMMNativeTool { '' } -ParameterFilter { $ArgumentList -contains 'buildTarget' }
        { Initialize-KMMCIEnvironment -Context $Context } | Should -Throw '*single KMyMoney build target*'
        Test-Path (Join-Path $Fixture 'build/ci/kmymoney-version.txt') | Should -BeFalse
    }

    It 'Stops provisioning after a Craft failure without querying or publishing SDK paths' {
        Mock -ModuleName KMMPluginBuild Invoke-KMMNativeTool { throw 'Synthetic Craft build failure' } -ParameterFilter { $ArgumentList -notcontains '-c' }
        { Initialize-KMMCIEnvironment -Context $Context } | Should -Throw '*Synthetic Craft build failure*'
        Should -Invoke -ModuleName KMMPluginBuild Invoke-KMMNativeTool -Times 1 -Exactly -ParameterFilter { $ArgumentList -notcontains '-c' }
        Test-Path -LiteralPath (Join-Path $Fixture 'build/ci/kmymoney-version.txt') | Should -BeFalse
    }
}

Describe 'Craft KMyMoney version selection' {
    BeforeEach {
        $SavedRoot = $env:CRAFT_ROOT
        $SavedPython = $env:CRAFT_PYTHON
        $env:CRAFT_ROOT = Join-Path $TestDrive 'Craft prefix'
        $env:CRAFT_PYTHON = 'python-fixture'
        Mock -ModuleName KMMPluginBuild Invoke-KMMNativeTool {}
    }
    AfterEach {
        $env:CRAFT_ROOT = $SavedRoot
        $env:CRAFT_PYTHON = $SavedPython
    }
    It 'Passes <Version> literally as the Craft version setting' -ForEach @(
        @{ Version = '5.2' }, @{ Version = 'master' }, @{ Version = 'work/feature' }
    ) {
        Set-KMMAppVersion -KMMAppVersion $Version -Confirm:$false
        Should -Invoke -ModuleName KMMPluginBuild Invoke-KMMNativeTool -Times 1 -Exactly -ParameterFilter {
            $Executable -eq 'python-fixture' -and $ArgumentList.Count -eq 4 -and
            $ArgumentList[0] -eq (Join-Path $env:CRAFT_ROOT 'craft/bin/craft.py') -and
            $ArgumentList[1] -ceq '--set' -and $ArgumentList[2] -ceq "version=$Version" -and
            $ArgumentList[3] -ceq 'extragear/kmymoney'
        }
    }
    It 'Leaves Craft unchanged when no version is configured or when previewing' {
        Set-KMMAppVersion -KMMAppVersion ''
        Set-KMMAppVersion -KMMAppVersion master -WhatIf
        Should -Invoke -ModuleName KMMPluginBuild Invoke-KMMNativeTool -Times 0 -Exactly
    }
    It 'Propagates Craft failures and rejects multiline values before calling Craft' {
        { Set-KMMAppVersion -KMMAppVersion "master`nother" } | Should -Throw '*single literal*'
        Should -Invoke -ModuleName KMMPluginBuild Invoke-KMMNativeTool -Times 0 -Exactly
        Mock -ModuleName KMMPluginBuild Invoke-KMMNativeTool { throw 'Craft failed with exit code 17.' }
        { Set-KMMAppVersion -KMMAppVersion master -Confirm:$false } | Should -Throw '*exit code 17*'
    }
}
