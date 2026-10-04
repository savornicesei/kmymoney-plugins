// SPDX-License-Identifier: GPL-2.0-or-later
#include "draftcodec.h"
#include "draftsview.h"

#include <KLocalizedString>
#include <KPluginMetaData>
#include <QAction>
#include <QFile>
#include <QJsonObject>
#include <QTest>
#include <algorithm>
#include <mymoneyexception.h>

class DraftTranslationTest : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void catalogAndUiUseSelectedLanguage()
    {
        const auto locale = qEnvironmentVariable("DRAFT_TEST_LOCALE");
        QVERIFY(!locale.isEmpty());
        KLocalizedString::setApplicationDomain("drafttransactions");
        if (!qEnvironmentVariableIsSet("DRAFT_TEST_USE_INSTALLED_CATALOGS"))
            KLocalizedString::addDomainLocaleDir("drafttransactions", QStringLiteral(DRAFT_LOCALE_DIR));
        KLocalizedString::setLanguages({locale});
        QVERIFY(QFile::exists(QStringLiteral(DRAFT_LOCALE_DIR "/%1/LC_MESSAGES/drafttransactions.mo").arg(locale)));

        const KPluginMetaData metadata(QStringLiteral(DRAFT_PLUGIN_FILE));
        const auto plugin = metadata.rawData().value(QStringLiteral("KPlugin")).toObject();
        const auto expectedName = plugin.value(QStringLiteral("Name[%1]").arg(locale)).toString();
        const auto expectedDescription = plugin.value(QStringLiteral("Description[%1]").arg(locale)).toString();
        QVERIFY(!expectedName.isEmpty());
        QVERIFY(!expectedDescription.isEmpty());
        QCOMPARE(i18n("Draft transactions"), expectedName);
        QCOMPARE(i18n("Keep complete transactions in drafts and restore them later"), expectedDescription);
        QCOMPARE(metadata.name(), expectedName);
        QCOMPARE(metadata.description(), expectedDescription);
        if (locale != QStringLiteral("en_GB")) {
            QVERIFY(i18n("Move to drafts") != QStringLiteral("Move to drafts"));
            QVERIFY(i18n("Draft metadata is not valid JSON.") != QStringLiteral("Draft metadata is not valid JSON."));
        }
        const auto errorText = i18n("Unable to read drafts: %1", QStringLiteral("synthetic-error"));
        QVERIFY(errorText.contains(QStringLiteral("synthetic-error")));
        QVERIFY(!errorText.contains(QStringLiteral("%1")));

        DraftTransactions::DraftsView view;
        QCOMPARE(view.windowTitle(), expectedName);
        const auto actions = view.findChildren<QAction*>();
        QVERIFY(std::any_of(actions.cbegin(), actions.cend(), [](const QAction* action) {
            return action->text() == i18n("Restore");
        }));
        if (locale == QStringLiteral("ro")) {
            QCOMPARE(view.windowTitle(), QString::fromUtf8("Tranzacții ciornă"));
            QCOMPARE(i18n("Restore"), QString::fromUtf8("Restaurează"));
            QCOMPARE(errorText, QString::fromUtf8("Nu se pot citi ciornele: synthetic-error"));
        }
        try {
            DraftTransactions::decode(QStringLiteral("invalid-json"));
            QFAIL("Invalid JSON must be rejected");
        } catch (const MyMoneyException& error) {
            QVERIFY(QString::fromUtf8(error.what()).contains(i18n("Draft metadata is not valid JSON.")));
        }
    }
};

QTEST_MAIN(DraftTranslationTest)
#include "drafttranslationtest.moc"
