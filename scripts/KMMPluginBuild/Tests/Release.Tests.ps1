#Requires -Version 7.0
#Requires -PSEdition Core
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester shares fixture state between setup and tests.')]
param()

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $RepositoryRoot = [IO.Path]::GetFullPath('../../..', $PSScriptRoot)
}

Describe 'Release packages with native CMake, CTest and CPack' {
    BeforeEach {
        $SavedEnvironment = [Environment]::GetEnvironmentVariables()
        $env:KMM_RELEASE_TARGET = $null
        $Fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $Fixture, (Join-Path $Fixture 'cmake'), (Join-Path $Fixture 'LICENSES')
        Copy-Item (Join-Path $RepositoryRoot 'cmake/KMMRelease.cmake') (Join-Path $Fixture 'cmake')
        Copy-Item (Join-Path $RepositoryRoot 'LICENSES/GPL-2.0-or-later.txt') (Join-Path $Fixture 'LICENSES')
        Copy-Item (Join-Path $RepositoryRoot 'release-compatibility.schema.json') $Fixture
        @{ schemaVersion = 1; plugins = @{ 'first-plugin' = @{ '1.2.3' = @{ kmymoney = @('master'); qtMajor = 6 } }; 'second-plugin' = @{ '1.2.3' = @{ kmymoney = @('master'); qtMajor = 6 } } } } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $Fixture 'release-compatibility.json')
        'synthetic SDK header' | Set-Content (Join-Path $Fixture 'mymoneyfile.h')
        '#define VERSION "5.2.3-fixture"' | Set-Content (Join-Path $Fixture 'config-kmymoney-version.h')
        foreach ($Plugin in 'first-plugin', 'second-plugin') {
            $Directory = Join-Path $Fixture "plugins/$Plugin"
            $null = New-Item -ItemType Directory -Path $Directory -Force
            '# selection marker' | Set-Content (Join-Path $Directory 'CMakeLists.txt')
            @{ KPlugin = @{ Id = $Plugin; Name = $Plugin; License = 'GPL-2.0-or-later'; Version = '@PROJECT_VERSION@' } } |
                ConvertTo-Json -Depth 3 | Set-Content (Join-Path $Directory 'plugin.json.in')
        }
        @'
cmake_minimum_required(VERSION 3.21)
project(ReleaseFixture VERSION ${KMM_PLUGIN_VERSION} LANGUAGES NONE)
include(CTest)
option(KMM_RELEASE_PACKAGING "Release fixture" ON)
# Exercise ZIP contents on every test platform; no native code is compiled here.
set(WIN32 TRUE)
set(APPLE FALSE)
if(EXISTS "${CMAKE_SOURCE_DIR}/macos-fixture")
    set(WIN32 FALSE)
    set(APPLE TRUE)
endif()
if(EXISTS "${CMAKE_SOURCE_DIR}/linux-fixture")
    set(WIN32 FALSE)
    set(APPLE FALSE)
    set(CMAKE_SYSTEM_NAME Linux)
endif()
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(KMYMONEY_INCLUDE_DIR "${CMAKE_SOURCE_DIR}")
set(KMYMONEY_BUILD_DIR "${CMAKE_SOURCE_DIR}")
set(KDE_INSTALL_PLUGINDIR lib/plugins)
set(KDE_INSTALL_LOCALEDIR share/locale)
set(Qt6_VERSION fixture)
include(cmake/KMMRelease.cmake)
configure_file("plugins/${KMM_PLUGIN_SELECTION}/plugin.json.in" plugin.json @ONLY)
install(FILES "${CMAKE_BINARY_DIR}/plugin.json" DESTINATION "lib/plugins/${KMM_PLUGIN_SELECTION}")
if(EXISTS "${CMAKE_SOURCE_DIR}/fail-${KMM_PLUGIN_SELECTION}")
    add_test(NAME synthetic COMMAND "${CMAKE_COMMAND}" -E false)
else()
    add_test(NAME synthetic COMMAND "${CMAKE_COMMAND}" -E true)
endif()
'@ | Set-Content (Join-Path $Fixture 'CMakeLists.txt')
        $Preset = if ($IsWindows) { 'craft-windows' } elseif ($IsMacOS) { 'craft-macos' } else { 'craft-linux' }
        @{ version = 3; configurePresets = @(@{ name = $Preset; generator = 'Ninja' }) } |
            ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Fixture 'CMakePresets.json')
        $Module = Import-TestBuildModule -RepositoryRoot $Fixture
        Mock -ModuleName KMMPluginBuild Enter-KMMCraftEnvironment {}
        Mock -ModuleName KMMPluginBuild Set-KMMAppVersion {}
        Mock -ModuleName KMMPluginBuild Get-KMMCraftReleaseHost { @{ Target = 'master'; Version = '5.2.3-fixture'; BuildDirectory = $Fixture } }
        $env:KMYMONEY_SDK_SOURCE_DIR = $Fixture
        $env:KMYMONEY_BUILD_DIR = $Fixture
        $Context = New-KMMBuildContext -Plugins all
        $Context.KMMAppVersion = ''
    }

    AfterEach {
        foreach ($Name in @([Environment]::GetEnvironmentVariables().Keys)) {
            if (-not $SavedEnvironment.Contains($Name)) { Remove-Item -LiteralPath "Env:$Name" }
        }
        foreach ($Name in $SavedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($Name, $SavedEnvironment[$Name], 'Process') }
    }

    It 'Publishes one isolated package per selected plugin with the requested metadata version and checksums' {
        Invoke-KMMRelease -Context $Context -Version 1.2.3
        $Directory = Join-Path $Fixture 'publish/kmymoney/master/windows'
        @(Get-ChildItem $Directory -Filter '*.zip').Count | Should -Be 2
        foreach ($Plugin in 'first-plugin', 'second-plugin') {
            $Base = Join-Path $Directory "$Plugin-1.2.3-windows-x86_64"
            $Archive = [IO.Compression.ZipFile]::OpenRead("$Base.zip")
            try {
                $Archive.Entries.FullName | Should -Contain "lib/plugins/$Plugin/plugin.json"
                $Other = if ($Plugin -eq 'first-plugin') { 'second-plugin' } else { 'first-plugin' }
                $Archive.Entries.FullName | Should -Not -Contain "lib/plugins/$Other/plugin.json"
                $Reader = [IO.StreamReader]::new($Archive.GetEntry("lib/plugins/$Plugin/plugin.json").Open())
                try { $Metadata = $Reader.ReadToEnd() | ConvertFrom-Json } finally { $Reader.Dispose() }
                $Metadata.KPlugin.Version | Should -BeExactly '1.2.3'
                $Metadata.KPlugin.Id | Should -BeExactly $Plugin
                $Manifest = Get-Content "$Base.manifest.json" -Raw | ConvertFrom-Json
                $Manifest.Plugin | Should -BeExactly $Plugin
                $Manifest.Build.Version | Should -BeExactly '1.2.3'
                $Archive.GetEntry("share/doc/kmymoney-plugin-$Plugin/release-manifest.json") | Should -Not -BeNullOrEmpty
                foreach ($File in $Manifest.Files) {
                    $Stream = $Archive.GetEntry($File.Path).Open()
                    $Hasher = [Security.Cryptography.SHA256]::Create()
                    try { $Hash = [BitConverter]::ToString($Hasher.ComputeHash($Stream)).Replace('-', '').ToLowerInvariant() }
                    finally { $Stream.Dispose(); $Hasher.Dispose() }
                    $Hash | Should -BeExactly $File.SHA256
                }
            } finally { $Archive.Dispose() }
            (Get-Content "$Base.sha256").Split(' ')[0] | Should -Be ((Get-FileHash "$Base.zip").Hash.ToLowerInvariant())
        }
    }

    It 'Rejects a missing plugin version before entering Craft' {
        { Invoke-KMMRelease -Context $Context -Version 9.9.9 } | Should -Throw '*9.9.9*'
        Should -Invoke -ModuleName KMMPluginBuild Enter-KMMCraftEnvironment -Times 0
    }

    It 'Publishes nothing when a later selected plugin fails its tests' {
        'fail' | Set-Content (Join-Path $Fixture 'fail-second-plugin')
        # Expected native stderr must not mark Invoke-KMMCheck's outer runspace as failed.
        { Invoke-KMMRelease -Context $Context -Version 1.2.3 2>$null } | Should -Throw '*exit code*'
        Test-Path (Join-Path $Fixture 'publish') | Should -BeFalse
    }

    It 'Produces the macOS tar.gz layout using the TGZ packaging branch' {
        'macos' | Set-Content (Join-Path $Fixture 'macos-fixture')
        $Context.Plugins = @('first-plugin')
        Invoke-KMMRelease -Context $Context -Version 1.2.3
        $Package = Get-ChildItem (Join-Path $Fixture 'publish/kmymoney/master/macos') -Filter '*.tar.gz'
        @($Package).Count | Should -Be 1
        $Contents = & cmake -E tar tf $Package.FullName
        $LASTEXITCODE | Should -Be 0
        $Contents | Should -Contain 'lib/plugins/first-plugin/plugin.json'
        $Contents | Should -Contain 'share/doc/kmymoney-plugin-first-plugin/release-manifest.json'
    }

    It 'Produces Linux tar.gz archives against the Craft host' {
        'linux' | Set-Content (Join-Path $Fixture 'linux-fixture')
        $Context.Plugins = @('first-plugin')
        Invoke-KMMRelease -Context $Context -Version 1.2.3
        $Package = Join-Path $Fixture 'publish/kmymoney/master/linux/first-plugin-1.2.3-linux-x86_64.tar.gz'
        Test-Path $Package | Should -BeTrue
        $Contents = & cmake -E tar tf $Package
        $LASTEXITCODE | Should -Be 0
        $Contents | Should -Contain 'lib/plugins/first-plugin/plugin.json'
    }

    It 'Rejects a host that the selected plugin version does not support' {
        Mock -ModuleName KMMPluginBuild Get-KMMCraftReleaseHost { @{ Target = '5.2'; Version = '5.2.3-fixture'; BuildDirectory = $Fixture } }
        { Invoke-KMMRelease -Context $Context -Version 1.2.3 } | Should -Throw '*does not support KMyMoney 5.2*'
        Test-Path (Join-Path $Fixture 'publish') | Should -BeFalse
    }

    It 'Keeps existing artifacts intact when the same release is requested again' {
        $Context.Plugins = @('first-plugin')
        Invoke-KMMRelease -Context $Context -Version 1.2.3
        $Package = Get-ChildItem (Join-Path $Fixture 'publish') -Recurse -Filter '*.zip'
        $Hash = (Get-FileHash $Package.FullName).Hash
        { Invoke-KMMRelease -Context $Context -Version 1.2.3 } | Should -Throw '*already exists*'
        (Get-FileHash $Package.FullName).Hash | Should -BeExactly $Hash
        @(Get-ChildItem (Join-Path $Fixture 'publish') -Recurse -Filter '*.zip').Count | Should -Be 1
    }
}

