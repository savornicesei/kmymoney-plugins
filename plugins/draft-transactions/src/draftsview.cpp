// SPDX-License-Identifier: GPL-2.0-or-later
#include "draftsview.h"
#include "draftservice.h"

#include <KLocalizedString>
#include <QAction>
#include <QDateEdit>
#include <QDialogButtonBox>
#include <QFormLayout>
#include <QHeaderView>
#include <QLabel>
#include <QLineEdit>
#include <QMenu>
#include <QPushButton>
#include <QTableWidget>
#include <QVBoxLayout>
#include <mymoneyaccount.h>
#include <mymoneyfile.h>
#include <mymoneyenums.h>
#include <mymoneyexception.h>
#include <mymoneymoney.h>
#include <mymoneysplit.h>

namespace DraftTransactions {
namespace {
void configureTable(QTableWidget* table, const QStringList& headers)
{
    table->setColumnCount(headers.size());
    table->setHorizontalHeaderLabels(headers);
    table->setEditTriggers(QAbstractItemView::NoEditTriggers);
    table->setSelectionBehavior(QAbstractItemView::SelectRows);
    table->setSelectionMode(QAbstractItemView::SingleSelection);
    table->setDragDropMode(QAbstractItemView::NoDragDrop);
    // Paint a flat row selection instead of the Windows style's accent on each cell.
    table->setStyleSheet(QStringLiteral("QTableWidget::item:selected {"
                                       " background-color: palette(highlight);"
                                       " color: palette(highlighted-text);"
                                       " border: none;"
                                       "}"));
    table->horizontalHeader()->setSectionResizeMode(QHeaderView::ResizeToContents);
    table->horizontalHeader()->setStretchLastSection(true);
    table->verticalHeader()->hide();
}

QString referenceName(const DraftRecord& record, const QString& id)
{
    return id.isEmpty() ? QString() : record.referenceNames.value(id, id);
}

QString stateName(eMyMoney::Split::State state)
{
    switch (state) {
    case eMyMoney::Split::State::NotReconciled:
        return i18n("Not reconciled");
    case eMyMoney::Split::State::Cleared:
        return i18n("Cleared");
    case eMyMoney::Split::State::Reconciled:
        return i18n("Reconciled");
    case eMyMoney::Split::State::Frozen:
        return i18n("Frozen");
    default:
        return i18n("Unknown");
    }
}

bool isInvestmentAccount(const QString& accountId)
{
    try {
        const auto account = MyMoneyFile::instance()->account(accountId);
        return account.isInvest() || account.accountType() == eMyMoney::Account::Type::Investment;
    } catch (const MyMoneyException&) {
        // Drafts remain readable even after an account has been removed.
        return false;
    }
}

void fillDetails(QTableWidget* table, const DraftRecord& record)
{
    configureTable(table,
                   {i18n("Account"),
                    i18n("Payee"),
                    i18n("Value (%1)", record.transaction.commodity()),
                    i18n("Shares (exact)"),
                    i18n("Price (exact)"),
                    i18n("Reconciliation"),
                    i18n("Reconciliation date"),
                    i18n("Memo")});
    table->setRowCount(record.transaction.splits().size());
    int row = 0;
    for (const auto& split : record.transaction.splits()) {
        const bool investment = isInvestmentAccount(split.accountId());
        const QStringList values{referenceName(record, split.accountId()),
                                 referenceName(record, split.payeeId()),
                                 split.value().formatMoney(QString(), -1),
                                 investment ? split.shares().toString() : QString(),
                                 investment ? split.price().toString() : QString(),
                                 stateName(split.reconcileFlag()),
                                 split.reconcileDate().toString(Qt::ISODate),
                                 split.memo()};
        for (int column = 0; column < values.size(); ++column)
            table->setItem(row, column, new QTableWidgetItem(values[column]));
        ++row;
    }
}
}

DraftsView::DraftsView(QWidget* parent)
    : QDialog(parent)
    , m_table(new QTableWidget(this))
    , m_details(new QTableWidget(this))
    , m_filter(new QLineEdit(this))
    , m_status(new QLabel(this))
    , m_restore(new QAction(i18n("Restore"), this))
{
    setWindowTitle(i18n("Draft transactions"));
    resize(1050, 650);
    setModal(false);
    auto* layout = new QVBoxLayout(this);
    m_filter->setPlaceholderText(i18n("Filter drafts…"));
    layout->addWidget(m_filter);
    configureTable(
        m_table,
        {i18n("Date"), i18n("Account"), i18n("Payee"), i18n("Memo"), i18n("Value"), i18n("Currency"), i18n("Splits"), i18n("Drafted (UTC)"), i18n("Status")});
    configureTable(m_details, {});
    m_table->setSortingEnabled(true);
    layout->addWidget(m_table, 2);
    layout->addWidget(new QLabel(i18n("Splits"), this));
    layout->addWidget(m_details, 1);
    m_status->setWordWrap(true);
    layout->addWidget(m_status);
    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Close, this);
    connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);
    layout->addWidget(buttons);
    connect(m_filter, &QLineEdit::textChanged, this, &DraftsView::filterRows);
    connect(m_table, &QTableWidget::itemSelectionChanged, this, &DraftsView::showDetails);
    connect(m_restore, &QAction::triggered, this, [this]() {
        Q_EMIT restoreRequested(selectedId());
    });
    m_table->setContextMenuPolicy(Qt::CustomContextMenu);
    connect(m_table, &QTableWidget::customContextMenuRequested, this, [this](const QPoint& point) {
        const auto index = m_table->indexAt(point);
        if (!index.isValid())
            return;
        m_table->selectRow(index.row());
        QMenu menu(this);
        menu.addAction(m_restore);
        menu.exec(m_table->viewport()->mapToGlobal(point));
    });
    refresh(false);
}

