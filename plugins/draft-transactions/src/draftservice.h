// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "draftrecord.h"
#include <QList>

namespace DraftTransactions {
struct MoveSelection {
    QString transactionId;
    QString splitId;
};

// Operates on the host singleton on its GUI thread, through the host undo model.
// Exceptions roll back the complete batch, including metadata changes.
class DraftService
{
public:
    static QString keyPrefix();
    QList<DraftRecord> records() const;
    void move(const QList<MoveSelection>& selections) const;
    QString restore(const QString& draftId, const QDate& postDate) const;
    // Call only for an open document. Removes verified pending copies only when
    // every host model is clean. Cleanup itself awaits the next normal save.
    int completeSavedRestores() const;
};
}