Describe 'Release compatibility selectors' {
    BeforeAll {
        $Module = Import-TestBuildModule
        $MatchVersion = & $Module { Get-Command Test-KMMVersionSelector }
    }
    It 'Matches <Selector> against <Target> / <HostVersion> as <Expected>' -ForEach @(
        @{ Selector = 'master'; Target = 'master'; HostVersion = '5.2.70-abcdef1'; Expected = $true }
        @{ Selector = '5.2.*'; Target = 'master'; HostVersion = '5.2.70-abcdef1'; Expected = $false }
        @{ Selector = '5.2.*'; Target = '5.2'; HostVersion = '5.2.3-abcdef1'; Expected = $true }
        @{ Selector = '5.2.3'; Target = '5.2'; HostVersion = '5.2.3-abcdef1'; Expected = $true }
        @{ Selector = '5.2.3'; Target = '5.2.4'; HostVersion = '5.2.4'; Expected = $false }
        @{ Selector = '5.2'; Target = '5.2'; HostVersion = '5.2.3'; Expected = $true }
        @{ Selector = '5.0 - 5.3'; Target = '5.3'; HostVersion = '5.3.999'; Expected = $true }
        @{ Selector = '5.0 - 5.3'; Target = '5.4'; HostVersion = '5.4.0'; Expected = $false }
        @{ Selector = '5.0 - 5.3'; Target = '4.9'; HostVersion = '4.9.9'; Expected = $false }
        @{ Selector = '5.2.1 - 5.2.4'; Target = '5.2.4'; HostVersion = '5.2.4'; Expected = $true }
        @{ Selector = '5.2.1 - 5.2.4'; Target = '5.2.5'; HostVersion = '5.2.5'; Expected = $false }
    ) {
        & $MatchVersion -Selector $Selector -Target $Target -HostVersion $HostVersion | Should -Be $Expected
    }
    It 'Rejects a reversed interval' {
        { & $MatchVersion -Selector '5.3 - 5.2' -Target '5.2' -HostVersion '5.2.3' } | Should -Throw '*Reversed*'
    }
}

