// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "draftrecord.h"
#include <QDialog>
#include <QList>

class QLabel;
class QLineEdit;
class QTableWidget;
class QAction;

namespace DraftTransactions {
class DraftsView : public QDialog
{
    Q_OBJECT
public:
    explicit DraftsView(QWidget* parent = nullptr);
    void refresh(bool documentOpen);

Q_SIGNALS:
    void restoreRequested(const QString& id);

private:
    QString selectedId() const;
    void showDetails();
    void filterRows();
    QList<DraftRecord> m_records;
    QTableWidget* m_table;
    QTableWidget* m_details;
    QLineEdit* m_filter;
    QLabel* m_status;
    QAction* m_restore;
};

// Invalid date means Cancel. Everything except the posting date is read-only.
QDate chooseRestoreDate(const DraftRecord& record, QWidget* parent);
}
