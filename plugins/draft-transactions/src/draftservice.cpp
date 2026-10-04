// SPDX-License-Identifier: GPL-2.0-or-later
#include "draftservice.h"
#include "draftcodec.h"
#include "drafterror.h"
#include <algorithm>
#include <functional>
#include <optional>

#include <KLocalizedString>
#include <QSet>
#include <QUndoStack>
#include <QUuid>
#include <costcentermodel.h>
#include <mymoneyaccount.h>
#include <mymoneyexception.h>
#include <mymoneyfile.h>
#include <mymoneypayee.h>
#include <mymoneysecurity.h>
#include <mymoneysplit.h>
#include <mymoneytag.h>
#include <parametersmodel.h>

namespace DraftTransactions {
namespace {
// ParametersModel::addItem/deleteItem bypass the host's undo stack. Supply the
// missing command inside the same engine macro as journal edits. The plugin
// pins its module in memory so these commands remain valid after UI unload.
class MetadataCommand final : public QUndoCommand
{
public:
    MetadataCommand(const QString& key, std::optional<QString> value)
        : m_model(MyMoneyFile::instance()->parametersModel())
        , m_key(key)
        , m_after(std::move(value))
    {
        const auto pairs = m_model->pairs();
        if (pairs.contains(key))
            m_before = pairs.value(key);
    }
    void undo() override
    {
        apply(m_before);
    }
    void redo() override
    {
        apply(m_after);
    }

private:
    void apply(const std::optional<QString>& value)
    {
        if (value)
            m_model->addItem(m_key, *value);
        else
            m_model->deleteItem(m_key);
        m_model->setDirty(true);
        auto* file = MyMoneyFile::instance();
        if (!file->hasTransaction()) {
            const auto documentId = file->value(QStringLiteral("kmm-id"));
            QMetaObject::invokeMethod(
                file,
                [file, documentId]() {
                    if (file->dirty() && !file->hasTransaction() && file->value(QStringLiteral("kmm-id")) == documentId)
                        Q_EMIT file->dataChanged();
                },
                Qt::QueuedConnection);
        }
    }
    ParametersModel* m_model;
    QString m_key;
    std::optional<QString> m_before;
    std::optional<QString> m_after;
};

void changeMetadata(const QString& key, std::optional<QString> value)
{
    MyMoneyFile::instance()->undoStack()->push(new MetadataCommand(key, std::move(value)));
}

void editDocument(const QString& description, const std::function<void()>& edit)
{
    try {
        MyMoneyFileTransaction operation(description, true);
        edit();
        operation.commit();
    } catch (...) {
        // The host rolls back by undoing its macro, but leaves that rejected
        // macro available for Redo. Discard it so failed validation cannot be
        // bypassed by Redo. An obsolete no-op truncates only the redo branch.
        auto* discardRedo = new QUndoCommand;
        discardRedo->setObsolete(true);
        MyMoneyFile::instance()->undoStack()->push(discardRedo);
        throw;
    }
}

void validateReferences(const MyMoneyTransaction& transaction, QMap<QString, QString>& names, int depth = 0)
{
    if (depth > 16)
        throw draftError(i18n("Matched transaction nesting is too deep."));
    auto* file = MyMoneyFile::instance();
    const auto security = file->security(transaction.commodity());
    if (security.id().isEmpty())
        throw draftError(i18n("The transaction currency or security no longer exists."));
    names.insert(security.id(), security.name());
    for (const auto& split : transaction.splits()) {
        const auto account = file->account(split.accountId());
        if (account.id().isEmpty() || file->isStandardAccount(account.id()))
            throw draftError(i18n("A split references a missing or standard account: %1", split.accountId()));
        if (account.isClosed())
            throw draftError(i18n("Account '%1' is closed. Reopen it in KMyMoney before moving or restoring this transaction.", account.name()));
        names.insert(account.id(), account.name());
        if (!split.payeeId().isEmpty()) {
            const auto payee = file->payee(split.payeeId());
            if (payee.id().isEmpty())
                throw draftError(i18n("A split references a missing payee: %1", split.payeeId()));
            names.insert(payee.id(), payee.name());
        }
        for (const auto& id : split.tagIdList()) {
            const auto tag = file->tag(id);
            if (tag.id().isEmpty())
                throw draftError(i18n("A split references a missing tag: %1", id));
            names.insert(id, tag.name());
        }
        if (!split.costCenterId().isEmpty()) {
            const auto center = file->costCenterModel()->itemById(split.costCenterId());
            if (center.id().isEmpty())
                throw draftError(i18n("A split references a missing cost center: %1", split.costCenterId()));
            names.insert(center.id(), center.name());
        }
        if (split.isMatched())
            validateReferences(split.matchedTransaction(), names, depth + 1);
    }
}

MyMoneyTransaction restoredCopy(const DraftRecord& record, const QString& id, const QDate& date)
{
    auto transaction = MyMoneyTransaction(id, record.transaction);
    transaction.setEntryDate(record.transaction.entryDate());
    transaction.setPostDate(date);
    return transaction;
}

bool matchesRestoration(const DraftRecord& record)
{
    try {
        const auto actual = MyMoneyFile::instance()->transaction(record.restoredId);
        return transactionObject(actual) == transactionObject(restoredCopy(record, record.restoredId, record.restoredDate));
    } catch (const MyMoneyException&) {
        return false;
    }
}
}

QString DraftService::keyPrefix()
{
    return QStringLiteral("draft-transactions/item/");
}

QList<DraftRecord> DraftService::records() const
{
    QList<DraftRecord> result;
    const auto pairs = MyMoneyFile::instance()->parametersModel()->pairs();
    for (auto it = pairs.cbegin(); it != pairs.cend(); ++it) {
        if (!it.key().startsWith(keyPrefix()))
            continue;
        auto record = decode(it.value());
        if (it.key() != keyPrefix() + record.id)
            throw draftError(i18n("Draft identity does not match its metadata key. No drafts were changed."));
        result.append(record);
    }
    return result;
}

void DraftService::move(const QList<MoveSelection>& selections) const
{
    if (selections.isEmpty())
        throw draftError(i18n("Select at least one saved transaction."));
    auto* file = MyMoneyFile::instance();
    if (file->hasTransaction())
        throw draftError(i18n("Finish the current KMyMoney operation first."));
    const auto existing = records(); // Refuse mutations of an unreadable archive.
    QSet<QString> archivedIds;
    for (const auto& record : existing) {
        archivedIds.insert(record.transaction.id());
        archivedIds.insert(record.restoredId);
    }
    QSet<QString> selectedIds;
    QList<DraftRecord> prepared;
    for (const auto& selection : selections) {
        if (selectedIds.contains(selection.transactionId))
            continue;
        if (archivedIds.contains(selection.transactionId))
            throw draftError(i18n("This transaction already has a draft or a pending restoration record. Save the document first."));
        DraftRecord record;
        record.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
        record.created = QDateTime::currentDateTimeUtc();
        record.transaction = file->transaction(selection.transactionId);
        record.originSplitId = selection.splitId;
        const auto split = record.transaction.splitById(selection.splitId);
        if (split.id().isEmpty())
            throw draftError(i18n("The selected ledger split no longer exists."));
        validateReferences(record.transaction, record.referenceNames);
        const auto checked = decode(encode(record));
        if (transactionObject(checked.transaction) != transactionObject(record.transaction))
            throw draftError(i18n("This transaction cannot be archived without changes."));
        prepared.append(record);
        selectedIds.insert(selection.transactionId);
    }
    editDocument(i18n("Move to drafts"), [&]() {
        for (const auto& record : prepared) {
            changeMetadata(keyPrefix() + record.id, encode(record));
            file->removeTransaction(record.transaction);
        }
    });
}

QString DraftService::restore(const QString& draftId, const QDate& postDate) const
{
    auto* file = MyMoneyFile::instance();
    if (file->hasTransaction() || !postDate.isValid())
        throw draftError(i18n("Restoration requires a valid posting date and no other active operation."));
    // Read all records to reject an incompatible archive consistently.
    const auto allRecords = records();
    auto found = std::find_if(allRecords.cbegin(), allRecords.cend(), [&draftId](const auto& record) {
        return record.id == draftId;
    });
    if (found == allRecords.cend())
        throw draftError(i18n("This draft no longer exists."));
    auto record = *found;
    if (!record.restoredId.isEmpty())
        throw draftError(i18n("This draft has already been restored. Save the document to finish cleanup."));
    auto names = record.referenceNames;
    validateReferences(record.transaction, names);
    auto transaction = restoredCopy(record, QString(), postDate);
    editDocument(i18n("Restore draft transaction"), [&]() {
        file->addTransaction(transaction);
        record.restoredId = transaction.id();
        record.restoredDate = postDate;
        if (!matchesRestoration(record))
            throw draftError(i18n("KMyMoney changed transaction fields during restoration. The operation was rolled back and the draft was retained."));
        changeMetadata(keyPrefix() + record.id, encode(record));
    });
    return transaction.id();
}

int DraftService::completeSavedRestores() const
{
    auto* file = MyMoneyFile::instance();
    if (file->dirty() || file->hasTransaction())
        return 0;
    QStringList keys;
    for (const auto& record : records()) {
        if (!record.restoredId.isEmpty() && matchesRestoration(record))
            keys.append(keyPrefix() + record.id);
    }
    if (keys.isEmpty())
        return 0;
    editDocument(i18n("Remove saved restoration copies"), [&]() {
        for (const auto& key : keys)
            changeMetadata(key, std::nullopt);
    });
    // A metadata-only engine macro has no object notifications; explicitly
    // notify the host so Save and autosave notice the pending cleanup.
    Q_EMIT file->dataChanged();
    return keys.size();
}
}