Describe 'Installed Craft host identity' {
    BeforeEach {
        $Module = Import-TestBuildModule
        $GetHost = & $Module { Get-Command Get-KMMCraftReleaseHost }
        $SavedCraft = $env:CRAFT_ROOT
        $SavedPython = $env:CRAFT_PYTHON
        $SavedBuild = $env:KMYMONEY_BUILD_DIR
        $env:CRAFT_ROOT = $TestDrive
        $env:CRAFT_PYTHON = 'python'
        $env:KMYMONEY_BUILD_DIR = $TestDrive
        '#define VERSION "5.2.70-abcdef123"' | Set-Content (Join-Path $TestDrive 'config-kmymoney-version.h')
        'BUILD_WITH_QT6:BOOL=ON' | Set-Content (Join-Path $TestDrive 'CMakeCache.txt')
        Mock -ModuleName KMMPluginBuild Invoke-KMMNativeTool {
            "[extragear/kmymoney]`nversion = master`nrevision = abcdef123" | Set-Content $ArgumentList[-1]
        }
        $Context = @{ KMMAppVersion = 'master' }
    }
    AfterEach {
        $env:CRAFT_ROOT = $SavedCraft
        $env:CRAFT_PYTHON = $SavedPython
        $env:KMYMONEY_BUILD_DIR = $SavedBuild
    }
    It 'Accepts the installed branch only with matching generated SDK revision' {
        $HostInfo = & $GetHost -Context $Context -Directory $TestDrive
        $HostInfo.Target | Should -BeExactly 'master'
        $HostInfo.Version | Should -BeExactly '5.2.70-abcdef123'
    }
    It 'Rejects a configuration change that has not rebuilt the host' {
        $Context.KMMAppVersion = '5.2'
        { & $GetHost -Context $Context -Directory $TestDrive } | Should -Throw '*Craft has*master*installed*'
    }
    It 'Rejects stale generated SDK headers' {
        '#define VERSION "5.2.70-123456789"' | Set-Content (Join-Path $TestDrive 'config-kmymoney-version.h')
        { & $GetHost -Context $Context -Directory $TestDrive } | Should -Throw '*revision differs*'
    }
    It 'Rejects a Qt 5 SDK' {
        'BUILD_WITH_QT6:BOOL=OFF' | Set-Content (Join-Path $TestDrive 'CMakeCache.txt')
        { & $GetHost -Context $Context -Directory $TestDrive } | Should -Throw '*not a Qt 6 build*'
    }
}