QString DraftsView::selectedId() const
{
    const auto* item = m_table->item(m_table->currentRow(), 0);
    return item ? item->data(Qt::UserRole).toString() : QString();
}

void DraftsView::refresh(bool documentOpen)
{
    const auto previousId = selectedId();
    m_restore->setEnabled(false);
    m_records.clear();
    m_table->setRowCount(0);
    m_details->setRowCount(0);
    if (!documentOpen) {
        m_status->setText(i18n("Open a KMyMoney document to view its drafts."));
        return;
    }
    try {
        m_records = DraftService().records();
    } catch (const MyMoneyException& error) {
        m_status->setText(i18n("Unable to read drafts: %1", QString::fromUtf8(error.what())));
        return;
    }
    m_table->setSortingEnabled(false);
    m_table->setRowCount(m_records.size());
    int row = 0;
    for (const auto& record : std::as_const(m_records)) {
        const auto split = record.transaction.splitById(record.originSplitId);
        const QStringList values{record.transaction.postDate().toString(Qt::ISODate),
                                 referenceName(record, split.accountId()),
                                 referenceName(record, split.payeeId()),
                                 record.transaction.memo(),
                                 split.value().formatMoney(QString(), -1),
                                 record.transaction.commodity(),
                                 QString::number(record.transaction.splitCount()),
                                 record.created.toUTC().toString(Qt::ISODate),
                                 record.restoredId.isEmpty() ? i18n("Draft") : i18n("Restored; recovery copy retained")};
        for (int column = 0; column < values.size(); ++column)
            m_table->setItem(row, column, new QTableWidgetItem(values[column]));
        m_table->item(row, 0)->setData(Qt::UserRole, record.id);
        ++row;
    }
    m_table->setSortingEnabled(true);
    for (int index = 0; index < m_table->rowCount(); ++index) {
        if (m_table->item(index, 0)->data(Qt::UserRole).toString() == previousId)
            m_table->selectRow(index);
    }
    m_status->setText(m_records.isEmpty() ? i18n("No draft transactions in this document.")
                                          : i18n("Drafts do not affect balances. Save the document to keep changes. Restored recovery copies are removed only "
                                                 "after a clean save and full verification; cleanup is saved with the next document save."));
    filterRows();
    showDetails();
}

void DraftsView::showDetails()
{
    m_details->setRowCount(0);
    m_restore->setEnabled(false);
    const auto id = selectedId();
    for (const auto& record : std::as_const(m_records)) {
        if (record.id == id) {
            fillDetails(m_details, record);
            m_restore->setEnabled(record.restoredId.isEmpty());
            break;
        }
    }
}

void DraftsView::filterRows()
{
    for (int row = 0; row < m_table->rowCount(); ++row) {
        bool visible = m_filter->text().isEmpty();
        for (int column = 0; column < m_table->columnCount(); ++column)
            visible |= m_table->item(row, column)->text().contains(m_filter->text(), Qt::CaseInsensitive);
        m_table->setRowHidden(row, !visible);
    }
}

QDate chooseRestoreDate(const DraftRecord& record, QWidget* parent)
{
    QDialog dialog(parent);
    dialog.setWindowTitle(i18n("Restore draft transaction"));
    dialog.resize(1000, 480);
    auto* layout = new QVBoxLayout(&dialog);
    auto* explanation =
        new QLabel(i18n("Every split will return to its original account. Only the posting date can change; reconciliation flags and dates remain unchanged."),
                   &dialog);
    explanation->setWordWrap(true);
    layout->addWidget(explanation);
    auto* form = new QFormLayout;
    auto* date = new QDateEdit(record.transaction.postDate(), &dialog);
    date->setCalendarPopup(true);
    date->setDisplayFormat(QStringLiteral("yyyy-MM-dd"));
    date->setMinimumDate(QDate(1, 1, 1));
    form->addRow(i18n("Posting date:"), date);
    layout->addLayout(form);
    auto* details = new QTableWidget(&dialog);
    fillDetails(details, record);
    layout->addWidget(details);
    auto* warning = new QLabel(i18n("Moving or restoring reconciled transactions changes historical balances. If you change the posting date, review the "
                                    "affected reconciliations afterwards."),
                               &dialog);
    warning->setWordWrap(true);
    layout->addWidget(warning);
    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &dialog);
    buttons->button(QDialogButtonBox::Ok)->setText(i18n("Restore"));
    QObject::connect(buttons, &QDialogButtonBox::accepted, &dialog, &QDialog::accept);
    QObject::connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
    layout->addWidget(buttons);
    return dialog.exec() == QDialog::Accepted ? date->date() : QDate();
}
}
