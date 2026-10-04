// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "draftservice.h"
#include <QPointer>
#include <kmymoneyplugin.h>

class QAction;
class QWidget;
class QTimer;
namespace DraftTransactions {
class DraftsView;
}

class DraftTransactionsPlugin : public KMyMoneyPlugin::Plugin
{
    Q_OBJECT
public:
    explicit DraftTransactionsPlugin(QObject* parent, const KPluginMetaData& metadata, const QVariantList& arguments);
    ~DraftTransactionsPlugin() override;
    void updateActions(const SelectedObjects& selections) override;
    void unplug() override;
    void plug(KXMLGUIFactory* factory) override;

private:
    void showDrafts();
    void moveSelected();
    void restoreDraft(const QString& id);
    void refresh();
    QAction* m_show;
    QAction* m_move;
    QPointer<QWidget> m_window;
    QPointer<DraftTransactions::DraftsView> m_view;
    QList<DraftTransactions::MoveSelection> m_selections;
    QString m_selectionDocument;
    bool m_documentOpen = false;
    bool m_active = true;
    bool m_modulePinned = false;
    QTimer* m_timer;
};
