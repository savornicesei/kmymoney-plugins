# Draft transactions translations

The `drafttransactions` catalog contains all 80 current user-facing messages:
menus, actions, table headings, dialogs, explanations, status messages, and
plugin-generated validation errors. The plugin name and description also have
localized entries in `../drafttransactions.json.in` for KMyMoney's plugin settings.
User financial data and persistent metadata keys are never translated.

There are 46 catalogs. This is the union of the language directories in the
installed host's KMyMoney source (`5.2.2-f1ed3c67f`) and the workspace reference
checkout, inspected on 2026-09-27. English source text is the fallback; `en_GB`
has its own catalog. KDE's `x-test` pseudo-language is not a user language.
This list is a snapshot, not a promise that future KMyMoney releases will use
exactly the same language set.

| Codes | Languages |
| --- | --- |
| `ar`, `ast`, `bg`, `bs` | Arabic, Asturian, Bulgarian, Bosnian |
| `ca`, `ca@valencia`, `cs`, `da` | Catalan, Valencian Catalan, Czech, Danish |
| `de`, `el`, `en_GB`, `eo` | German, Greek, British English, Esperanto |
| `es`, `et`, `eu`, `fi` | Spanish, Estonian, Basque, Finnish |
| `fr`, `ga`, `gl`, `hu` | French, Irish, Galician, Hungarian |
| `ia`, `it`, `ja`, `ka` | Interlingua, Italian, Japanese, Georgian |
| `kk`, `ko`, `lo`, `lt` | Kazakh, Korean, Lao, Lithuanian |
| `mr`, `ms`, `nb`, `nds` | Marathi, Malay, Norwegian Bokmål, Low German |
| `nl`, `pl`, `pt`, `pt_BR` | Dutch, Polish, Portuguese, Brazilian Portuguese |
| `ro`, `ru`, `sk`, `sl` | Romanian, Russian, Slovak, Slovenian |
| `sv`, `tr`, `ug`, `uk` | Swedish, Turkish, Uyghur, Ukrainian |
| `zh_CN`, `zh_TW` | Simplified Chinese, Traditional Chinese |

These are initial AI-assisted translations, not reviewed translations supplied
or endorsed by KDE language teams. Native-speaker review remains necessary,
especially for accounting terminology and recovery explanations. KMyMoney
catalogs were consulted for terminology and plural conventions; the final plugin
messages were authored for this plugin. PO headers identify their review status.
Reviewers should retain accurate authorship and update the revision date and
review note when they review a catalog.

## Build and try a language

The normal CMake build uses `ki18n_install(po)` to compile PO files with gettext
and stage the MO catalogs. Install into the same prefix as the plugin:

```powershell
./build.ps1 -Tasks Stage
./build.ps1 -Tasks EnterCraft
$env:LANGUAGE = 'ro'
./build.ps1 -Tasks Run
```

Close KMyMoney before changing the language. Its application-language setting
may override the environment. The plugin follows KMyMoney's language; there is
no separate plugin language selector. Qt/KDE supply translations of standard
buttons such as Cancel and Close, and host-originated errors remain the host's
responsibility.

On Windows, catalogs are staged under
`stage/craft-windows/bin/data/locale/<language>/LC_MESSAGES/drafttransactions.mo`.
On Unix, the default is `stage/<preset>/share/locale/...` unless the KDE install
layout overrides it. `EnterCraft` registers `share` and, on Windows,
`bin/data` in `XDG_DATA_DIRS`. Distributing only the plugin library omits its
catalogs; deploy the staged data directory too.

## Update translations

Run from the repository root in PowerShell 7 with Craft/gettext initialized:

```powershell
./build.ps1 -Tasks EnterCraft
./build.ps1 -Tasks UpdateTranslations -Plugins draft-transactions -Preview
./build.ps1 -Tasks UpdateTranslations -Plugins draft-transactions
```

The script extracts C++ `i18n`/`i18nc` calls, XMLGUI text, and the English plugin
name/description into `drafttransactions.pot`. It merges existing catalogs
without guessing translations. It does not translate new text or update the
localized JSON entries. Review newly empty entries, translate them in a PO
editor, and preserve `%1` placeholders exactly. Do not mark English fallback
text as a completed translation. Clear fuzzy flags only after review.

`-Plugin draft-transactions` selects this plugin's directory. Its
`drafttransactions.json.in` filename supplies the `drafttransactions` catalog
domain. Other plugins use the same script with their own directory names; see
the [script conventions](../../../scripts/README.md).

When translating the plugin name or description, copy the same translation to
`Name[language]` or `Description[language]` in `../drafttransactions.json.in`.
To add a language, add its code to `LINGUAS`, create
`<language>/drafttransactions.po` from the template with correct language and
plural headers, and add both JSON entries. CMake compiles catalogs found under
`po`; the tests ensure this directory set matches `LINGUAS`.

Rebuild after PO or metadata changes. The factory explicitly depends on the
generated JSON so incremental builds refresh embedded translations.

## Validate

```powershell
./build.ps1 -Tasks Check
./build.ps1 -Tasks Test -Plugins draft-transactions
```

Pester requires `xgettext`, `msgmerge`, `msgfmt`, `msgcmp`, and `msgattrib` on PATH.
It checks complete, non-fuzzy catalogs against the current template, gettext
syntax and placeholders, source extraction, translation preservation, declared
languages, and failure handling. CTest starts a fresh process for each locale
to check compiled catalog lookup, embedded metadata, UI text, substitution, and
UTF-8 errors. Separate processes avoid gettext's Windows language cache.
Automated checks do not establish linguistic accuracy or visual layout quality.

Windows validation passed all 47 CTest cases (the service suite plus 46 language
processes) and all 102 PowerShell checks. A separate Romanian run also loaded
catalogs from staging through `XDG_DATA_DIRS`, without registering the build
catalog directory. Linux/macOS execution and native-speaker layout review
remain unverified.
