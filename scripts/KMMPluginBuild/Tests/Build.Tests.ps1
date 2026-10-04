#Requires -Version 7.0
#Requires -PSEdition Core
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester and Invoke-Build share fixture variables between script blocks.'
)]
param()

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module InvokeBuild -ErrorAction Stop
    $BuildEngine = (Get-Command Invoke-Build).Definition
    $BuildSource = Join-Path ([IO.Path]::GetFullPath('../../..', $PSScriptRoot)) 'build.ps1'
    $RealGetCommand = Get-Command Get-Command
}

Describe 'CMake plugin selection' {
    It 'Reconfiguration limits tests and staging to selected plugins' {
        $CMake = (Get-Command cmake -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        $CTest = (Get-Command ctest -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        $Fixture = Join-Path $TestDrive 'cmake-selection'
        $Binary = Join-Path $Fixture 'build'
        New-Item -ItemType Directory -Path $Fixture | Out-Null
        $RootCMake = Get-Content (Join-Path ([IO.Path]::GetFullPath('../../..', $PSScriptRoot)) 'CMakeLists.txt') -Raw
        $SelectionCode = $RootCMake.Substring($RootCMake.IndexOf('set(KMM_PLUGIN_SELECTION'))
        "cmake_minimum_required(VERSION 3.21)`nproject(SelectionFixture NONE)`ninclude(CTest)`n$SelectionCode" |
            Set-Content -LiteralPath (Join-Path $Fixture 'CMakeLists.txt')
        foreach ($Plugin in 'first-plugin', 'second-plugin') {
            $Directory = Join-Path $Fixture "plugins/$Plugin"
            New-Item -ItemType Directory -Path $Directory | Out-Null
            $Plugin | Set-Content -LiteralPath (Join-Path $Directory "$Plugin.txt")
            @'
get_filename_component(plugin_name "${CMAKE_CURRENT_SOURCE_DIR}" NAME)
install(FILES "${plugin_name}.txt" DESTINATION plugins)
add_test(NAME "${plugin_name}" COMMAND "${CMAKE_COMMAND}" -E true)
'@ | Set-Content -LiteralPath (Join-Path $Directory 'CMakeLists.txt')
        }
        & $CMake -S $Fixture -B $Binary -G Ninja '-DKMM_PLUGIN_SELECTION=all'
        $LASTEXITCODE | Should -Be 0
        $AllStage = Join-Path $Fixture 'stage-all'
        & $CMake --install $Binary --prefix $AllStage
        $LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath (Join-Path $AllStage 'plugins/first-plugin.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $AllStage 'plugins/second-plugin.txt') | Should -BeTrue
        & $CMake -S $Fixture -B $Binary '-DKMM_PLUGIN_SELECTION=first-plugin'
        $LASTEXITCODE | Should -Be 0
        $SingleStage = Join-Path $Fixture 'stage-one'
        & $CMake --install $Binary --prefix $SingleStage
        $LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath (Join-Path $SingleStage 'plugins/first-plugin.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $SingleStage 'plugins/second-plugin.txt') | Should -BeFalse
        $TestListing = (& $CTest --test-dir $Binary --show-only=json-v1 | Out-String) | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        @($TestListing.tests).Count | Should -Be 1
        $TestListing.tests[0].name | Should -BeExactly 'first-plugin'
    }
}

Describe 'Plugin build task graph' {
    BeforeEach {
        $Fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $Fixture 'scripts'),
            (Join-Path $Fixture 'plugins/first-plugin'), (Join-Path $Fixture 'plugins/second-plugin') | Out-Null
        $BuildFile = Join-Path $Fixture 'build.ps1'
        Copy-Item -LiteralPath $BuildSource -Destination $BuildFile
        $Module = Import-TestBuildModule -RepositoryRoot $Fixture
        $Reader = & $Module { Get-Command Read-KMMLocalEnvironment }
        Mock -ModuleName KMMPluginBuild Set-KMMAppVersion {}
        Mock -ModuleName KMMPluginBuild Install-KMMApplication {
            $Context.EnvironmentValues.KMYMONEY_SOURCE_DIR = Join-Path $Context.EnvironmentValues.CRAFT_ROOT 'source/kmymoney'
            $Context.EnvironmentValues.KMYMONEY_EXECUTABLE = Join-Path $Context.EnvironmentValues.CRAFT_ROOT 'bin/kmymoney'
        }
        Mock -ModuleName KMMPluginBuild Initialize-KMMPowerShell { 'setup' | Add-Content (Join-Path $Fixture 'module-setup.log') }
        foreach ($Plugin in 'first-plugin', 'second-plugin') {
            '# synthetic plugin' | Set-Content -LiteralPath (Join-Path $Fixture "plugins/$Plugin/CMakeLists.txt")
        }
        Mock -ModuleName KMMPluginBuild Enter-KMMCraftEnvironment {
            $Values = & $Reader -EnvFile $EnvFile
            foreach ($Name in $Values.Keys) { [Environment]::SetEnvironmentVariable($Name, $Values[$Name], 'Process') }
            $env:KMM_BUILD_TEST_TEMPORARY = 'created'
            $env:KMM_BUILD_TEST_EXISTING = 'changed'
            function global:craft { 'temporary-craft' }
            if ($env:KMM_BUILD_TEST_FAIL -eq 'setup') { throw 'Synthetic Craft setup failure' }
        }
        $Tool = Join-Path $Fixture 'native-tool.ps1'
        @'
ConvertTo-Json -InputObject @($args) -Compress | Add-Content -LiteralPath $env:KMM_BUILD_TEST_LOG
Set-Variable LASTEXITCODE -Value 0 -Scope 1
if ($args[0] -eq $env:KMM_BUILD_TEST_FAIL) { Set-Variable LASTEXITCODE -Value 23 -Scope 1 }
'@ | Set-Content -LiteralPath $Tool
        Mock -ModuleName KMMPluginBuild Get-Command { & $RealGetCommand -Name $Name }
        Mock -ModuleName KMMPluginBuild Get-Command {
            [pscustomobject]@{ Source = $Tool }
            [pscustomobject]@{ Source = 'unused-tool-later-on-PATH' }
        } -ParameterFilter { $Name -in 'cmake', 'ctest' }
        $SavedEnvironment = [Environment]::GetEnvironmentVariables()
        # Synthetic plugins must not inherit a real pipeline's plugin selection.
        $env:KMM_PLUGINS = $null
        $env:CI = 'false'
        $env:TF_BUILD = 'false'
        $env:GITHUB_ACTIONS = 'false'
        '# Empty selected configuration' | Set-Content (Join-Path $Fixture 'alternate.env.ini')
        $SavedCraft = Get-Item Function:craft -ErrorAction SilentlyContinue
        $SavedLocation = $PWD.Path
        $env:KMM_BUILD_TEST_LOG = Join-Path $Fixture 'calls.jsonl'
        $env:KMM_BUILD_TEST_FAIL = $null
        $env:KMM_BUILD_TEST_TEMPORARY = $null
        $env:KMM_BUILD_TEST_EXISTING = 'original'
        function global:craft { 'original-craft' }
    }

    AfterEach {
        foreach ($Name in @([Environment]::GetEnvironmentVariables().Keys)) {
            if (-not $SavedEnvironment.Contains($Name)) { Remove-Item -LiteralPath "Env:$Name" }
        }
        foreach ($Name in $SavedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($Name, $SavedEnvironment[$Name], 'Process') }
        if ($SavedCraft) { Set-Item Function:global:craft $SavedCraft.ScriptBlock }
        else { Remove-Item Function:global:craft -ErrorAction SilentlyContinue }
        Set-Location -LiteralPath $SavedLocation
    }

    It 'BuildCI configures and builds once before testing and staging one plugin' {
        & $BuildEngine -File $BuildFile -Task BuildCI -Plugins first-plugin
        $Calls = @(Get-Content -LiteralPath $env:KMM_BUILD_TEST_LOG | ForEach-Object { ,(ConvertFrom-Json $_) })
        $Calls.Count | Should -Be 4
        $Calls[0] | Should -Contain '-DKMM_PLUGIN_SELECTION=first-plugin'
        $Calls[0] | Should -Contain '-DBUILD_FIRST_PLUGIN=ON'
        $Calls[1][0] | Should -Be '--build'
        $Calls[2][0] | Should -Be '--test-dir'
        $Calls[2] | Should -Contain '--no-tests=error'
        $Calls[3][0] | Should -Be '--install'
        $Calls[3][-1] | Should -BeLike "$Fixture*stage*craft-*"
        $env:KMM_BUILD_TEST_EXISTING | Should -BeExactly 'original'
        (Test-Path -LiteralPath Env:KMM_BUILD_TEST_TEMPORARY) | Should -BeFalse
        (& (Get-Item Function:craft).ScriptBlock) | Should -BeExactly 'original-craft'
        $PWD.Path | Should -Be $SavedLocation
    }

    It 'Selects <Selection> and builds without testing or staging by default' -ForEach @(
        @{ Selection = 'several'; Chosen = @('second-plugin', 'first-plugin', 'first-plugin') }
        @{ Selection = 'all'; Chosen = @('all') }
    ) {
        & $BuildEngine -File $BuildFile -Plugins $Chosen
        $Calls = @(Get-Content -LiteralPath $env:KMM_BUILD_TEST_LOG | ForEach-Object { ,(ConvertFrom-Json $_) })
        $Calls.Count | Should -Be 2
        $Calls[0] | Should -Contain '-DKMM_PLUGIN_SELECTION=first-plugin;second-plugin'
        $Calls[1][0] | Should -Be '--build'
    }

    It 'Defaults to all outside CI even when KMM_PLUGINS is configured' {
        'KMM_PLUGINS=second-plugin' | Set-Content (Join-Path $Fixture 'env.ini')
        & $BuildEngine -File $BuildFile -Task Build
        $Calls = @(Get-Content $env:KMM_BUILD_TEST_LOG | ForEach-Object { ,(ConvertFrom-Json $_) })
        $Calls[0] | Should -Contain '-DKMM_PLUGIN_SELECTION=first-plugin;second-plugin'
    }

    It 'Overrides explicit Plugins during initialization for <Flag> CI' -ForEach @(
        @{ Flag = 'CI' }, @{ Flag = 'TF_BUILD' }, @{ Flag = 'GITHUB_ACTIONS' }
    ) {
        [Environment]::SetEnvironmentVariable($Flag, 'true', 'Process')
        'KMM_PLUGINS=second-plugin' | Set-Content (Join-Path $Fixture 'env.ini')
        & $BuildEngine -File $BuildFile -Task Build -Plugins first-plugin
        $Calls = @(Get-Content $env:KMM_BUILD_TEST_LOG | ForEach-Object { ,(ConvertFrom-Json $_) })
        $Calls[0] | Should -Contain '-DKMM_PLUGIN_SELECTION=second-plugin'
    }

    It 'Uses the runner plugin override and restores configured variables after CI' {
        $env:CI = 'true'
        $env:KMM_PLUGINS = 'second-plugin'
        $env:KMM_APP_VERSION = 'caller-value'
        "KMM_PLUGINS=first-plugin`nKMM_APP_VERSION=master" | Set-Content (Join-Path $Fixture 'env.ini')
        Mock Initialize-KMMCIEnvironment {
            $env:KMM_APP_VERSION | Should -BeExactly 'master'
        }
        & $BuildEngine -File $BuildFile -Task PrepareCI -Plugins first-plugin
        Should -Invoke Initialize-KMMCIEnvironment -Times 1 -Exactly -ParameterFilter {
            $Context.Plugins.Count -eq 1 -and $Context.Plugins[0] -eq 'second-plugin' -and $Context.KMMAppVersion -eq 'master'
        }
        $env:KMM_APP_VERSION | Should -BeExactly 'caller-value'
    }

    It 'Uses the version from the selected INI when no command-line version is supplied' {
        'KMM_APP_VERSION=5.2' | Set-Content (Join-Path $Fixture 'alternate.env.ini')
        & $BuildEngine -File $BuildFile -Task Build -EnvFile alternate.env.ini
        Should -Invoke -ModuleName KMMPluginBuild Set-KMMAppVersion -Times 1 -Exactly -ParameterFilter {
            $KMMAppVersion -ceq '5.2'
        }
    }

    It 'Applies the explicit Craft version before plugin configuration' {
        'KMM_APP_VERSION=5.2' | Set-Content (Join-Path $Fixture 'env.ini')
        Mock -ModuleName KMMPluginBuild Set-KMMAppVersion {
            Test-Path -LiteralPath $env:KMM_BUILD_TEST_LOG | Should -BeFalse
        }
        & $BuildEngine -File $BuildFile -Task Build -KMMAppVersion master
        Should -Invoke -ModuleName KMMPluginBuild Set-KMMAppVersion -Times 1 -Exactly -ParameterFilter {
            $KMMAppVersion -ceq 'master'
        }
    }

    It 'Runs the shared build test and stage graph after CI preparation and checks' {
        Mock Initialize-KMMCIEnvironment {}
        Mock Enter-KMMCraftEnvironment {}
        Mock Invoke-KMMCheck {}
        & $BuildEngine -File $BuildFile -Task CI -Plugins first-plugin
        Should -Invoke Initialize-KMMCIEnvironment -Times 1 -Exactly
        Should -Invoke Invoke-KMMCheck -Times 1 -Exactly
        $Calls = @(Get-Content $env:KMM_BUILD_TEST_LOG | ForEach-Object { ,(ConvertFrom-Json $_) })
        $Calls.Count | Should -Be 4
        $Calls[0][0] | Should -Be '--preset'
        $Calls[2][0] | Should -Be '--test-dir'
        $Calls[3][0] | Should -Be '--install'
    }

    It 'Cleans through CMake before building and staging' {
        & $BuildEngine -File $BuildFile -Task Clean, Stage -Plugins first-plugin
        $Calls = @(Get-Content -LiteralPath $env:KMM_BUILD_TEST_LOG | ForEach-Object { ,(ConvertFrom-Json $_) })
        $Calls.Count | Should -Be 4
        $Calls[1][-2..-1] | Should -Be @('--target', 'clean')
        $Calls[2][0] | Should -Be '--build'
        $Calls[3][0] | Should -Be '--install'
    }

    It 'Stops on <Step> failure and restores the environment' -ForEach @(
        @{ Step = '--preset'; Count = 1 }
        @{ Step = '--build'; Count = 2 }
        @{ Step = '--test-dir'; Count = 3 }
        @{ Step = '--install'; Count = 4 }
    ) {
        $env:KMM_BUILD_TEST_FAIL = $Step
        { & $BuildEngine -File $BuildFile -Task BuildCI -Plugins all } | Should -Throw '*exit code 23*'
        @(Get-Content -LiteralPath $env:KMM_BUILD_TEST_LOG).Count | Should -Be $Count
        $env:KMM_BUILD_TEST_EXISTING | Should -BeExactly 'original'
        (Test-Path -LiteralPath Env:KMM_BUILD_TEST_TEMPORARY) | Should -BeFalse
        (& (Get-Item Function:craft).ScriptBlock) | Should -BeExactly 'original-craft'
        $PWD.Path | Should -Be $SavedLocation
    }

    It 'Restores environment and function after setup failure' {
        $env:KMM_BUILD_TEST_FAIL = 'setup'
        { & $BuildEngine -File $BuildFile -Task Build } | Should -Throw '*Synthetic Craft setup failure*'
        $env:KMM_BUILD_TEST_EXISTING | Should -BeExactly 'original'
        (Test-Path -LiteralPath Env:KMM_BUILD_TEST_TEMPORARY) | Should -BeFalse
        (& (Get-Item Function:craft).ScriptBlock) | Should -BeExactly 'original-craft'
    }

    It 'Rejects unknown plugins and mixed all selection before setup' {
        { & $BuildEngine -File $BuildFile -Task Build -Plugins missing } | Should -Throw '*Unknown plugin*'
        { & $BuildEngine -File $BuildFile -Task Build -Plugins all, first-plugin } | Should -Throw "*Use 'all' alone*"
        Test-Path -LiteralPath $env:KMM_BUILD_TEST_LOG | Should -BeFalse
        $env:KMM_BUILD_TEST_EXISTING | Should -BeExactly 'original'
    }

    It 'FirstRun installs KMyMoney and preserves explicit paths in the saved INI' {
        $env:KMM_BUILD_TEST_FAIL = 'setup'
        Mock -ModuleName KMMPluginBuild Read-Host {
            if ($Prompt -like 'CRAFT_PYTHON*') { return '-' }
            Join-Path $Fixture 'path with spaces # and = signs'
        }
        & $BuildEngine -File $BuildFile -Task FirstRun
        Get-Content (Join-Path $Fixture 'module-setup.log') | Should -BeExactly 'setup'
        $File = Join-Path $Fixture 'env.ini'
        $Values = & $Reader -EnvFile $File
        $Values.Count | Should -Be 12
        $Values['CRAFT_ROOT'] | Should -BeExactly (Join-Path $Fixture 'path with spaces # and = signs')
        $Values.KMYMONEY_SOURCE_DIR | Should -BeExactly (Join-Path $Fixture 'path with spaces # and = signs')
        $Values.KMYMONEY_EXECUTABLE | Should -BeExactly (Join-Path $Fixture 'path with spaces # and = signs')
        $Values['CRAFT_PYTHON'] | Should -BeNullOrEmpty
        Should -Invoke -ModuleName KMMPluginBuild Read-Host -Times 4 -Exactly
        Should -Invoke -ModuleName KMMPluginBuild Install-KMMApplication -Times 1 -Exactly
        Test-Path -LiteralPath $env:KMM_BUILD_TEST_LOG | Should -BeFalse
        $env:KMM_BUILD_TEST_EXISTING | Should -BeExactly 'original'
        [IO.File]::ReadAllText($File).Contains("`r") | Should -BeFalse
    }

    It 'FirstRun accepts blank paths and discovers the application under the default Craft root' {
        Mock -ModuleName KMMPluginBuild Read-Host { '' }
        & $BuildEngine -File $BuildFile -Task FirstRun -KMMAppVersion master
        $Values = & $Reader -EnvFile (Join-Path $Fixture 'env.ini')
        $ExpectedRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'kdecraft-root'
        $Values.CRAFT_ROOT | Should -BeExactly $ExpectedRoot
        $Values.KMYMONEY_SOURCE_DIR | Should -BeExactly (Join-Path $ExpectedRoot 'source/kmymoney')
        $Values.KMYMONEY_EXECUTABLE | Should -BeExactly (Join-Path $ExpectedRoot 'bin/kmymoney')
        $Values.KMM_APP_VERSION | Should -BeExactly 'master'
    }

    It 'FirstRun saves the resolved Craft default when the input version was blank' {
        Mock -ModuleName KMMPluginBuild Read-Host { '' }
        Mock -ModuleName KMMPluginBuild Install-KMMApplication {
            $Context.EnvironmentValues.KMM_APP_VERSION = '5.2'
            $Context.KMMAppVersion = '5.2'
        }
        & $BuildEngine -File $BuildFile -Task FirstRun
        $Values = & $Reader -EnvFile (Join-Path $Fixture 'env.ini')
        $Values.KMM_APP_VERSION | Should -BeExactly '5.2'
    }

    It 'Preserves the existing INI when Craft installation fails' {
        $File = Join-Path $Fixture 'env.ini'
        'KMM_APP_VERSION=master' | Set-Content $File
        $Original = [IO.File]::ReadAllText($File)
        Mock -ModuleName KMMPluginBuild Read-Host { '' }
        Mock -ModuleName KMMPluginBuild Install-KMMApplication { throw 'Synthetic installation failure' }
        { & $BuildEngine -File $BuildFile -Task FirstRun } | Should -Throw '*Synthetic installation failure*'
        [IO.File]::ReadAllText($File) | Should -BeExactly $Original
    }

    It 'FirstRun supports an alternate file followed by Build in the same invocation' {
        "KMM_PLUGINS=second-plugin`nCMAKE_BUILD_PARALLEL_LEVEL=2" |
            Set-Content (Join-Path $Fixture 'alternate.env.ini')
        Mock -ModuleName KMMPluginBuild Read-Host {
            if ($Prompt -like 'CRAFT_PYTHON*') { return '-' }
            Join-Path $Fixture 'chosen-path'
        }
        & $BuildEngine -File $BuildFile -Task FirstRun, Build -Tasks FirstRun,Build -EnvFile alternate.env.ini -Plugins first-plugin
        Test-Path -LiteralPath (Join-Path $Fixture 'alternate.env.ini') | Should -BeTrue
        $Settings = & $Reader -EnvFile (Join-Path $Fixture 'alternate.env.ini')
        $Settings.KMM_PLUGINS | Should -BeExactly 'second-plugin'
        $Settings.CMAKE_BUILD_PARALLEL_LEVEL | Should -BeExactly '2'
        Test-Path -LiteralPath (Join-Path $Fixture 'env.ini') | Should -BeFalse
        @(Get-Content -LiteralPath $env:KMM_BUILD_TEST_LOG).Count | Should -Be 2
        [string]$env:CRAFT_ROOT | Should -BeExactly ([string]$SavedEnvironment['CRAFT_ROOT'])
    }

    It 'Routes Run arguments and the selected INI through the module' {
        Mock Invoke-KMMDevelopment {}
        & $BuildEngine -File $BuildFile -Task Run -Tasks Run -EnvFile alternate.env.ini -KMMAppArguments @('--', 'synthetic file.kmy')
        Should -Invoke Invoke-KMMDevelopment -Times 1 -Exactly -ParameterFilter {
            $Action -eq 'Run' -and $EnvFile -eq 'alternate.env.ini' -and
            $KMMAppArguments.Count -eq 2 -and $KMMAppArguments[1] -eq 'synthetic file.kmy'
        }
    }

    It 'Routes KMMAppFile through the Run task' {
        Mock Invoke-KMMDevelopment {}
        & $BuildEngine -File $BuildFile -Task Run -Tasks Run -KMMAppFile 'synthetic file.kmy'
        Should -Invoke Invoke-KMMDevelopment -Times 1 -Exactly -ParameterFilter {
            $Action -eq 'Run' -and $KMMAppFile -eq 'synthetic file.kmy'
        }
    }

    It 'Defaults Run to the sample document' {
        Mock Invoke-KMMDevelopment {}
        & $BuildEngine -File $BuildFile -Task Run -Tasks Run
        Should -Invoke Invoke-KMMDevelopment -Times 1 -Exactly -ParameterFilter {
            $Action -eq 'Run' -and $KMMAppFile -eq 'data/sample-data.xml'
        }
    }

    It 'Allows Run without an explicit document' {
        Mock Invoke-KMMDevelopment {}
        & $BuildEngine -File $BuildFile -Task Run -Tasks Run -KMMAppFile ''
        Should -Invoke Invoke-KMMDevelopment -Times 1 -Exactly -ParameterFilter {
            $Action -eq 'Run' -and $KMMAppFile -eq ''
        }
    }

    It 'Routes workspace generation options through its task' {
        Mock Open-KMMWorkspace {}
        & $BuildEngine -File $BuildFile -Task OpenWorkspace -Tasks OpenWorkspace -GenerateOnly -EnvFile alternate.env.ini
        Should -Invoke Open-KMMWorkspace -Times 1 -Exactly -ParameterFilter {
            $GenerateOnly -and $EnvFile -eq 'alternate.env.ini'
        }
    }

    It 'Updates each selected plugin through the translation task' {
        Mock Update-KMMTranslation {}
        & $BuildEngine -File $BuildFile -Task UpdateTranslations -Plugins all -EnvFile alternate.env.ini
        Should -Invoke Update-KMMTranslation -Times 2 -Exactly
        Should -Invoke Update-KMMTranslation -Times 1 -Exactly -ParameterFilter {
            $Plugin -eq 'second-plugin' -and $EnvFile -eq 'alternate.env.ini'
        }
    }

    It 'Runs Check without configuring or compiling plugins' {
        Mock Enter-KMMCraftEnvironment {}
        Mock Invoke-KMMCheck {}
        & $BuildEngine -File $BuildFile -Task Check
        Should -Invoke Invoke-KMMCheck -Times 1 -Exactly
        Test-Path -LiteralPath $env:KMM_BUILD_TEST_LOG | Should -BeFalse
        $env:KMM_BUILD_TEST_EXISTING | Should -BeExactly 'original'
    }

    It 'Forwards the Craft version and plugin selection to CI provisioning' {
        Mock Initialize-KMMCIEnvironment {}
        $env:KMM_BUILD_TEST_FAIL = 'setup'
        & $BuildEngine -File $BuildFile -Task PrepareCI -Plugins second-plugin -KMMAppVersion 'master'
        Should -Invoke Initialize-KMMCIEnvironment -Times 1 -Exactly -ParameterFilter {
            $Context.Plugins.Count -eq 1 -and $Context.Plugins[0] -eq 'second-plugin' -and $Context.KMMAppVersion -eq 'master'
        }
    }

    It 'Keeps successful EnterCraft changes available to the calling shell' {
        Mock Enter-KMMCraftEnvironment {
            $env:KMM_BUILD_TEST_TEMPORARY = 'created'
            function global:craft { 'temporary-craft' }
        }
        & $BuildEngine -File $BuildFile -Task EnterCraft
        $env:KMM_BUILD_TEST_TEMPORARY | Should -BeExactly 'created'
        (& (Get-Item Function:craft).ScriptBlock) | Should -BeExactly 'temporary-craft'
    }

    It 'Restores the environment if EnterCraft fails' {
        Mock Enter-KMMCraftEnvironment {
            $env:KMM_BUILD_TEST_TEMPORARY = 'created'
            throw 'Synthetic Craft setup failure'
        }
        $env:KMM_BUILD_TEST_FAIL = 'setup'
        { & $BuildEngine -File $BuildFile -Task EnterCraft } | Should -Throw '*Synthetic Craft setup failure*'
        (Test-Path -LiteralPath Env:KMM_BUILD_TEST_TEMPORARY) | Should -BeFalse
        $env:KMM_BUILD_TEST_EXISTING | Should -BeExactly 'original'
    }
}
