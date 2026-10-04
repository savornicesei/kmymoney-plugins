# Draft transactions — implementation plan and decisions

Status: metadata storage approved and the first implementation created.
See [README.md](README.md) for behavior, build commands, recovery semantics, tests, and validation limits.

## Confirmed requirements

- Display name: **Draft transactions**; project directory: `plugins/draft-transactions`.
- Move the entire transaction and all splits out of every active ledger, balance, report, and reconciliation.
- Support `.kmy` and SQL storage on an unmodified KMyMoney host.
- Provide a **Drafts** main menu and a plugin-owned read-only list for all accounts in the current document.
- Add **Move to drafts** in a separate ledger context-menu section and **Restore** in the draft-row context menu.
- Only the posting date is editable on restore; original account assignments stay fixed.
- A new host-assigned transaction ID is acceptable.
- Delete the archived copy only after successful complete restoration.

## Accepted storage decision

Use namespaced, versioned document metadata in both formats.
Existing XML parameters and SQL `STORAGE` key/value records already participate in normal host persistence.
No custom XML section, dedicated SQL tables, or sidecar file is created.
Unknown top-level XML sections are lost on stock save; extra SQL tables need independent conversion and backup handling.
The host exposes no supported backup-completion hook with destination information, so embedding drafts avoids coordinating companion backups.

The initial source investigation used reference revision `12920e6a4`.
Build and runtime checks use the installed Craft host `5.2.2-f1ed3c67f` and matching source/generated headers.
The standalone build discovers those inputs without modifying or rebuilding the host.

## Implemented architecture

The root CMake project aggregates independently selectable plugins and retains shared Windows/Linux/macOS presets.
`drafttransactions` installs in the `kmymoney_plugins` namespace under local staging.
The host's fixed navigation-page enum is not extended; the Drafts menu opens a plugin-owned window.

Each metadata record contains the complete transaction, nested matches, exact monetary values, originating split, reference display names, and recovery state.
A version and checksum reject unsupported or damaged records without rewriting them.
Restore validates references and compares every field, accepting only the chosen posting date and new transaction identity.

Moves and restores use host engine transactions.
Tests established that host parameter setters bypass undo; explicit metadata commands now group with journal operations.
The host also leaves a failed transaction in its redo branch after rollback; rejected plugin operations discard that branch.
The module remains resident while undo history can reference its commands, even after UI deactivation.

Restoration retains the original archive plus the restored ID and posting date.
The same record cannot be restored twice.
Automatic cleanup requires a clean host document and an exact match of the active transaction to the expected restoration.
Cleanup marks the document dirty and is persisted by the next normal save.
Changed or missing active transactions leave the recovery copy intact.
This separates engine commit, durable restoration, and eventual archive cleanup.

## Host constraints

Closed accounts must be reopened by the user before moving or restoring their transactions.
Opaque metadata cannot protect references from host deletion or participate in import duplicate detection.
Restore rejects missing references without silently recreating them.
Reconciliation flags and dates stay unchanged; dialogs explain effects on historical balances.
Unexpected host normalization causes rollback.

## Acceptance work

Automated checks cover engine operations, archival round trips, undo/redo, failed validation, XML/SQLite persistence, SQL-to-XML conversion, backup copies, restart recovery, plugin factory loading, and the read-only/date-only UI.
The plugin README maps individual tests to behavior and records validation limits.

Before a production release:

1. Build and load natively in Linux and macOS hosts.
2. Exercise actual host menus and backup UI with synthetic documents.
3. Verify compressed/encrypted files and supported SQL server drivers, including size limits and failed-save rollback.
4. Expand financial fixtures beyond the initial synthetic examples.
5. Establish anonymized-export handling for opaque draft payloads.
6. Define a resolution workflow for retained recovery records whose active transactions changed before cleanup.

No host modifications, production document edits, or installations into the shared Craft prefix are included.
