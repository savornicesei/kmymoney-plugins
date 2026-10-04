# Draft transactions

Move complete KMyMoney transactions into a read-only drafts collection and restore them later.
All splits leave the active journal together, so drafts do not affect balances, reports, or reconciliation.
Only the posting date can change on restore; original accounts and financial fields remain unchanged.

This is an initial development implementation for an unmodified Qt 6 / KDE Frameworks 6 KMyMoney host.
Use synthetic documents for development; see the validation status below before evaluating other hosts.

## Build and load

Follow the [shared Craft setup](../../README.md), including environment variables and matching host ABI.
From a PowerShell 7 session at the repository root:

```powershell
./build.ps1 -Tasks Stage
./build.ps1 -Tasks EnterCraft
ctest --test-dir "build/$env:KMYMONEY_PRESET" --output-on-failure
./build.ps1 -Tasks Run
```

Enable **Draft transactions** in KMyMoney's plugin settings.
The module and Windows debug symbols install into `stage/<preset>/lib/plugins/kmymoney_plugins`.
Close KMyMoney before installing a replacement module.
The [root README](../../README.md) covers VS Code, CLion, and Qt Creator debugging.
The root CMake option `BUILD_DRAFT_TRANSACTIONS` controls this plugin independently of future plugins.

## Usage

1. Select posted transactions in a ledger and choose **Move to drafts** from the context menu.
   Confirm that every split, including postings in other accounts, leaves the active journal.
2. Open **Drafts > Show drafts…** to browse drafts from the current document.
   Select a row to inspect all its splits; the table is read-only and supports sorting and filtering.
3. Right-click a draft and choose **Restore**.
   Review its accounts and splits, optionally change its posting date, and select **Restore**.
4. Save the document normally.

KMyMoney assigns a new transaction ID on restore.
The plugin compares the complete restored transaction with the requested copy before committing.
Unexpected host normalization causes rollback and leaves the original draft intact.
Reconciliation flags and dates are preserved even when the posting date changes.
The dialogs explain that affected historical reconciliations need review.
Closed accounts must be reopened explicitly through KMyMoney.

## Save, recovery, and undo

Moving archives the complete transaction and removes its active copy in one host engine transaction.
Metadata and journal changes share an undo group, so undo and redo update both collections together.

Restoration first adds and verifies the active transaction, then marks its draft as a recovery copy with the new transaction ID and posting date.
That copy cannot be restored again.
It remains until the host reports that all document models are clean and the active transaction still matches the expected restoration exactly.
The plugin checks this while the document is open; clicking Save is not treated as proof of success.

After verification, cleanup removes the recovery copy from memory and marks the document modified again.
The next normal save persists that cleanup.
A crash before cleanup leaves a recovery copy alongside the restored transaction; reopening can finish cleanup without inserting another transaction.
If the active transaction was edited or removed before verification, its recovery copy remains.
This version does not offer automatic conflict resolution or a second restoration of pending records.

The host's parameter setters bypass undo, so the plugin supplies explicit metadata commands through the public undo stack and parameter model.
It explicitly marks metadata changes dirty, including updates of existing values.
It discards the redo branch of rejected operations so Redo cannot bypass failed restoration checks.
Plugin code stays loaded until process exit because undo history can reference those commands after the plugin UI is disabled.

## Storage format

Each draft uses a document metadata key `draft-transactions/item/<UUID>`.
Its value is compact UTF-8 JSON with schema version `1`, a content object, and a SHA-256 checksum of the content.
The checksum detects accidental changes; it is not authentication.
Records are limited to 4 MiB and matched transactions to 16 nesting levels.
Unsupported versions, malformed records, and checksum failures block mutations and leave metadata untouched.
No older plugin format exists to migrate yet; future formats require explicit migrations.

The content stores original IDs, both dates, commodity, memo, bank identifiers, every split, exact rational monetary values, references, reconciliation fields, arbitrary key/value pairs, and recursively matched transactions.
It also stores the originating split, UTC draft timestamp, reference display names, and restoration recovery state.
Reference names are snapshots for display; they do not recreate missing objects.

| Host storage | Draft location |
| --- | --- |
| `.kmy` | Existing document-level key/value XML section |
| SQL | Existing `kmmKeyValuePairs` rows of type `STORAGE` |

There are no new XML sections, SQL tables, sidecar files, or direct live-database writes.
Stock storage code preserves drafts when the plugin is disabled.
Native saves, document copies, and backups carry the metadata in that document version.
The plugin does not add SQL backup functionality or a separate backup command.
Document encryption encloses the embedded metadata; encrypted save/reopen has not yet been exercised here.
CSV/QIF exports do not carry this archive.
Do not treat anonymized exports as restorable draft archives or assume they safely anonymize this payload; that host path needs separate validation.

