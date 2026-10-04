// SPDX-License-Identifier: GPL-2.0-or-later
#include "draftcodec.h"
#include "drafterror.h"
#include <KLocalizedString>

#include <QCryptographicHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSet>
#include <QUuid>
#include <mymoneyenums.h>
#include <mymoneyexception.h>
#include <mymoneymoney.h>
#include <mymoneysplit.h>

namespace DraftTransactions {
namespace {
constexpr qsizetype MaximumPayloadSize = 4 * 1024 * 1024;
constexpr int MaximumMatchDepth = 16;

void require(bool condition, const QString& message)
{
    if (!condition)
        throw draftError(message);
}

QJsonObject pairsObject(const QMap<QString, QString>& pairs)
{
    QJsonObject result;
    for (auto it = pairs.cbegin(); it != pairs.cend(); ++it)
        result.insert(it.key(), it.value());
    return result;
}

QMap<QString, QString> readPairs(const QJsonValue& value)
{
    require(value.isObject(), i18n("Draft metadata must be an object."));
    const auto object = value.toObject();
    QMap<QString, QString> result;
    for (auto it = object.begin(); it != object.end(); ++it) {
        require(it.value().isString(), i18n("Draft metadata values must be strings."));
        result.insert(it.key(), it.value().toString());
    }
    return result;
}

MyMoneyMoney readMoney(const QJsonValue& value)
{
    static const QRegularExpression rational(QStringLiteral("^-?[0-9]+/[1-9][0-9]*$"));
    require(value.isString() && value.toString().size() <= 4096 && rational.match(value.toString()).hasMatch(), i18n("Invalid exact monetary value in draft."));
    return MyMoneyMoney(value.toString());
}

MyMoneyTransaction readTransaction(const QJsonObject& object, int depth)
{
    require(depth <= MaximumMatchDepth, i18n("Matched transaction nesting is too deep."));
    MyMoneyTransaction transaction;
    transaction.setPostDate(QDate::fromString(object.value("postDate").toString(), Qt::ISODate));
    transaction.setEntryDate(QDate::fromString(object.value("entryDate").toString(), Qt::ISODate));
    transaction.setMemo(object.value("memo").toString());
    transaction.setCommodity(object.value("commodity").toString());
    transaction.setBankID(object.value("bankId").toString());
    transaction.setPairs(readPairs(object.value("metadata")));
    require(object.value("splits").isArray(), i18n("Draft splits are missing."));
    for (const auto& value : object.value("splits").toArray()) {
        require(value.isObject(), i18n("Invalid draft split."));
        const auto item = value.toObject();
        MyMoneySplit split;
        split.setAccountId(item.value("account").toString());
        split.setPayeeId(item.value("payee").toString());
        split.setCostCenterId(item.value("costCenter").toString());
        split.setMemo(item.value("memo").toString());
        split.setAction(item.value("action").toString());
        split.setNumber(item.value("number").toString());
        split.setBankID(item.value("bankId").toString());
        split.setTransactionId(item.value("transactionId").toString());
        split.setReconcileDate(QDate::fromString(item.value("reconcileDate").toString(), Qt::ISODate));
        const int state = item.value("reconcileState").toInt(-1);
        require(state >= 0 && state <= static_cast<int>(eMyMoney::Split::State::Frozen), i18n("Invalid reconciliation state."));
        split.setReconcileFlag(static_cast<eMyMoney::Split::State>(state));
        split.setValue(readMoney(item.value("value")));
        split.setShares(readMoney(item.value("shares")));
        split.setPrice(readMoney(item.value("price")));
        QStringList tags;
        require(item.value("tags").isArray(), i18n("Draft tags are missing."));
        for (const auto& tag : item.value("tags").toArray()) {
            require(tag.isString(), i18n("Invalid draft tag."));
            tags.append(tag.toString());
        }
        split.setTagIdList(tags);
        split.setPairs(readPairs(item.value("metadata")));
        if (item.value("match").isObject())
            split.addMatch(readTransaction(item.value("match").toObject(), depth + 1));
        else
            require(item.value("match").isNull(), i18n("Invalid matched transaction."));
        // addSplit allocates an ID; the mutable list preserves existing split IDs.
        transaction.splits().append(MyMoneySplit(item.value("id").toString(), split));
    }
    transaction = MyMoneyTransaction(object.value("id").toString(), transaction);
    const auto splitObjects = object.value("splits").toArray();
    for (qsizetype index = 0; index < transaction.splits().size(); ++index)
        transaction.splits()[index].setTransactionId(splitObjects[index].toObject().value("transactionId").toString());
    // The ID constructor supplies today's date for an empty entry date.
    transaction.setEntryDate(QDate::fromString(object.value("entryDate").toString(), Qt::ISODate));
    require(transactionObject(transaction, depth) == object, i18n("Draft contains missing, unknown, or noncanonical transaction fields."));
    return transaction;
}

QString digest(const QJsonObject& object)
{
    return QString::fromLatin1(QCryptographicHash::hash(QJsonDocument(object).toJson(QJsonDocument::Compact), QCryptographicHash::Sha256).toHex());
}
}

QJsonObject transactionObject(const MyMoneyTransaction& transaction, int depth)
{
    require(depth <= MaximumMatchDepth, i18n("Matched transaction nesting is too deep."));
    QJsonArray splits;
    for (const auto& split : transaction.splits()) {
        splits.append(QJsonObject{
            {"id", split.id()},
            {"transactionId", split.transactionId()},
            {"account", split.accountId()},
            {"payee", split.payeeId()},
            {"costCenter", split.costCenterId()},
            {"memo", split.memo()},
            {"action", split.action()},
            {"number", split.number()},
            {"bankId", split.bankID()},
            {"value", split.value().toString()},
            {"shares", split.shares().toString()},
            {"price", split.price().toString()},
            {"reconcileDate", split.reconcileDate().toString(Qt::ISODate)},
            {"reconcileState", static_cast<int>(split.reconcileFlag())},
            {"tags", QJsonArray::fromStringList(split.tagIdList())},
            {"metadata", pairsObject(split.pairs())},
            {"match", split.isMatched() ? QJsonValue(transactionObject(split.matchedTransaction(), depth + 1)) : QJsonValue(QJsonValue::Null)},
        });
    }
    return {{"id", transaction.id()},
            {"postDate", transaction.postDate().toString(Qt::ISODate)},
            {"entryDate", transaction.entryDate().toString(Qt::ISODate)},
            {"memo", transaction.memo()},
            {"commodity", transaction.commodity()},
            {"bankId", transaction.bankID()},
            {"metadata", pairsObject(transaction.pairs())},
            {"splits", splits}};
}

QString encode(const DraftRecord& record)
{
    const QJsonObject content{
        {"id", record.id},
        {"created", record.created.toString(Qt::ISODateWithMs)},
        {"originSplit", record.originSplitId},
        {"referenceNames", pairsObject(record.referenceNames)},
        {"transaction", transactionObject(record.transaction)},
        {"restoredId", record.restoredId},
        {"restoredDate", record.restoredDate.toString(Qt::ISODate)},
    };
    const auto bytes = QJsonDocument(QJsonObject{{"version", 1}, {"sha256", digest(content)}, {"content", content}}).toJson(QJsonDocument::Compact);
    require(bytes.size() <= MaximumPayloadSize, i18n("This draft exceeds the 4 MiB metadata record limit."));
    return QString::fromUtf8(bytes);
}

DraftRecord decode(const QString& payload)
{
    require(payload.size() <= MaximumPayloadSize, i18n("Draft metadata is too large."));
    QJsonParseError error;
    const auto document = QJsonDocument::fromJson(payload.toUtf8(), &error);
    require(error.error == QJsonParseError::NoError && document.isObject(), i18n("Draft metadata is not valid JSON."));
    const auto envelope = document.object();
    require(envelope.value("version") == QJsonValue(1), i18n("Unsupported draft metadata version. Update the plugin before changing drafts."));
    const auto content = envelope.value("content").toObject();
    require(envelope.value("sha256").toString() == digest(content), i18n("Draft checksum mismatch. The archive was not changed."));
    DraftRecord record;
    record.id = content.value("id").toString();
    record.created = QDateTime::fromString(content.value("created").toString(), Qt::ISODateWithMs);
    record.originSplitId = content.value("originSplit").toString();
    record.referenceNames = readPairs(content.value("referenceNames"));
    record.transaction = readTransaction(content.value("transaction").toObject(), 0);
    record.restoredId = content.value("restoredId").toString();
    record.restoredDate = QDate::fromString(content.value("restoredDate").toString(), Qt::ISODate);
    require(!QUuid(record.id).isNull() && record.created.isValid(), i18n("Invalid draft identity or timestamp."));
    require(!record.transaction.id().isEmpty() && record.transaction.postDate().isValid(), i18n("Invalid archived transaction identity or date."));
    QSet<QString> splitIds;
    for (const auto& split : record.transaction.splits()) {
        require(!split.id().isEmpty() && !splitIds.contains(split.id()), i18n("Missing or duplicate split identity in draft."));
        splitIds.insert(split.id());
    }
    require(splitIds.contains(record.originSplitId), i18n("Draft origin split does not exist."));
    require(record.restoredId.isEmpty() == !record.restoredDate.isValid(), i18n("Invalid restoration recovery record."));
    require(QJsonDocument::fromJson(encode(record).toUtf8()).object() == envelope, i18n("Unknown or missing draft fields. Archive left unchanged."));
    return record;
}
}
