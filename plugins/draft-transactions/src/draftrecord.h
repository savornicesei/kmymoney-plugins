// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QDateTime>
#include <QMap>
#include <QString>
#include <mymoneytransaction.h>

namespace DraftTransactions {
struct DraftRecord {
    QString id;
    QDateTime created;
    QString originSplitId;
    QMap<QString, QString> referenceNames;
    MyMoneyTransaction transaction;
    // A nonempty ID means restoration has committed but archive cleanup still
    // awaits a clean host document. Never offer Restore again for this record.
    QString restoredId;
    QDate restoredDate;
};
}
