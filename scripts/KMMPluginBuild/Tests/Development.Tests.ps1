#Requires -Version 7.0
#Requires -PSEdition Core
# Run through ./build.ps1 -Tasks Check
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester shares fixture variables between BeforeAll, BeforeEach, It, and AfterEach script blocks.'
)]
param()

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $Module = Import-TestBuildModule
    $ScriptDirectory = Split-Path -Parent $PSScriptRoot
    $RepositoryRoot = [IO.Path]::GetFullPath('../../..', $PSScriptRoot)
    $PowerShellPath = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
}

Describe 'Development script contracts' {
    It 'Documents <Name> through Get-Help' -ForEach @(
        @{ Name = 'Enter-KMMCraftEnvironment' }
        @{ Name = 'Invoke-KMMDevelopment' }
        @{ Name = 'Open-KMMWorkspace' }
        @{ Name = 'Update-KMMTranslation' }
        @{ Name = 'Initialize-KMMCIEnvironment' }
        @{ Name = 'Initialize-KMMPowerShell' }
    ) {
        $Help = Get-Help $Name -Full
        $Help.Synopsis | Should -Not -Match ([regex]::Escape($Name) + '\s*\[')
        $Help.Description.Text | Should -Not -BeNullOrEmpty
        @($Help.Examples.Example).Count | Should -BeGreaterThan 0
    }

    It 'Previews <Name> without requiring Craft or creating output' -ForEach @(
        @{ Name = 'Enter-KMMCraftEnvironment'; Arguments = @{} }
        @{ Name = 'Invoke-KMMDevelopment'; Arguments = @{ Action = 'Install' } }
        @{ Name = 'Open-KMMWorkspace'; Arguments = @{} }
        @{ Name = 'Update-KMMTranslation'; Arguments = @{ Plugin = 'draft-transactions' } }
    ) {
        $Command = Get-Command $Name
        { & $Command @Arguments -WhatIf } | Should -Not -Throw
    }

    It 'Rejects a target for Run before initializing Craft' {
        { Invoke-KMMDevelopment -Action Run -Target unwanted } |
            Should -Throw '*Target*Build*'
    }

    It 'Rejects host arguments for Build before checking the project' {
        { Invoke-KMMDevelopment -Action Build -KMMAppArguments '--help' } |
            Should -Throw '*KMMAppArguments*Run*'
    }

    It 'Stops before setup when the plugin project is missing' {
        $MissingProjectScripts = Join-Path $TestDrive 'missing-project/scripts'
        New-Item -ItemType Directory -Path $MissingProjectScripts | Out-Null
        $Module = Import-TestBuildModule -RepositoryRoot (Split-Path -Parent $MissingProjectScripts)
        { Invoke-KMMDevelopment -Action Build } |
            Should -Throw '*No CMakeLists.txt*'
    }
}

