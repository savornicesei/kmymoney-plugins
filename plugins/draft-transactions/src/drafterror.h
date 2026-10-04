// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QString>
#include <mymoneyexception.h>

namespace DraftTransactions {
// The host's MYMONEYEXCEPTION macro uses qPrintable (the local code page on
// Windows). Keep plugin-owned diagnostics in UTF-8 for the UI's fromUtf8 calls.
inline MyMoneyException draftError(const QString& message)
{
    return MyMoneyException(message.toUtf8().toStdString());
}
}