Opaque metadata does not participate in reference tracking or duplicate-import detection.
Deleting a referenced account, payee, tag, cost center, or security can prevent restoration.
Reimporting bank data may reintroduce a drafted transaction.
Restore validates references and never chooses replacement accounts or silently recreates objects.

## Validation

All 80 user-facing messages have catalogs for the 46 locales in the checked
KMyMoney sources, including localized plugin metadata. These are initial
AI-assisted translations awaiting native-speaker review. See the
[translation guide](po/README.md) for languages, installation, and maintenance.

Tests use synthetic data and the actual installed host engine.
With `BUILD_HOST_STORAGE_TESTS=ON` (default), the matching host's unmodified XML and SQL adapters compile into the test executable only.
These sources are neither modified nor linked into the plugin.

Windows validation uses KMyMoney `5.2.2-f1ed3c67f`, Qt 6.11.1, KDE Frameworks 6.30, and MSVC 2022 x64.
The synthetic service suite covers transaction and storage behavior; separate
runtime tests exercise every translation catalog. The PowerShell suite also
checks catalog completeness and extraction; see the translation guide for commands.
The workspace reference checkout differs from the installed host.
`KMYMONEY_SDK_SOURCE_DIR` and `KMYMONEY_BUILD_DIR` identify matching SDK inputs; Craft build-cache discovery supplies them locally.

| Behavior | Regression test |
| --- | --- |
| Complete splits, exact money, metadata, matched transactions, frozen state | `codecPreservesCompleteMatchedTransaction` |
| All account balances exclude drafts; duplicate selection is deduplicated | `moveExcludesEverySplitAndDeduplicatesSelection` |
| Undo/redo across archive and journal | `moveAndRestoreSupportUndoRedo` |
| Only date and identity change; cleanup waits for clean saved state | `restoreChangesOnlyDateAndIdentityAndRetainsCopyUntilSaved` |
| Edits after restore retain the recovery copy | `editedRestorationRetainsRecoveryCopy` |
| Multi-currency, investment, loan, matched-import, and frozen transactions | `nativeTransactionVariantsRoundTrip` |
| Closed accounts and invalid batches leave both stores unchanged | `closedAccountAndInvalidBatchLeaveBothStoresUnchanged` |
| Missing references, invalid dates, corrupt/future records | `missingReferenceAndInvalidDateKeepDraft`, `corruptAndFuturePayloadsAreRejected` |
| Normalization rolls back and cannot be redone | `unexpectedHostNormalizationRollsBackRestoration` |
| Plugin factory loads; menu actions and separators exist | `pluginLoadsWithRequestedMenuActions` |
| Read-only list, split details, Restore action, date-only dialog, cancellation | `draftsViewIsReadOnlyAndRestoreDialogEditsOnlyDate` |
| Stock XML save/reopen/resave and copied backup | `stockXmlSaveReopenAndBackupPreserveDrafts` |
| Stock SQLite persistence and conversion to XML | `stockSqlAndXmlConversionPreserveDrafts` |
| Restart before cleanup cannot duplicate a restoration | `savedRestorationSurvivesRestartBeforeCleanup` |
| Failed XML/SQLite saves retain durable drafts and recovery copies | `failedXmlWriteRetainsRecoveryCopyAndDurableDraft`, `failedSqlSaveKeepsDurableDraftAndPendingRecovery` |
| Every locale loads, metadata and UI agree, substitutions and Unicode errors survive | `DraftTranslationTest::catalogAndUiUseSelectedLanguage` |

Native Linux/macOS builds, encrypted/compressed-file workflows, actual backup UI, SQL server drivers and payload limits, and an interactive host walkthrough remain to be checked.
Fixtures cover split transactions, transfers, investments, loans, multi-currency entries, matched imports, and frozen/reconciled states.
Broader real-world combinations remain acceptance work.
Host restrictions and normalization reject unsupported cases without changing the archived financial data.

## Code map

- `draftcodec`: strict serialization and complete-field comparison.
- `drafterror`: preserves UTF-8 in plugin-generated exceptions.
- `draftservice`: validation, metadata undo, move/restore, recovery cleanup.
- `drafttransactionsplugin`: host actions, selection mapping, lifecycle, clean-state monitoring.
- `draftsview`: read-only list, split details, filtering, restore dialog.
- `tests/draftservicetest.cpp`: engine, persistence, factory, and UI checks.
- `po/`, `tests/drafttranslationtest.cpp`: catalogs and per-language runtime checks.

Source code uses [GPL-2.0-or-later](../../LICENSES/GPL-2.0-or-later.txt).
