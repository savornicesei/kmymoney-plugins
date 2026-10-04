#Requires -Version 7.0
#Requires -PSEdition Core
# Run through ./build.ps1 -Tasks Check
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester shares fixture variables between setup, tests, and cleanup blocks.'
)]
param()

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $RepositoryRoot = [IO.Path]::GetFullPath('../../..', $PSScriptRoot)
    $PluginRoot = Join-Path $RepositoryRoot 'plugins/draft-transactions'
    $CatalogRoot = Join-Path $PluginRoot 'po'
    $MsgFmt = (Get-Command msgfmt -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $MsgAttrib = (Get-Command msgattrib -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $MsgCmp = (Get-Command msgcmp -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $NativeTools = @{}
    foreach ($Name in 'xgettext', 'msgmerge') {
        $NativeTools[$Name] = (Get-Command $Name -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    }
}

Describe 'Translation catalog coverage' {
    It 'Compiles every message without fuzzy entries or missing translations in <Locale>' -ForEach @(
        Get-Content (Join-Path $PSScriptRoot '../../../plugins/draft-transactions/po/LINGUAS') |
            Where-Object { $_.Trim() } | ForEach-Object { @{ Locale = $_.Trim() } }
    ) {
        $Catalog = Join-Path $CatalogRoot "$Locale/drafttransactions.po"
        $OutputFile = Join-Path $TestDrive "$Locale.mo"
        & $MsgFmt --check --check-format "--output-file=$OutputFile" $Catalog
        $LASTEXITCODE | Should -Be 0
        (Get-Item -LiteralPath $OutputFile).Length | Should -BeGreaterThan 0
        & $MsgCmp $Catalog (Join-Path $CatalogRoot 'drafttransactions.pot')
        $LASTEXITCODE | Should -Be 0
        $Untranslated = & $MsgAttrib --untranslated --no-obsolete $Catalog | Out-String
        $LASTEXITCODE | Should -Be 0
        $Untranslated | Should -Not -Match '(?m)^msgid "[^"\r\n]'
        $Fuzzy = & $MsgAttrib --only-fuzzy --no-obsolete $Catalog | Out-String
        $LASTEXITCODE | Should -Be 0
        $Fuzzy | Should -Not -Match '(?m)^msgid "[^"\r\n]'
    }

    It 'Has exactly the declared catalog directories and localized metadata entries' {
        $Locales = @(Get-Content (Join-Path $CatalogRoot 'LINGUAS') | Where-Object { $_.Trim() })
        $Directories = @(Get-ChildItem -LiteralPath $CatalogRoot -Directory | ForEach-Object Name)
        @(Compare-Object $Locales $Directories).Count | Should -Be 0
        @($Locales | Select-Object -Unique).Count | Should -Be $Locales.Count
        $Metadata = Get-Content (Join-Path $PluginRoot 'drafttransactions.json.in') -Raw | ConvertFrom-Json -AsHashtable
        foreach ($Prefix in 'Name', 'Description') {
            $Keys = @($Metadata.KPlugin.Keys | Where-Object { $_.StartsWith($Prefix + '[', [StringComparison]::Ordinal) })
            $Keys.Count | Should -Be $Locales.Count
            foreach ($Locale in $Locales) {
                $Metadata.KPlugin["$Prefix`[$Locale]"] | Should -Not -BeNullOrEmpty
            }
        }
    }
}

Describe 'Translation extraction and merge' {
    BeforeEach {
        $SavedLocation = $PWD.Path
        $FixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $FixtureScripts = Join-Path $FixtureRoot 'scripts'
        $FixturePlugin = Join-Path $FixtureRoot 'plugins/draft-transactions'
        New-Item -ItemType Directory -Path $FixtureScripts, $FixturePlugin | Out-Null
        foreach ($Name in 'src', 'po', 'drafttransactions.json.in', 'drafttransactions.rc') {
            Copy-Item -LiteralPath (Join-Path $PluginRoot $Name) -Destination $FixturePlugin -Recurse
        }
        $Module = Import-TestBuildModule -RepositoryRoot $FixtureRoot
        $Updater = Get-Command Update-KMMTranslation
        Mock -ModuleName KMMPluginBuild Get-Command { [pscustomobject]@{ Source = $NativeTools[$Name] } }
    }

    AfterEach {
        Set-Location -LiteralPath $SavedLocation
    }

    It 'Extracts current source, XMLGUI and metadata while preserving translations' {
        $Catalog = Join-Path $FixturePlugin 'po/ro/drafttransactions.po'
        $Before = Get-Content -LiteralPath $Catalog -Raw
        & $Updater -Plugin draft-transactions *> (Join-Path $TestDrive 'extract.log')
        $PWD.Path | Should -Be $SavedLocation
        $Template = Get-Content (Join-Path $FixturePlugin 'po/drafttransactions.pot') -Raw
        $Template | Should -Match 'msgid "Drafts"'
        $Template | Should -Match 'msgid "Keep complete transactions in drafts and restore them later"'
        $Template | Should -Match 'msgid "Draft metadata is not valid JSON\."'
        $Original = Get-Content (Join-Path $CatalogRoot 'drafttransactions.pot') -Raw
        $OriginalIds = @([regex]::Matches($Original, '(?m)^msgid .+$').Value | Sort-Object)
        $CurrentIds = @([regex]::Matches($Template, '(?m)^msgid .+$').Value | Sort-Object)
        @(Compare-Object $OriginalIds $CurrentIds).Count | Should -Be 0
        $BeforeValues = @([regex]::Matches($Before, '(?m)^msgstr .+$').Value)
        $AfterValues = @([regex]::Matches((Get-Content -LiteralPath $Catalog -Raw), '(?m)^msgstr .+$').Value)
        @(Compare-Object $BeforeValues $AfterValues).Count | Should -Be 0
    }

    It 'Propagates native extraction failure and restores the working directory' {
        $FailureTool = Join-Path $FixtureRoot 'failed-xgettext.ps1'
        ' $global:LASTEXITCODE = 17 ' | Set-Content -LiteralPath $FailureTool
        Mock -ModuleName KMMPluginBuild Get-Command { [pscustomobject]@{ Source = $FailureTool } } -ParameterFilter { $Name -eq 'xgettext' }
        { & $Updater -Plugin draft-transactions } | Should -Throw '*xgettext failed with exit code 17*'
        $PWD.Path | Should -Be $SavedLocation
    }

    It 'Updates only the selected plugin and its own domain' {
        $OtherPlugin = Join-Path $FixtureRoot 'plugins/sample-plugin'
        New-Item -ItemType Directory -Path (Join-Path $OtherPlugin 'src/nested'), (Join-Path $OtherPlugin 'po/ro') | Out-Null
        '{"KPlugin":{"Name":"Sample plugin","Description":"Sample description"}}' |
            Set-Content -LiteralPath (Join-Path $OtherPlugin 'samplecatalog.json.in')
        'i18n("Nested sample message");' | Set-Content -LiteralPath (Join-Path $OtherPlugin 'src/nested/sample.cpp')
        # This plugin has no XMLGUI menu. Its folder name differs from its domain.
        $OtherCatalog = Join-Path $OtherPlugin 'po/ro/samplecatalog.po'
        @'
msgid ""
msgstr ""
"Content-Type: text/plain; charset=UTF-8\n"
"Language: ro\n"

msgid "Nested sample message"
msgstr "Mesaj de test imbricat"
'@ | Set-Content -LiteralPath $OtherCatalog
        $OriginalHashes = @{}
        foreach ($File in Get-ChildItem -LiteralPath $FixturePlugin -Recurse -File) {
            $OriginalHashes[$File.FullName] = (Get-FileHash -LiteralPath $File.FullName).Hash
        }
        & $Updater -Plugin sample-plugin *> (Join-Path $TestDrive 'sample-extract.log')
        $Template = Get-Content (Join-Path $OtherPlugin 'po/samplecatalog.pot') -Raw
        $Template | Should -Match 'msgid "Nested sample message"'
        $Template | Should -Match 'msgid "Sample plugin"'
        $Template | Should -Match 'msgid "Sample description"'
        $Template | Should -Not -Match 'Draft transactions|drafttransactions'
        (Get-Content -LiteralPath $OtherCatalog -Raw) | Should -Match 'msgstr "Mesaj de test imbricat"'
        (Get-Content -LiteralPath $OtherCatalog -Raw) | Should -Match 'msgid "Sample description"'
        Test-Path -LiteralPath (Join-Path $OtherPlugin 'po/drafttransactions.pot') | Should -BeFalse
        foreach ($File in $OriginalHashes.Keys) {
            (Get-FileHash -LiteralPath $File).Hash | Should -BeExactly $OriginalHashes[$File]
        }
        $PWD.Path | Should -Be $SavedLocation
    }

    It 'Rejects an unknown plugin before calling gettext' {
        { & $Updater -Plugin missing-plugin } | Should -Throw '*Plugin directory does not exist*'
        Should -Invoke -ModuleName KMMPluginBuild Get-Command -Times 0 -Exactly
    }

    It 'Rejects a missing selected INI before invoking gettext' {
        { & $Updater -Plugin draft-transactions -EnvFile missing.env.ini } | Should -Throw '*Environment file does not exist*'
        Should -Invoke -ModuleName KMMPluginBuild Get-Command -Times 0 -Exactly
    }

    It 'Rejects plugin path traversal' {
        { & $Updater -Plugin '../draft-transactions' } | Should -Throw '*Plugin*'
        Should -Invoke -ModuleName KMMPluginBuild Get-Command -Times 0 -Exactly
    }

    It 'Rejects ambiguous metadata before calling gettext' {
        Copy-Item -LiteralPath (Join-Path $FixturePlugin 'drafttransactions.json.in') -Destination (Join-Path $FixturePlugin 'other.json.in')
        { & $Updater -Plugin draft-transactions } | Should -Throw '*exactly one*metadata template*'
        Should -Invoke -ModuleName KMMPluginBuild Get-Command -Times 0 -Exactly
    }

    It 'Previews the selected plugin without discovering tools or changing catalogs' {
        $Template = Join-Path $FixturePlugin 'po/drafttransactions.pot'
        $OriginalHash = (Get-FileHash -LiteralPath $Template).Hash
        & $Updater -Plugin draft-transactions -WhatIf
        Should -Invoke -ModuleName KMMPluginBuild Get-Command -Times 0 -Exactly
        (Get-FileHash -LiteralPath $Template).Hash | Should -BeExactly $OriginalHash
    }

    It 'Reports the affected locale when a native merge fails' {
        $FailureTool = Join-Path $FixtureRoot 'failed-msgmerge.ps1'
        ' $global:LASTEXITCODE = 19 ' | Set-Content -LiteralPath $FailureTool
        Mock -ModuleName KMMPluginBuild Get-Command { [pscustomobject]@{ Source = $FailureTool } } -ParameterFilter { $Name -eq 'msgmerge' }
        { & $Updater -Plugin draft-transactions 2>$null } | Should -Throw '*msgmerge failed for * with exit code 19*'
        $PWD.Path | Should -Be $SavedLocation
    }
}
