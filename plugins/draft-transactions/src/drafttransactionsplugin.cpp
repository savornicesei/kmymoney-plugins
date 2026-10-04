// SPDX-License-Identifier: GPL-2.0-or-later
#include "drafttransactionsplugin.h"
#include "draftsview.h"

#include <KActionCollection>
#include <KLocalizedString>
#include <KPluginFactory>
#include <QAction>
#include <QLibrary>
#include <QMessageBox>
#include <QTimer>
#include <QUndoStack>
#include <QWidget>
#include <appinterface.h>
#include <journalmodel.h>
#include <mymoneyenums.h>
#include <mymoneyexception.h>
#include <mymoneyfile.h>
#include <selectedobjects.h>

using namespace DraftTransactions;

DraftTransactionsPlugin::DraftTransactionsPlugin(QObject* parent, const KPluginMetaData& metadata, const QVariantList& arguments)
    : KMyMoneyPlugin::Plugin(parent, metadata, arguments)
    , m_show(actionCollection()->addAction(QStringLiteral("drafts_show")))
    , m_move(actionCollection()->addAction(QStringLiteral("transaction_move_to_drafts")))
    , m_window(qobject_cast<QWidget*>(parent))
    , m_timer(new QTimer(this))
{
    Q_INIT_RESOURCE(drafttransactions);
    setXMLFile(QStringLiteral("drafttransactions.rc"));
    m_show->setText(i18n("Show drafts…"));
    m_move->setText(i18n("Move to drafts"));
    m_move->setEnabled(false);
    auto* library = new QLibrary(metadata.fileName(), this);
    library->setLoadHints(QLibrary::PreventUnloadHint);
    m_modulePinned = library->load();
    connect(m_show, &QAction::triggered, this, &DraftTransactionsPlugin::showDrafts);
    connect(m_move, &QAction::triggered, this, &DraftTransactionsPlugin::moveSelected);
    auto* file = MyMoneyFile::instance();
    connect(file, &MyMoneyFile::dataChanged, this, &DraftTransactionsPlugin::refresh, Qt::QueuedConnection);
    connect(file, &MyMoneyFile::modelsReadyToUse, this, &DraftTransactionsPlugin::refresh, Qt::QueuedConnection);
    connect(file->undoStack(), &QUndoStack::indexChanged, this, &DraftTransactionsPlugin::refresh, Qt::QueuedConnection);
    // The host has no usable public save-completion signal. Its clean flag is
    // reset after successful persistence/load; never infer success from Save clicks.
    m_timer->setInterval(1000);
    connect(m_timer, &QTimer::timeout, this, [this, file]() {
        const bool open = appInterface()->fileOpen();
        if (open != m_documentOpen)
            refresh();
        if (!open || file->dirty() || !m_modulePinned)
            return;
        try {
            if (DraftService().completeSavedRestores() > 0)
                refresh();
        } catch (const MyMoneyException&) {
            // An unreadable/unsupported archive remains intact; Show drafts
            // presents the error without repeating background message boxes.
        }
    });
    m_timer->start();
}

DraftTransactionsPlugin::~DraftTransactionsPlugin()
{
    delete m_view.data();
}

void DraftTransactionsPlugin::unplug()
{
    m_active = false;
    m_timer->stop();
    delete m_view.data();
    m_selections.clear();
    m_move->setEnabled(false);
    KMyMoneyPlugin::Plugin::unplug();
}

void DraftTransactionsPlugin::plug(KXMLGUIFactory* factory)
{
    KMyMoneyPlugin::Plugin::plug(factory);
    m_active = true;
    m_timer->start();
}

void DraftTransactionsPlugin::updateActions(const SelectedObjects& selections)
{
    m_selections.clear();
    auto* file = MyMoneyFile::instance();
    m_selectionDocument = file->value(QStringLiteral("kmm-id"));
    if (m_active && m_modulePinned && appInterface()->fileOpen()) {
        for (const auto& id : selections.selection(SelectedObjects::JournalEntry)) {
            const auto index = file->journalModel()->indexById(id);
            const auto transactionId = index.data(eMyMoney::Model::JournalTransactionIdRole).toString();
            const auto splitId = index.data(eMyMoney::Model::JournalSplitIdRole).toString();
            if (!transactionId.isEmpty() && !splitId.isEmpty())
                m_selections.append({transactionId, splitId});
        }
    }
    m_move->setEnabled(!m_selections.isEmpty());
}

void DraftTransactionsPlugin::showDrafts()
{
    if (!m_view) {
        m_view = new DraftsView(m_window);
        connect(m_view, &DraftsView::restoreRequested, this, &DraftTransactionsPlugin::restoreDraft);
    }
    refresh();
    m_view->show();
    m_view->raise();
    m_view->activateWindow();
}

void DraftTransactionsPlugin::moveSelected()
{
    auto* file = MyMoneyFile::instance();
    const auto document = m_selectionDocument;
    if (!m_active || !m_modulePinned || !appInterface()->fileOpen() || file->value(QStringLiteral("kmm-id")) != document)
        return;
    const auto selections = m_selections;
    if (QMessageBox::question(m_window,
                              i18n("Move to drafts"),
                              i18n("Move the complete selected transactions, including every split, to drafts? They will stop affecting all account balances, "
                                   "reports, and reconciliations."),
                              QMessageBox::Yes | QMessageBox::Cancel,
                              QMessageBox::Cancel)
        != QMessageBox::Yes)
        return;
    if (!appInterface()->fileOpen() || file->value(QStringLiteral("kmm-id")) != document)
        return;
    try {
        DraftService().move(selections);
        m_selections.clear();
        m_move->setEnabled(false);
        refresh();
    } catch (const MyMoneyException& error) {
        QMessageBox::warning(m_window, i18n("Unable to move to drafts"), QString::fromUtf8(error.what()));
    }
}

void DraftTransactionsPlugin::restoreDraft(const QString& id)
{
    if (!m_modulePinned) {
        QMessageBox::warning(m_view,
                             i18n("Unable to restore draft"),
                             i18n("The plugin module could not be retained for undo history. Restart KMyMoney and check the plugin installation."));
        return;
    }
    if (!m_active || !appInterface()->fileOpen())
        return;
    const auto document = MyMoneyFile::instance()->value(QStringLiteral("kmm-id"));
    try {
        for (const auto& record : DraftService().records()) {
            if (record.id != id || !record.restoredId.isEmpty())
                continue;
            const auto date = chooseRestoreDate(record, m_view);
            if (date.isValid() && appInterface()->fileOpen() && MyMoneyFile::instance()->value(QStringLiteral("kmm-id")) == document)
                DraftService().restore(id, date);
            refresh();
            break;
        }
    } catch (const MyMoneyException& error) {
        QMessageBox::warning(m_view, i18n("Unable to restore draft"), QString::fromUtf8(error.what()));
    }
}

void DraftTransactionsPlugin::refresh()
{
    if (!m_active)
        return;
    m_documentOpen = appInterface()->fileOpen();
    if (!m_documentOpen) {
        m_selections.clear();
        m_move->setEnabled(false);
    }
    if (m_view)
        m_view->refresh(m_documentOpen);
}

K_PLUGIN_CLASS_WITH_JSON(DraftTransactionsPlugin, "drafttransactions.json")
#include "drafttransactionsplugin.moc"