Describe 'Craft environment and workspace integration with isolated native stubs' {
    BeforeEach {
        $SavedEnvironment = [Environment]::GetEnvironmentVariables()
        $SavedCraft = Get-Item Function:craft -ErrorAction SilentlyContinue
        $SavedLocation = $PWD.Path
        $FixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $FixtureScripts = Join-Path $FixtureRoot 'scripts'
        $CraftRoot = Join-Path $FixtureRoot 'Craft prefix with spaces'
        $SourceRoot = Join-Path $FixtureRoot 'host source'
        New-Item -ItemType Directory -Path $FixtureScripts, (Join-Path $CraftRoot 'craft/bin'), $SourceRoot | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'kmymoney-plugin.code-workspace') -Destination $FixtureRoot
        $Module = Import-TestBuildModule -RepositoryRoot $FixtureRoot
        Set-Content -LiteralPath (Join-Path $CraftRoot 'craft/bin/CraftSetupHelper.py') -Value '# stub'
        $PythonStub = Join-Path $FixtureRoot 'python-stub.ps1'
        @'
if ($args[0] -eq '-c') { $global:LASTEXITCODE = 0; return }
$global:LASTEXITCODE = 0
if ($env:DEVELOPMENT_TEST_FAILURE -eq 'exit') { $global:LASTEXITCODE = 7; return }
if ($env:DEVELOPMENT_TEST_FAILURE -eq 'json') { '{'; return }
@{
    KDEROOT = $env:CRAFT_ROOT
    PATH = $env:PATH
    QT_PLUGIN_PATH = [string]$env:QT_PLUGIN_PATH
    XDG_DATA_DIRS = [string]$env:XDG_DATA_DIRS
} | ConvertTo-Json -Compress
'@ | Set-Content -LiteralPath $PythonStub
        $env:CRAFT_ROOT = $CraftRoot
        $env:KMYMONEY_SOURCE_DIR = $SourceRoot
        $env:KMYMONEY_EXECUTABLE = Join-Path $FixtureRoot 'host.ps1'
        $env:CRAFT_PYTHON = $PythonStub
        $env:KDEROOT = $null
        $env:DEVELOPMENT_TEST_FAILURE = $null
        Mock -ModuleName KMMPluginBuild Get-Command {
            [pscustomobject]@{ Source = $env:CRAFT_PYTHON }
        } -ParameterFilter { $Name -eq $env:CRAFT_PYTHON }
    }

    AfterEach {
        foreach ($Key in @([Environment]::GetEnvironmentVariables().Keys)) {
            if (-not $SavedEnvironment.Contains($Key)) {
                Remove-Item -LiteralPath "Env:$Key"
            }
        }
        foreach ($Key in $SavedEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($Key, $SavedEnvironment[$Key], 'Process')
        }
        if ($SavedCraft) {
            Set-Item Function:global:craft $SavedCraft.ScriptBlock
        } else {
            Remove-Item Function:craft -ErrorAction SilentlyContinue
        }
        Set-Location -LiteralPath $SavedLocation
    }

    It 'Initializes staging once and preserves caller scope and working directory' {
        $OriginalPreference = $ErrorActionPreference
        Enter-KMMCraftEnvironment
        $FirstPath = $env:QT_PLUGIN_PATH
        $DataPaths = $env:XDG_DATA_DIRS.Split([IO.Path]::PathSeparator)
        $DataPaths | Should -Contain (Join-Path $env:KMYMONEY_STAGE_DIR 'share')
        if ($IsWindows) {
            $DataPaths | Should -Contain (Join-Path $env:KMYMONEY_STAGE_DIR 'bin/data')
        }
        Enter-KMMCraftEnvironment
        $ExpectedPreset = if ($IsWindows) { 'craft-windows' } elseif ($IsMacOS) { 'craft-macos' } else { 'craft-linux' }
        $env:KMYMONEY_PRESET | Should -BeExactly $ExpectedPreset
        $env:KMYMONEY_STAGE_DIR | Should -Be (Join-Path $FixtureRoot "stage/$ExpectedPreset")
        $env:QT_PLUGIN_PATH | Should -BeExactly $FirstPath
        ($FirstPath -split [regex]::Escape([string][IO.Path]::PathSeparator))[0] |
            Should -Be (Join-Path $env:KMYMONEY_STAGE_DIR 'lib/plugins')
        $ErrorActionPreference | Should -Be $OriginalPreference
        $PWD.Path | Should -Be $SavedLocation
    }

    It 'Accepts the same Craft root with a trailing separator on <Side>' -ForEach @(
        @{ Side = 'configured' }, @{ Side = 'active' }
    ) {
        $env:KDEROOT = $CraftRoot
        if ($Side -eq 'configured') { $env:CRAFT_ROOT = $CraftRoot + [IO.Path]::DirectorySeparatorChar }
        else { $env:KDEROOT = $CraftRoot + [IO.Path]::DirectorySeparatorChar }
        { Enter-KMMCraftEnvironment } | Should -Not -Throw
        { Enter-KMMCraftEnvironment } | Should -Not -Throw
        $env:KDEROOT.TrimEnd('/','\') | Should -BeExactly $CraftRoot.TrimEnd('/','\')
    }

    It 'Still rejects a genuinely different active Craft installation' {
        $OtherRoot = Join-Path $FixtureRoot 'other Craft'
        New-Item -ItemType Directory -Path $OtherRoot | Out-Null
        $env:KDEROOT = $OtherRoot
        { Enter-KMMCraftEnvironment } | Should -Throw '*different Craft installation*requested*'
        $env:KDEROOT | Should -BeExactly $OtherRoot
    }

    It 'Restores the environment when Craft fails with <Failure>' -ForEach @(
        @{ Failure = 'exit' }
        @{ Failure = 'json' }
    ) {
        $env:DEVELOPMENT_TEST_FAILURE = $Failure
        $Before = [Environment]::GetEnvironmentVariables()
        { Enter-KMMCraftEnvironment } | Should -Throw
        $After = [Environment]::GetEnvironmentVariables()
        $After.Count | Should -Be $Before.Count
        foreach ($Key in $Before.Keys) {
            $After[$Key] | Should -BeExactly $Before[$Key]
        }
    }

    It 'Loads alternate file values for workspace generation instead of existing environment values' {
        $AlternateSource = Join-Path $FixtureRoot 'alternate source'
        New-Item -ItemType Directory -Path $AlternateSource | Out-Null
        "[Environment]`nKMYMONEY_SOURCE_DIR=$AlternateSource" |
            Set-Content -LiteralPath (Join-Path $FixtureRoot 'alternate.env.ini')
        $WorkspacePath = Open-KMMWorkspace -GenerateOnly -EnvFile alternate.env.ini
        $Workspace = Get-Content -LiteralPath $WorkspacePath -Raw | ConvertFrom-Json
        $Workspace.folders[1].path | Should -BeExactly $AlternateSource
        $env:KMYMONEY_SOURCE_DIR | Should -BeExactly $AlternateSource
    }

    It 'Restores original values when setup fails after loading an INI override' {
        $AlternateSource = Join-Path $FixtureRoot 'alternate source'
        New-Item -ItemType Directory -Path $AlternateSource | Out-Null
        "KMYMONEY_SOURCE_DIR=$AlternateSource" | Set-Content -LiteralPath (Join-Path $FixtureRoot 'env.ini')
        $env:DEVELOPMENT_TEST_FAILURE = 'exit'
        { Enter-KMMCraftEnvironment } | Should -Throw '*exit code 7*'
        $env:KMYMONEY_SOURCE_DIR | Should -BeExactly $SourceRoot
    }

    It 'Forwards the selected INI through development build automation' {
        '# fixture' | Set-Content -LiteralPath (Join-Path $FixtureRoot 'CMakeLists.txt')
        { Invoke-KMMDevelopment -Action Configure -EnvFile missing.env.ini } |
            Should -Throw '*Environment file does not exist*'
        $env:KMYMONEY_SOURCE_DIR | Should -BeExactly $SourceRoot
    }

    It 'Generates a local workspace with literal paths and preserves the template' {
        $TemplatePath = Join-Path $FixtureRoot 'kmymoney-plugin.code-workspace'
        $OriginalTemplate = Get-Content -LiteralPath $TemplatePath -Raw
        $Result = Open-KMMWorkspace -GenerateOnly
        $Result | Should -Be (Join-Path $FixtureRoot 'kmymoney-plugin.local.code-workspace')
        $Workspace = Get-Content -LiteralPath $Result -Raw | ConvertFrom-Json
        $Workspace.folders[1].path | Should -BeExactly $SourceRoot
        $Workspace.folders[2].path | Should -BeExactly $CraftRoot
        $Workspace.launch.configurations.Count | Should -Be 3
        (Get-Content -LiteralPath $TemplatePath -Raw) | Should -BeExactly $OriginalTemplate
    }

    It 'Forwards host arguments with spaces and reports native failure' {
        @'
$args | ConvertTo-Json -Compress | Set-Content -LiteralPath $env:DEVELOPMENT_TEST_ARGUMENTS
$global:LASTEXITCODE = 19
'@ | Set-Content -LiteralPath $env:KMYMONEY_EXECUTABLE
        $env:DEVELOPMENT_TEST_ARGUMENTS = Join-Path $FixtureRoot 'arguments.json'
        {
            Invoke-KMMDevelopment -Action Run -KMMAppArguments @('--', 'a file.kmy')
        } | Should -Throw '*exit code 19*'
        $RecordedArguments = Get-Content -LiteralPath $env:DEVELOPMENT_TEST_ARGUMENTS -Raw | ConvertFrom-Json
        $RecordedArguments[0] | Should -BeExactly '--'
        $RecordedArguments[1] | Should -BeExactly 'a file.kmy'
        $PWD.Path | Should -Be $SavedLocation
    }

    It 'Forwards positional document argument <Document> unchanged' -ForEach @(
        @{ Document = 'data/a file.kmy' }
        @{ Document = 'data/a file.xml' }
        @{ Document = 'sql://localhost/C:/data/a%20file.sqlite?driver=QSQLITE&mode=single' }
    ) {
        @'
ConvertTo-Json -InputObject @($args) -Compress | Set-Content -LiteralPath $env:DEVELOPMENT_TEST_ARGUMENTS
$PWD.Path | Set-Content -LiteralPath $env:DEVELOPMENT_TEST_LOCATION
$global:LASTEXITCODE = 0
'@ | Set-Content -LiteralPath $env:KMYMONEY_EXECUTABLE
        $env:DEVELOPMENT_TEST_ARGUMENTS = Join-Path $FixtureRoot 'arguments.json'
        $env:DEVELOPMENT_TEST_LOCATION = Join-Path $FixtureRoot 'location.txt'
        Invoke-KMMDevelopment -Action Run -KMMAppArguments @($Document)
        $Recorded = @(Get-Content -LiteralPath $env:DEVELOPMENT_TEST_ARGUMENTS -Raw | ConvertFrom-Json)
        $Recorded.Count | Should -Be 1
        $Recorded[0] | Should -BeExactly $Document
        (Get-Content -LiteralPath $env:DEVELOPMENT_TEST_LOCATION) | Should -BeExactly $FixtureRoot
    }

    It 'Opens <Extension> documents with literal paths and additional host options' -ForEach @(
        @{ Extension = '.kmy' }, @{ Extension = '.sqlite' }, @{ Extension = '.xml' }
    ) {
        @'
ConvertTo-Json -InputObject @($args) -Compress | Set-Content -LiteralPath $env:DEVELOPMENT_TEST_ARGUMENTS
$global:LASTEXITCODE = 0
'@ | Set-Content -LiteralPath $env:KMYMONEY_EXECUTABLE
        $env:DEVELOPMENT_TEST_ARGUMENTS = Join-Path $FixtureRoot 'arguments.json'
        $FileName = 'synthetic [test] # % ' + [char]0x021B + $Extension
        $FilePath = Join-Path $FixtureRoot $FileName
        Set-Content -LiteralPath $FilePath -Value 'synthetic stub input'
        Invoke-KMMDevelopment -Action Run -KMMAppFile $FileName -KMMAppArguments '--noplugins'
        $Recorded = @(Get-Content -LiteralPath $env:DEVELOPMENT_TEST_ARGUMENTS -Raw | ConvertFrom-Json)
        $Recorded.Count | Should -Be 3
        $Recorded[0] | Should -BeExactly '--noplugins'
        $Recorded[1] | Should -BeExactly '--'
        if ($Extension -eq '.sqlite') {
            $Recorded[2] | Should -Match '^sql://localhost/'
            $Recorded[2] | Should -Match '\?driver=QSQLITE&mode=single$'
            $EncodedPath = $Recorded[2].Substring('sql://localhost/'.Length).Split('?')[0]
            [Uri]::UnescapeDataString($EncodedPath) | Should -BeExactly $FilePath.Replace('\', '/')
            $Recorded[2] | Should -Not -Match '[ #]'
        } else {
            $Recorded[2] | Should -BeExactly $FilePath
        }
        $PWD.Path | Should -Be $SavedLocation
    }

    It 'Rejects missing documents before Craft initialization' {
        { Invoke-KMMDevelopment -Action Run -KMMAppFile 'missing.kmy' } | Should -Throw '*does not exist*'
        Should -Invoke -ModuleName KMMPluginBuild Get-Command -Times 0 -ParameterFilter { $Name -eq $env:CRAFT_PYTHON }
    }

    It 'Rejects unsupported documents and file arguments for Build' {
        { Invoke-KMMDevelopment -Action Run -KMMAppFile 'sample.txt' } | Should -Throw '*must be a .kmy*'
        { Invoke-KMMDevelopment -Action Build -KMMAppFile 'sample.kmy' } | Should -Throw '*KMMAppFile*Run*'
    }

    It 'Previews workspace generation without initializing Craft or writing a file' {
        $OriginalRoot = $env:craftRoot
        Open-KMMWorkspace -WhatIf
        $env:craftRoot | Should -BeExactly $OriginalRoot
        Test-Path (Join-Path $FixtureRoot 'kmymoney-plugin.local.code-workspace') | Should -BeFalse
        Should -Invoke -ModuleName KMMPluginBuild Get-Command -Times 0 -ParameterFilter { $Name -eq $env:CRAFT_PYTHON }
    }

    It 'Preserves native error preferences while reporting an actual executable failure' {
        $PSNativeCommandUseErrorActionPreference = $true
        $env:KMYMONEY_EXECUTABLE = $PowerShellPath
        {
            Invoke-KMMDevelopment -Action Run -KMMAppArguments @('-NoProfile', '-Command', 'exit 23')
        } | Should -Throw '*exit code 23*'
        $PSNativeCommandUseErrorActionPreference | Should -BeTrue
    }

    Context 'CMake sequencing' {
        BeforeEach {
            Set-Content -LiteralPath (Join-Path $FixtureRoot 'CMakeLists.txt') -Value '# fixture only'
            $env:DEVELOPMENT_TEST_CMAKE = Join-Path $FixtureRoot 'cmake-stub.ps1'
            $env:DEVELOPMENT_TEST_COMMANDS = Join-Path $FixtureRoot 'commands.jsonl'
            $env:DEVELOPMENT_TEST_FAIL_STEP = $null
            @'
ConvertTo-Json -InputObject @($args) -Compress | Add-Content -LiteralPath $env:DEVELOPMENT_TEST_COMMANDS
$global:LASTEXITCODE = if ($args[0] -eq $env:DEVELOPMENT_TEST_FAIL_STEP) { 17 } else { 0 }
'@ | Set-Content -LiteralPath $env:DEVELOPMENT_TEST_CMAKE
            Mock -ModuleName KMMPluginBuild Get-Command {
                [pscustomobject]@{ Source = $env:DEVELOPMENT_TEST_CMAKE }
            } -ParameterFilter { $Name -eq 'cmake' }
        }

        It 'Configures and builds a named target without installing' {
            Invoke-KMMDevelopment -Action Build -Target 'plugin-with-dashes'
            $Commands = @(Get-Content -LiteralPath $env:DEVELOPMENT_TEST_COMMANDS | ForEach-Object { ,(ConvertFrom-Json $_) })
            $Commands.Count | Should -Be 2
            $Commands[0] | Should -Be @('--preset', $env:KMYMONEY_PRESET, '-DKMM_PLUGIN_SELECTION=all')
            $Commands[1] | Should -Be @('--build', '--preset', $env:KMYMONEY_PRESET, '--target', 'plugin-with-dashes')
            $PWD.Path | Should -Be $SavedLocation
        }

        It 'Installs only after configuration and build succeed' {
            Invoke-KMMDevelopment -Action Install
            $Commands = @(Get-Content -LiteralPath $env:DEVELOPMENT_TEST_COMMANDS | ForEach-Object { ,(ConvertFrom-Json $_) })
            $Commands.Count | Should -Be 3
            $Commands[0][0] | Should -BeExactly '--preset'
            $Commands[1][0] | Should -BeExactly '--build'
            $Commands[2] | Should -Be @('--install', "build/$env:KMYMONEY_PRESET")
        }

        It 'Stops installation when <Step> fails' -ForEach @(
            @{ Step = '--preset'; CommandCount = 1 }
            @{ Step = '--build'; CommandCount = 2 }
        ) {
            $env:DEVELOPMENT_TEST_FAIL_STEP = $Step
            { Invoke-KMMDevelopment -Action Install } | Should -Throw '*exit code 17*'
            @(Get-Content -LiteralPath $env:DEVELOPMENT_TEST_COMMANDS).Count | Should -Be $CommandCount
            $PWD.Path | Should -Be $SavedLocation
        }
    }
}
