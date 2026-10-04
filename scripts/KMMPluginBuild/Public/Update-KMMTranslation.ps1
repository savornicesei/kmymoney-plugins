function Update-KMMTranslation {
    <#
    .SYNOPSIS
    Extracts and merges translation catalogs for a selected repository plugin.
    .DESCRIPTION
    Uses GNU gettext from the initialized Craft environment. Extracts C++ strings,
    XMLGUI text, and plugin metadata into the POT template and merges existing PO
    catalogs without guessing translations. Does not translate text automatically.
    .PARAMETER Plugin
    Directory name under the repository's plugins folder, such as draft-transactions.
    The plugin must have one root-level <domain>.json.in metadata template. Its basename
    selects the translation domain, optional <domain>.rc, and PO/POT filenames.
    .PARAMETER EnvFile
    Optional local INI file. Gettext is located under its CRAFT_ROOT before PATH.
    Defaults to the repository env.ini if present.
    .EXAMPLE
    ./build.ps1 -Tasks EnterCraft
    ./build.ps1 -Tasks UpdateTranslations -Plugins draft-transactions
    Updates the POT and PO catalogs after changing user-facing strings.
    .EXAMPLE
    ./build.ps1 -Tasks UpdateTranslations -Plugins draft-transactions -Preview
    Previews the catalog update without writing files or requiring gettext.
    .INPUTS
    None.
    .OUTPUTS
    Native gettext diagnostics.
    .NOTES
    Requires PowerShell Core 7 and xgettext/msgmerge on PATH. Edits only plugin PO/POT
    files. Review new untranslated entries and metadata Name/Description translations
    before committing. Temporary extraction files are removed in finally.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]*$')]
        [string]$Plugin,

        [string]$EnvFile
    )

    & {
        param([string]$SelectedPlugin, [string]$SelectedFile)

        Set-StrictMode -Version 3.0
        $ErrorActionPreference = 'Stop'
        $PSNativeCommandUseErrorActionPreference = $false
        $PluginRoot = Join-Path $script:RepositoryRoot "plugins/$SelectedPlugin"
        if (-not (Test-Path -LiteralPath $PluginRoot -PathType Container)) {
            throw "Plugin directory does not exist: $PluginRoot"
        }
        $MetadataFiles = @(Get-ChildItem -LiteralPath $PluginRoot -File -Filter '*.json.in')
        if ($MetadataFiles.Count -ne 1) {
            throw "Plugin '$SelectedPlugin' must contain exactly one root-level <domain>.json.in metadata template."
        }
        $Domain = $MetadataFiles[0].Name -replace '\.json\.in$', ''
        if ($Domain -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') {
            throw "Invalid translation domain in metadata filename: $($MetadataFiles[0].Name)"
        }
        $CatalogRoot = Join-Path $PluginRoot 'po'
        $SourceRoot = Join-Path $PluginRoot 'src'
        if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
            throw "Plugin '$SelectedPlugin' has no src directory."
        }
        if (-not $PSCmdlet.ShouldProcess("$SelectedPlugin ($Domain) PO and POT catalogs", 'Extract and merge translations')) {
            return
        }
        $FileValues = Read-KMMLocalEnvironment -EnvFile $SelectedFile
        $GettextTools = @{}
        foreach ($Tool in 'xgettext', 'msgmerge') {
            $Candidates = @()
            if ($FileValues['CRAFT_ROOT']) {
                $Suffix = if ($IsWindows) { '.exe' } else { '' }
                $Candidates = @('bin', 'dev-utils/bin') | ForEach-Object { Join-Path $FileValues['CRAFT_ROOT'] "$_/$Tool$Suffix" }
            }
            $ToolPath = $Candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
            if (-not $ToolPath) { $ToolPath = (Get-Command $Tool -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source }
            $GettextTools[$Tool] = $ToolPath
        }
        $XGettext = $GettextTools['xgettext']
        $MsgMerge = $GettextTools['msgmerge']
        $TemporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('plugin-translations-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $TemporaryRoot | Out-Null
        $OriginalLocation = Get-Location
        try {
            Set-Location -LiteralPath $PluginRoot
            $Metadata = Get-Content -LiteralPath $MetadataFiles[0].FullName -Raw | ConvertFrom-Json
            $Strings = @($Metadata.KPlugin.Name, $Metadata.KPlugin.Description)
            $MenuPath = Join-Path $PluginRoot "$Domain.rc"
            if (Test-Path -LiteralPath $MenuPath -PathType Leaf) {
                [xml]$Menus = Get-Content -LiteralPath $MenuPath -Raw
                $Strings += @($Menus.SelectNodes('//text') | ForEach-Object InnerText)
            }
            $Extracted = foreach ($String in $Strings) {
                'i18n(' + (ConvertTo-Json -InputObject $String -Compress) + ');'
            }
            $ExtraSource = Join-Path $TemporaryRoot 'metadata.cpp'
            [IO.File]::WriteAllText($ExtraSource, ($Extracted -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
            New-Item -ItemType Directory -Path $CatalogRoot -Force | Out-Null
            $Template = Join-Path $CatalogRoot "$Domain.pot"
            $Sources = @(Get-ChildItem -LiteralPath $SourceRoot -File -Recurse |
                Where-Object Extension -In '.cpp', '.h', '.cc', '.cxx', '.hpp' |
                Sort-Object FullName | ForEach-Object FullName)
            & $XGettext --language=C++ --kde --from-code=UTF-8 --keyword=i18n:1 --keyword=i18nc:1c,2 `
                --flag=i18n:1:kde-format --flag=i18nc:2:kde-format --add-comments=TRANSLATORS: `
                --sort-output --no-location --no-wrap "--package-name=$Domain" `
                "--copyright-holder=$($Metadata.KPlugin.Name) contributors" "--output=$Template" @Sources $ExtraSource
            if ($LASTEXITCODE -ne 0) {
                throw "xgettext failed with exit code $LASTEXITCODE."
            }
            foreach ($Directory in Get-ChildItem -LiteralPath $CatalogRoot -Directory) {
                $Catalog = Join-Path $Directory.FullName "$Domain.po"
                if (Test-Path -LiteralPath $Catalog -PathType Leaf) {
                    & $MsgMerge --update --backup=none --no-fuzzy-matching --no-wrap --no-location $Catalog $Template
                    if ($LASTEXITCODE -ne 0) {
                        throw "msgmerge failed for $($Directory.Name) with exit code $LASTEXITCODE."
                    }
                }
            }
        } finally {
            Set-Location -LiteralPath $OriginalLocation
            # Delete only files this invocation created, then the now-empty directory.
            $ExtraSource = Join-Path $TemporaryRoot 'metadata.cpp'
            if (Test-Path -LiteralPath $ExtraSource -PathType Leaf) {
                Remove-Item -LiteralPath $ExtraSource
            }
            Remove-Item -LiteralPath $TemporaryRoot
        }
    } $Plugin $EnvFile
}
