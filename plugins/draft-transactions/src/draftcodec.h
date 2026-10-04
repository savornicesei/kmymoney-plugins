// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "draftrecord.h"
#include <QJsonObject>

namespace DraftTransactions {
// Versioned, lossless text payload for document metadata. Throws MyMoneyException
// on unsupported versions, malformed data, or a lossy decode.
QString encode(const DraftRecord& record);
DraftRecord decode(const QString& payload);
QJsonObject transactionObject(const MyMoneyTransaction& transaction, int depth = 0);
}
