#Requires -Version 7.0
#Requires -PSEdition Core
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester shares fixture variables between setup and test blocks.'
)]
param()

BeforeAll {
    . (Join-Path $PSScriptRoot '../Private/Copy-KMMSqlCipherRuntime.ps1')
}

Describe 'Staged SQLCipher runtime compatibility' {
    BeforeEach {
        $PreviousCraftRoot = $env:CRAFT_ROOT
        $Fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $env:CRAFT_ROOT = Join-Path $Fixture 'craft'
        $Context = @{ Preset = 'craft-windows'; Stage = (Join-Path $Fixture 'stage') }
        $null = New-Item -ItemType Directory -Path (Join-Path $env:CRAFT_ROOT 'bin') -Force
        $Source = Join-Path $env:CRAFT_ROOT 'bin/libsqlcipher.dll'
        $Destination = Join-Path $Context.Stage 'bin/sqlite3.dll'
        [IO.File]::WriteAllBytes($Source, [byte[]](1, 2, 3, 4))
    }
    AfterEach {
        if ($null -eq $PreviousCraftRoot) { Remove-Item Env:CRAFT_ROOT -ErrorAction SilentlyContinue }
        else { $env:CRAFT_ROOT = $PreviousCraftRoot }
    }
    It 'Copies exact bytes and supports repeated staging without changing Craft' {
        Copy-KMMSqlCipherRuntime -Context $Context
        Copy-KMMSqlCipherRuntime -Context $Context
        (Get-FileHash $Destination).Hash | Should -BeExactly (Get-FileHash $Source).Hash
        Test-Path (Join-Path $env:CRAFT_ROOT 'bin/sqlite3.dll') | Should -BeFalse
    }
    It 'Preserves a conflicting staged DLL and reports the conflict' {
        $null = New-Item -ItemType Directory -Path (Split-Path $Destination) -Force
        [IO.File]::WriteAllBytes($Destination, [byte[]](9, 8, 7))
        $OriginalHash = (Get-FileHash $Destination).Hash
        { Copy-KMMSqlCipherRuntime -Context $Context } | Should -Throw '*conflicts with Craft*'
        (Get-FileHash $Destination).Hash | Should -BeExactly $OriginalHash
    }
    It 'Skips a Craft installation that supplies the expected DLL' {
        [IO.File]::WriteAllBytes((Join-Path $env:CRAFT_ROOT 'bin/sqlite3.dll'), [byte[]](5))
        Copy-KMMSqlCipherRuntime -Context $Context
        Test-Path $Context.Stage | Should -BeFalse
    }
    It 'Skips installations without SQLCipher' {
        Remove-Item -LiteralPath $Source
        Copy-KMMSqlCipherRuntime -Context $Context
        Test-Path $Context.Stage | Should -BeFalse
    }
    It 'Skips non-Windows presets' -ForEach @('craft-linux', 'craft-macos') {
        $Context.Preset = $_
        Copy-KMMSqlCipherRuntime -Context $Context
        Test-Path $Context.Stage | Should -BeFalse
    }
}
