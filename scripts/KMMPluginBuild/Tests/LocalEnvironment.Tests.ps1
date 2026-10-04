#Requires -Version 7.0
#Requires -PSEdition Core
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester shares fixture variables between setup and test blocks.'
)]
param()

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Literal local INI configuration' {
    BeforeEach {
        $Fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $Scripts = Join-Path $Fixture 'scripts'
        New-Item -ItemType Directory -Path $Scripts | Out-Null
        $Module = Import-TestBuildModule -RepositoryRoot $Fixture
        $Reader = & $Module { Get-Command Read-KMMLocalEnvironment }
        $DefaultFile = Join-Path $Fixture 'env.ini'
    }

    It 'Allows a missing default but rejects a missing explicit file' {
        (& $Reader).Count | Should -Be 0
        { & $Reader -EnvFile missing.env.ini } | Should -Throw '*Environment file does not exist*'
    }

    It 'Resolves all project defaults and overrides SDK and CI settings from the selected file' {
        @'
KMM_PLUGINS=first-plugin,second-plugin
KMYMONEY_BUILD_DIR=/tmp/host build
CMAKE_BUILD_PARALLEL_LEVEL=2
'@ | Set-Content -LiteralPath $DefaultFile
        $Values = Get-KMMBuildEnvironment
        $Values.Count | Should -Be 12
        $Values.KMM_PLUGINS | Should -BeExactly 'first-plugin,second-plugin'
        $Values.KMYMONEY_BUILD_DIR | Should -BeExactly '/tmp/host build'
        $Values.CMAKE_BUILD_PARALLEL_LEVEL | Should -BeExactly '2'
        $Values.KMM_APP_VERSION | Should -BeNullOrEmpty
        $Values.ContainsKey('KMYMONEY_SDK_SOURCE_DIR') | Should -BeTrue
    }

    It 'Preserves literal paths and never evaluates PowerShell expressions' {
        @'
# Full-line comments are allowed
[Environment]
CRAFT_ROOT="/tmp/Craft root # literal;=value"
KMYMONEY_SOURCE_DIR='/tmp/$(throw "must not run")'
; No variable expansion or inline comments
KMYMONEY_EXECUTABLE=/tmp/$HOME/kmymoney
CRAFT_PYTHON=
'@ | Set-Content -LiteralPath $DefaultFile
        $Before = [Environment]::GetEnvironmentVariables()
        $Values = & $Reader
        $Values.Count | Should -Be 4
        $Values.CRAFT_ROOT | Should -BeExactly '/tmp/Craft root # literal;=value'
        $Values.KMYMONEY_SOURCE_DIR | Should -BeExactly '/tmp/$(throw "must not run")'
        $Values.KMYMONEY_EXECUTABLE | Should -BeExactly '/tmp/$HOME/kmymoney'
        $Values.CRAFT_PYTHON | Should -BeExactly ''
        $After = [Environment]::GetEnvironmentVariables()
        $After.Count | Should -Be $Before.Count
        foreach ($Name in $Before.Keys) { $After[$Name] | Should -BeExactly $Before[$Name] }
    }

    It 'Uses the selected file relative to the repository regardless of current directory' {
        'CRAFT_ROOT=/default' | Set-Content -LiteralPath $DefaultFile
        'CRAFT_ROOT=/alternate' | Set-Content -LiteralPath (Join-Path $Fixture 'alternate.env.ini')
        Push-Location -LiteralPath $TestDrive
        try { (& $Reader -EnvFile alternate.env.ini).CRAFT_ROOT | Should -BeExactly '/alternate' }
        finally { Pop-Location }
    }

    It 'Rejects <Problem> without partially changing the environment' -ForEach @(
        @{ Problem = 'unknown keys'; Text = 'PATH=/untrusted'; ExpectedError = '*Unknown environment key*' }
        @{ Problem = 'duplicates'; Text = "CRAFT_ROOT=/one`ncraft_root=/two"; ExpectedError = '*Duplicate environment key*' }
        @{ Problem = 'unsupported sections'; Text = '[Other]'; ExpectedError = '*Invalid INI entry*' }
        @{ Problem = 'malformed entries'; Text = 'CRAFT_ROOT'; ExpectedError = '*Invalid INI entry*' }
    ) {
        $Text | Set-Content -LiteralPath $DefaultFile
        $Before = [string]$env:CRAFT_ROOT
        { & $Reader } | Should -Throw $ExpectedError
        [string]$env:CRAFT_ROOT | Should -BeExactly $Before
    }
}
