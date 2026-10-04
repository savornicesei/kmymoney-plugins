// SPDX-License-Identifier: GPL-2.0-or-later
#include "draftservice.h"
#include "draftcodec.h"
#include "draftsview.h"
#include <algorithm>
#include <memory>

#include <KActionCollection>
#include <KLocalizedString>
#include <KPluginFactory>
#include <KPluginMetaData>
#include <QAction>
#include <QApplication>
#include <QDateEdit>
#include <QDomDocument>
#include <QFile>
#include <QJsonDocument>
#include <QSignalSpy>
#include <QTableWidget>
#include <QTest>
#include <QTimer>
#include <QUndoStack>
#include <QUuid>
#include <kmymoneyplugin.h>
#include <mymoneyaccount.h>
#include <mymoneyenums.h>
#include <mymoneyexception.h>
#include <mymoneyfile.h>
#include <mymoneymoney.h>
#include <mymoneypayee.h>
#include <mymoneysecurity.h>
#include <mymoneysplit.h>
#include <mymoneytag.h>
#include <parametersmodel.h>
#ifdef DRAFT_HOST_STORAGE_TESTS
#include <QBuffer>
#include <QSqlQuery>
#include <QTemporaryDir>
#include <QUrlQuery>
#include <mymoneystoragesql.h>
#include <mymoneyxmlreader.h>
#include <mymoneyxmlwriter.h>
#endif

using namespace DraftTransactions;

class DraftServiceTest : public QObject
{
    Q_OBJECT
private:
    MyMoneyFile* m_file = MyMoneyFile::instance();
    DraftService m_service;
    QString m_bank;
    QString m_savings;
    QString m_expense;
    QString m_payee;
    QString m_tag;

    MyMoneyTransaction fixture() const
    {
        MyMoneyTransaction transaction;
        transaction.setPostDate(QDate(2020, 2, 15));
        transaction.setEntryDate(QDate(2020, 3, 1));
        transaction.setCommodity(QStringLiteral("USD"));
        transaction.setMemo(QString::fromUtf8("Synthetic café <memo> & \"quotes\"\nsecond line"));
        transaction.setBankID(QStringLiteral("legacy-bank-id"));
        transaction.setValue(QStringLiteral("custom/transaction"), QStringLiteral("retained"));
        const QStringList accounts{m_bank, m_savings, m_expense};
        const QStringList amounts{QStringLiteral("-12345/100"), QStringLiteral("100/1"), QStringLiteral("2345/100")};
        for (int index = 0; index < accounts.size(); ++index) {
            MyMoneySplit split;
            split.setAccountId(accounts[index]);
            split.setPayeeId(m_payee);
            split.setTagIdList({m_tag});
            split.setValue(MyMoneyMoney(amounts[index]));
            split.setShares(MyMoneyMoney(amounts[index]));
            split.setPrice(MyMoneyMoney(QStringLiteral("1/1")));
            split.setMemo(QStringLiteral("split %1").arg(index));
            split.setNumber(QStringLiteral("ref-%1").arg(index));
            split.setBankID(QStringLiteral("bank-%1").arg(index));
            split.setReconcileFlag(eMyMoney::Split::State::Reconciled);
            split.setReconcileDate(QDate(2020, 4, 1));
            split.setValue(QStringLiteral("custom/split"), QStringLiteral("preserve & <>"));
            transaction.addSplit(split);
        }
        return transaction;
    }

    MyMoneyTransaction addFixture()
    {
        auto transaction = fixture();
        MyMoneyFileTransaction operation;
        m_file->addTransaction(transaction);
        operation.commit();
        return m_file->transaction(transaction.id());
    }

    DraftRecord moveFixture()
    {
        const auto transaction = addFixture();
        m_service.move({{transaction.id(), transaction.splits().first().id()}});
        return m_service.records().first();
    }

private Q_SLOTS:
    void initTestCase()
    {
        KLocalizedString::setApplicationDomain("drafttransactions");
    }
    void init()
    {
        KLocalizedString::setLanguages({QStringLiteral("en_US")});
        m_file->unload();
        MyMoneyFileTransaction operation;
        MyMoneySecurity currency(QStringLiteral("USD"), QStringLiteral("US dollar"), QStringLiteral("$"));
        m_file->addCurrency(currency);
        m_file->setBaseCurrency(currency);
        auto asset = m_file->asset();
        auto expense = m_file->expense();
        MyMoneyAccount bank;
        bank.setName(QStringLiteral("Synthetic checking"));
        bank.setAccountType(eMyMoney::Account::Type::Checkings);
        bank.setCurrencyId(currency.id());
        m_file->addAccount(bank, asset);
        m_bank = bank.id();
        MyMoneyAccount savings;
        savings.setName(QStringLiteral("Synthetic savings"));
        savings.setAccountType(eMyMoney::Account::Type::Savings);
        savings.setCurrencyId(currency.id());
        m_file->addAccount(savings, asset);
        m_savings = savings.id();
        MyMoneyAccount category;
        category.setName(QStringLiteral("Synthetic expense"));
        category.setAccountType(eMyMoney::Account::Type::Expense);
        category.setCurrencyId(currency.id());
        m_file->addAccount(category, expense);
        m_expense = category.id();
        MyMoneyPayee payee;
        payee.setName(QStringLiteral("Synthetic payee"));
        m_file->addPayee(payee);
        m_payee = payee.id();
        MyMoneyTag tag;
        tag.setName(QStringLiteral("Synthetic tag"));
        m_file->addTag(tag);
        m_tag = tag.id();
        operation.commit();
    }

    void cleanup()
    {
        m_file->unload();
    }

    void codecPreservesCompleteMatchedTransaction()
    {
        auto original = addFixture();
        auto match = fixture();
        match.setImported(true);
        original.splits()[0].addMatch(match);
        original.splits()[1].setReconcileFlag(eMyMoney::Split::State::Frozen);
        DraftRecord record;
        record.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
        record.created = QDateTime::currentDateTimeUtc();
        record.originSplitId = original.splits().first().id();
        record.transaction = original;
        const auto decoded = decode(encode(record));
        QCOMPARE(transactionObject(decoded.transaction), transactionObject(original));
        QCOMPARE(decoded.transaction.splits().first().bankID(), QStringLiteral("bank-0"));
        QVERIFY(decoded.transaction.splits().first().isMatched());
        QCOMPARE(transactionObject(decoded.transaction.splits().first().matchedTransaction()), transactionObject(match));
        QCOMPARE(decoded.transaction.splits()[1].reconcileFlag(), eMyMoney::Split::State::Frozen);
    }

    void corruptAndFuturePayloadsAreRejected()
    {
        const auto record = moveFixture();
        const auto payload = encode(record);
        auto corrupt = QJsonDocument::fromJson(payload.toUtf8()).object();
        auto content = corrupt.value("content").toObject();
        content.insert(QStringLiteral("originSplit"), QStringLiteral("changed"));
        corrupt.insert(QStringLiteral("content"), content);
        QVERIFY_EXCEPTION_THROWN(decode(QString::fromUtf8(QJsonDocument(corrupt).toJson())), MyMoneyException);
        auto future = QJsonDocument::fromJson(payload.toUtf8()).object();
        future.insert(QStringLiteral("version"), 2);
        MyMoneyFileTransaction operation;
        m_file->setValue(DraftService::keyPrefix() + record.id, QString::fromUtf8(QJsonDocument(future).toJson()));
        operation.commit();
        QVERIFY_EXCEPTION_THROWN(m_service.restore(record.id, QDate(2021, 1, 1)), MyMoneyException);
        QCOMPARE(m_file->transactionCount(), 0U);
        QCOMPARE(m_file->value(DraftService::keyPrefix() + record.id), QString::fromUtf8(QJsonDocument(future).toJson()));
    }

    void moveExcludesEverySplitAndDeduplicatesSelection()
    {
        const auto transaction = addFixture();
        QCOMPARE(m_file->balance(m_bank), MyMoneyMoney(QStringLiteral("-12345/100")));
        m_service.move({{transaction.id(), transaction.splits()[0].id()}, {transaction.id(), transaction.splits()[1].id()}});
        QCOMPARE(m_file->transactionCount(), 0U);
        QCOMPARE(m_service.records().size(), 1);
        QCOMPARE(transactionObject(m_service.records().first().transaction), transactionObject(transaction));
        QCOMPARE(m_file->balance(m_bank), MyMoneyMoney());
        QCOMPARE(m_file->balance(m_savings), MyMoneyMoney());
        QCOMPARE(m_file->balance(m_expense), MyMoneyMoney());
        QVERIFY(m_file->dirty());
    }

    void moveAndRestoreSupportUndoRedo()
    {
        const auto transaction = addFixture();
        m_service.move({{transaction.id(), transaction.splits().first().id()}});
        const auto record = m_service.records().first();
        m_file->undoStack()->undo();
        QVERIFY(m_service.records().isEmpty());
        QCOMPARE(transactionObject(m_file->transaction(transaction.id())), transactionObject(transaction));
        m_file->undoStack()->redo();
        QCOMPARE(m_service.records().size(), 1);
        QCOMPARE(m_file->transactionCount(), 0U);
        const auto restoredId = m_service.restore(record.id, QDate(2022, 2, 2));
        m_file->undoStack()->undo();
        QVERIFY(m_service.records().first().restoredId.isEmpty());
        QCOMPARE(m_file->transactionCount(), 0U);
        m_file->undoStack()->redo();
        QCOMPARE(m_file->transaction(restoredId).postDate(), QDate(2022, 2, 2));
        QCOMPARE(m_service.records().first().restoredId, restoredId);
    }

    void restoreChangesOnlyDateAndIdentityAndRetainsCopyUntilSaved()
    {
        const auto record = moveFixture();
        const QDate date(2021, 7, 10);
        const auto id = m_service.restore(record.id, date);
        QVERIFY(id != record.transaction.id());
        auto expected = MyMoneyTransaction(id, record.transaction);
        expected.setPostDate(date);
        QCOMPARE(transactionObject(m_file->transaction(id)), transactionObject(expected));
        QCOMPARE(m_file->balance(m_bank), MyMoneyMoney(QStringLiteral("-12345/100")));
        QCOMPARE(m_file->balance(m_savings), MyMoneyMoney(QStringLiteral("100/1")));
        QCOMPARE(m_file->balance(m_expense), MyMoneyMoney(QStringLiteral("2345/100")));
        QCOMPARE(m_service.records().first().restoredId, id);
        QCOMPARE(m_service.completeSavedRestores(), 0);
        QVERIFY_EXCEPTION_THROWN(m_service.restore(record.id, date), MyMoneyException);
        QCOMPARE(m_file->transactionCount(), 1U);
        // Engine-level test only: the public method marks all models clean.
        // Storage integration tests must establish actual persistence separately.
        m_file->fileSaved();
        QCOMPARE(m_service.completeSavedRestores(), 1);
        QVERIFY(m_service.records().isEmpty());
        QCOMPARE(transactionObject(m_file->transaction(id)), transactionObject(expected));
        QVERIFY(m_file->dirty()); // cleanup awaits the next normal document save
    }

    void editedRestorationRetainsRecoveryCopy()
    {
        const auto record = moveFixture();
        const auto id = m_service.restore(record.id, record.transaction.postDate());
        auto changed = m_file->transaction(id);
        changed.setMemo(QStringLiteral("Changed after restoration"));
        MyMoneyFileTransaction operation;
        m_file->modifyTransaction(changed);
        operation.commit();
        m_file->fileSaved();
        QCOMPARE(m_service.completeSavedRestores(), 0);
        QCOMPARE(m_service.records().first().restoredId, id);
        QCOMPARE(m_file->transactionCount(), 1U);
    }

    void nativeTransactionVariantsRoundTrip_data()
    {
        QTest::addColumn<QString>("kind");
        QTest::newRow("multi-currency") << QStringLiteral("currency");
        QTest::newRow("investment") << QStringLiteral("investment");
        QTest::newRow("loan") << QStringLiteral("loan");
        QTest::newRow("matched-import") << QStringLiteral("match");
        QTest::newRow("frozen") << QStringLiteral("frozen");
    }

    void nativeTransactionVariantsRoundTrip()
    {
        QFETCH(QString, kind);
        auto transaction = fixture();
        {
            MyMoneyFileTransaction operation;
            if (kind == QStringLiteral("currency")) {
                MyMoneySecurity euro(QStringLiteral("EUR"), QStringLiteral("Euro"), QStringLiteral("EUR"));
                m_file->addCurrency(euro);
                auto savings = m_file->account(m_savings);
                savings.setCurrencyId(euro.id());
                m_file->modifyAccount(savings);
                transaction.splits()[1].setShares(MyMoneyMoney(QStringLiteral("9123/100")));
                transaction.splits()[1].setPrice(MyMoneyMoney(QStringLiteral("10000/9123")));
            } else if (kind == QStringLiteral("investment")) {
                MyMoneySecurity stock;
                stock.setName(QStringLiteral("Synthetic stock"));
                stock.setSecurityType(eMyMoney::Security::Type::Stock);
                stock.setTradingCurrency(QStringLiteral("USD"));
                stock.setSmallestAccountFraction(10000);
                m_file->addSecurity(stock);
                auto asset = m_file->asset();
                MyMoneyAccount investment;
                investment.setName(QStringLiteral("Synthetic investments"));
                investment.setAccountType(eMyMoney::Account::Type::Investment);
                investment.setCurrencyId(QStringLiteral("USD"));
                m_file->addAccount(investment, asset);
                MyMoneyAccount holding;
                holding.setName(QStringLiteral("Synthetic holding"));
                holding.setAccountType(eMyMoney::Account::Type::Stock);
                holding.setCurrencyId(stock.id());
                m_file->addAccount(holding, investment);
                transaction.splits()[1].setAccountId(holding.id());
                transaction.splits()[1].setShares(MyMoneyMoney(QStringLiteral("3/1")));
                transaction.splits()[1].setPrice(MyMoneyMoney(QStringLiteral("100/3")));
                transaction.splits()[1].setAction(QStringLiteral("Buy"));
            } else if (kind == QStringLiteral("loan")) {
                auto liability = m_file->liability();
                MyMoneyAccount loan;
                loan.setName(QStringLiteral("Synthetic loan"));
                loan.setAccountType(eMyMoney::Account::Type::Loan);
                loan.setCurrencyId(QStringLiteral("USD"));
                m_file->addAccount(loan, liability);
                transaction.splits()[1].setAccountId(loan.id());
                transaction.splits()[1].setAction(QStringLiteral("Transfer"));
            } else if (kind == QStringLiteral("match")) {
                auto imported = fixture();
                imported.setImported(true);
                transaction.splits()[0].addMatch(imported);
            } else {
                transaction.splits()[0].setReconcileFlag(eMyMoney::Split::State::Frozen);
            }
            m_file->addTransaction(transaction);
            operation.commit();
        }
        const auto original = m_file->transaction(transaction.id());
        m_service.move({{original.id(), original.splits().first().id()}});
        QCOMPARE(m_file->transactionCount(), 0U);
        QCOMPARE(transactionObject(m_service.records().first().transaction), transactionObject(original));
        const auto id = m_service.restore(m_service.records().first().id, original.postDate());
        QCOMPARE(transactionObject(m_file->transaction(id)), transactionObject(MyMoneyTransaction(id, original)));
        QCOMPARE(m_file->transactionCount(), 1U);
    }

    void closedAccountAndInvalidBatchLeaveBothStoresUnchanged()
    {
        const auto transaction = addFixture();
        QVERIFY_EXCEPTION_THROWN(m_service.move({{transaction.id(), transaction.splits().first().id()}, {QStringLiteral("missing"), QStringLiteral("S0001")}}),
                                 MyMoneyException);
        QVERIFY(m_service.records().isEmpty());
        QCOMPARE(transactionObject(m_file->transaction(transaction.id())), transactionObject(transaction));
        // Closing an account is only permitted at a zero balance. Add a real
        // offsetting transaction rather than bypassing the host restriction.
        auto offset = fixture();
        for (auto& split : offset.splits()) {
            split.setValue(-split.value());
            split.setShares(-split.shares());
        }
        {
            MyMoneyFileTransaction balanceOperation;
            m_file->addTransaction(offset);
            balanceOperation.commit();
        }
        auto account = m_file->account(m_savings);
        account.setClosed(true);
        MyMoneyFileTransaction operation;
        m_file->modifyAccount(account);
        operation.commit();
        QVERIFY_EXCEPTION_THROWN(m_service.move({{transaction.id(), transaction.splits().first().id()}}), MyMoneyException);
        QVERIFY(m_service.records().isEmpty());
        QCOMPARE(m_file->transactionCount(), 2U);
    }

    void missingReferenceAndInvalidDateKeepDraft()
    {
        const auto record = moveFixture();
        const auto payload = m_file->value(DraftService::keyPrefix() + record.id);
        QVERIFY_EXCEPTION_THROWN(m_service.restore(record.id, QDate()), MyMoneyException);
        MyMoneyFileTransaction operation;
        m_file->removePayee(m_file->payee(m_payee));
        operation.commit();
        QVERIFY_EXCEPTION_THROWN(m_service.restore(record.id, record.transaction.postDate()), MyMoneyException);
        QCOMPARE(m_file->transactionCount(), 0U);
        QCOMPARE(m_file->value(DraftService::keyPrefix() + record.id), payload);
    }

    void unexpectedHostNormalizationRollsBackRestoration()
    {
        auto record = moveFixture();
        // A valid archive with precision the current account cannot represent.
        record.transaction.splits()[0].setValue(MyMoneyMoney(QStringLiteral("-123456/1000")));
        MyMoneyFileTransaction operation;
        const auto payload = encode(record);
        m_file->setValue(DraftService::keyPrefix() + record.id, payload);
        operation.commit();
        QVERIFY_EXCEPTION_THROWN(m_service.restore(record.id, record.transaction.postDate()), MyMoneyException);
        QCOMPARE(m_file->transactionCount(), 0U);
        QCOMPARE(m_file->value(DraftService::keyPrefix() + record.id), payload);
        QVERIFY(m_service.records().first().restoredId.isEmpty());
        QVERIFY(!m_file->undoStack()->canRedo());
        m_file->undoStack()->redo();
        QCOMPARE(m_file->transactionCount(), 0U);
    }

    void documentMetadataRoundTripKeepsDraftIndependentOfPlugin()
    {
        const auto record = moveFixture();
        const auto parameters = m_file->parametersModel()->pairs();
        m_file->unload();
        // The storage adapters populate this same public host model on load.
        m_file->parametersModel()->load(parameters);
        const auto reloaded = m_service.records().first();
        QCOMPARE(reloaded.id, record.id);
        QCOMPARE(transactionObject(reloaded.transaction), transactionObject(record.transaction));
        QCOMPARE(m_file->transactionCount(), 0U);
    }

    void pluginLoadsWithRequestedMenuActions()
    {
        const KPluginMetaData metadata(QStringLiteral(DRAFT_PLUGIN_FILE));
        QCOMPARE(metadata.name(), QStringLiteral("Draft transactions"));
        auto result = KPluginFactory::instantiatePlugin<KMyMoneyPlugin::Plugin>(metadata);
        QVERIFY2(result.plugin, qPrintable(result.errorString));
        std::unique_ptr<KMyMoneyPlugin::Plugin> plugin(result.plugin);
        QVERIFY(plugin->actionCollection()->action(QStringLiteral("drafts_show")));
        const auto* move = plugin->actionCollection()->action(QStringLiteral("transaction_move_to_drafts"));
        QVERIFY(move);
        QCOMPARE(move->text(), QStringLiteral("Move to drafts"));
        QVERIFY(!move->isEnabled());
        const auto xml = plugin->domDocument();
        QVERIFY(!xml.isNull());
        QCOMPARE(xml.documentElement().attribute(QStringLiteral("translationDomain")), QStringLiteral("drafttransactions"));
        const auto menus = xml.elementsByTagName(QStringLiteral("Menu"));
        bool draftsMenu = false;
        bool separatedContextAction = false;
        for (int index = 0; index < menus.size(); ++index) {
            const auto menu = menus.at(index).toElement();
            if (menu.attribute(QStringLiteral("name")) == QStringLiteral("drafts"))
                draftsMenu = menu.firstChildElement(QStringLiteral("text")).text() == QStringLiteral("Drafts");
            if (menu.attribute(QStringLiteral("name")) == QStringLiteral("transaction_context_menu")) {
                const auto action = menu.firstChildElement(QStringLiteral("Action"));
                separatedContextAction = action.attribute(QStringLiteral("name")) == QStringLiteral("transaction_move_to_drafts")
                    && action.previousSiblingElement().tagName() == QStringLiteral("Separator")
                    && action.nextSiblingElement().tagName() == QStringLiteral("Separator");
            }
        }
        QVERIFY(draftsMenu);
        QVERIFY(separatedContextAction);
    }

    void draftsViewFormatsAmountsAndHidesNonInvestmentFields()
    {
        const auto record = moveFixture();
        DraftsView view;
        view.refresh(true);
        const auto tables = view.findChildren<QTableWidget*>();
        QCOMPARE(tables.size(), 2);
        QCOMPARE(tables.first()->item(0, 4)->text(), QStringLiteral("-123.45"));
        tables.first()->selectRow(0);
        const QStringList amounts{QStringLiteral("-123.45"), QStringLiteral("100"), QStringLiteral("23.45")};
        for (int row = 0; row < amounts.size(); ++row) {
            QCOMPARE(tables.last()->item(row, 2)->text(), amounts[row]);
            QVERIFY(tables.last()->item(row, 3)->text().isEmpty());
            QVERIFY(tables.last()->item(row, 4)->text().isEmpty());
        }
        bool restoreAmountsMatch = false;
        QTimer::singleShot(0, [&restoreAmountsMatch, &amounts]() {
            auto* dialog = qobject_cast<QDialog*>(QApplication::activeModalWidget());
            if (!dialog)
                return;
            const auto tables = dialog->findChildren<QTableWidget*>();
            if (tables.size() == 1 && tables.first()->rowCount() == amounts.size()) {
                restoreAmountsMatch = true;
                for (int row = 0; row < amounts.size(); ++row) {
                    restoreAmountsMatch &= tables.first()->item(row, 2)->text() == amounts[row];
                    restoreAmountsMatch &= tables.first()->item(row, 3)->text().isEmpty();
                    restoreAmountsMatch &= tables.first()->item(row, 4)->text().isEmpty();
                }
            }
            dialog->reject();
        });
        QVERIFY(!chooseRestoreDate(record, &view).isValid());
        QVERIFY(restoreAmountsMatch);
        QCOMPARE(encode(m_service.records().first()), encode(record));
    }

    void draftsViewShowsInvestmentFieldsOnlyForInvestmentSplits()
    {
        auto transaction = fixture();
        {
            MyMoneyFileTransaction operation;
            MyMoneySecurity stock;
            stock.setName(QStringLiteral("Synthetic stock"));
            stock.setSecurityType(eMyMoney::Security::Type::Stock);
            stock.setTradingCurrency(QStringLiteral("USD"));
            stock.setSmallestAccountFraction(10000);
            m_file->addSecurity(stock);
            auto asset = m_file->asset();
            MyMoneyAccount investment;
            investment.setName(QStringLiteral("Synthetic investments"));
            investment.setAccountType(eMyMoney::Account::Type::Investment);
            investment.setCurrencyId(QStringLiteral("USD"));
            m_file->addAccount(investment, asset);
            MyMoneyAccount holding;
            holding.setName(QStringLiteral("Synthetic holding"));
            holding.setAccountType(eMyMoney::Account::Type::Stock);
            holding.setCurrencyId(stock.id());
            m_file->addAccount(holding, investment);
            transaction.splits()[1].setAccountId(holding.id());
            transaction.splits()[1].setShares(MyMoneyMoney(QStringLiteral("3/1")));
            transaction.splits()[1].setPrice(MyMoneyMoney(QStringLiteral("100/3")));
            transaction.splits()[1].setAction(QStringLiteral("Buy"));
            m_file->addTransaction(transaction);
            operation.commit();
        }
        m_service.move({{transaction.id(), transaction.splits().first().id()}});
        const auto record = m_service.records().first();
        DraftsView view;
        view.refresh(true);
        const auto tables = view.findChildren<QTableWidget*>();
        QCOMPARE(tables.size(), 2);
        tables.first()->selectRow(0);
        QCOMPARE(tables.last()->item(1, 2)->text(), QStringLiteral("100"));
        QCOMPARE(tables.last()->item(1, 3)->text(), QStringLiteral("3/1"));
        QCOMPARE(tables.last()->item(1, 4)->text(), QStringLiteral("100/3"));
        for (const int row : {0, 2}) {
            QVERIFY(tables.last()->item(row, 3)->text().isEmpty());
            QVERIFY(tables.last()->item(row, 4)->text().isEmpty());
        }
        QCOMPARE(encode(m_service.records().first()), encode(record));
    }

    void draftsViewIsReadOnlyAndRestoreDialogEditsOnlyDate()
    {
        const auto record = moveFixture();
        DraftsView view;
        view.refresh(true);
        const auto tables = view.findChildren<QTableWidget*>();
        QCOMPARE(tables.size(), 2);
        for (auto* table : tables) {
            QCOMPARE(table->editTriggers(), QAbstractItemView::NoEditTriggers);
            QCOMPARE(table->dragDropMode(), QAbstractItemView::NoDragDrop);
        }
        QCOMPARE(tables.first()->rowCount(), 1);
        tables.first()->selectRow(0);
        QCOMPARE(tables.last()->rowCount(), 3);
        QSignalSpy restoreRequested(&view, &DraftsView::restoreRequested);
        auto actions = view.findChildren<QAction*>();
        auto restore = std::find_if(actions.cbegin(), actions.cend(), [](auto* action) {
            return action->text() == QStringLiteral("Restore");
        });
        QVERIFY(restore != actions.cend());
        (*restore)->trigger();
        QCOMPARE(restoreRequested.size(), 1);
        QCOMPARE(restoreRequested.first().first().toString(), record.id);
        bool onlyDateEditable = false;
        QTimer::singleShot(0, [&onlyDateEditable]() {
            auto* dialog = qobject_cast<QDialog*>(QApplication::activeModalWidget());
            if (!dialog)
                return;
            const auto dates = dialog->findChildren<QDateEdit*>();
            onlyDateEditable = dates.size() == 1;
            for (auto* table : dialog->findChildren<QTableWidget*>())
                onlyDateEditable &= table->editTriggers() == QAbstractItemView::NoEditTriggers;
            if (dates.size() == 1)
                dates.first()->setDate(QDate(2024, 8, 9));
            dialog->accept();
        });
        QCOMPARE(chooseRestoreDate(record, &view), QDate(2024, 8, 9));
        QVERIFY(onlyDateEditable);
        QTimer::singleShot(0, []() {
            if (auto* dialog = qobject_cast<QDialog*>(QApplication::activeModalWidget()))
                dialog->reject();
        });
        QVERIFY(!chooseRestoreDate(record, &view).isValid());
        QCOMPARE(encode(m_service.records().first()), encode(record));
        QCOMPARE(m_file->transactionCount(), 0U);
    }

#ifdef DRAFT_HOST_STORAGE_TESTS
    void stockXmlSaveReopenAndBackupPreserveDrafts()
    {
        const auto record = moveFixture();
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const auto path = directory.filePath(QStringLiteral("synthetic.kmy"));
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        MyMoneyXmlWriter writer;
        writer.setFile(m_file);
        QVERIFY2(writer.write(&file), qPrintable(writer.errorString()));
        file.close();
        QVERIFY(QFile::copy(path, path + QStringLiteral(".backup")));
        m_file->unload();
        QVERIFY(file.open(QIODevice::ReadOnly));
        MyMoneyXmlReader reader;
        reader.setFile(m_file);
        QVERIFY2(reader.read(&file), qPrintable(reader.errorString()));
        file.close();
        QCOMPARE(m_service.records().size(), 1);
        QCOMPARE(transactionObject(m_service.records().first().transaction), transactionObject(record.transaction));
        QCOMPARE(m_file->transactionCount(), 0U);
        // Save again using only stock storage code, with no plugin callbacks.
        QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
        QVERIFY(writer.write(&file));
        file.close();
        m_file->unload();
        QVERIFY(file.open(QIODevice::ReadOnly));
        QVERIFY(reader.read(&file));
        file.close();
        QCOMPARE(m_service.records().first().id, record.id);
        m_file->unload();
        QFile backup(path + QStringLiteral(".backup"));
        QVERIFY(backup.open(QIODevice::ReadOnly));
        QVERIFY(reader.read(&backup));
        QCOMPARE(transactionObject(m_service.records().first().transaction), transactionObject(record.transaction));
    }

    void stockSqlAndXmlConversionPreserveDrafts()
    {
        const auto record = moveFixture();
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        auto url = QUrl::fromLocalFile(directory.filePath(QStringLiteral("synthetic.sqlite")));
        url.setScheme(QStringLiteral("sql"));
        QUrlQuery query;
        query.addQueryItem(QStringLiteral("driver"), QStringLiteral("QSQLITE"));
        url.setQuery(query);
        {
            MyMoneyStorageSql storage(m_file, url);
            QCOMPARE(storage.open(url, QIODevice::WriteOnly), 0);
            QVERIFY2(storage.writeFile(), qPrintable(storage.lastError()));
            QSqlQuery stored(storage);
            QVERIFY(stored.exec(QStringLiteral("SELECT kvpData FROM kmmKeyValuePairs WHERE kvpType='STORAGE' AND kvpKey LIKE 'draft-transactions/item/%'")));
            QVERIFY(stored.next());
            QCOMPARE(decode(stored.value(0).toString()).id, record.id);
            storage.close();
        }
        m_file->unload();
        {
            MyMoneyStorageSql storage(m_file, url);
            QCOMPARE(storage.open(url, QIODevice::ReadWrite), 0);
            QVERIFY2(storage.readFile(), qPrintable(storage.lastError()));
            QCOMPARE(transactionObject(m_service.records().first().transaction), transactionObject(record.transaction));
            QCOMPARE(m_file->transactionCount(), 0U);
            QVERIFY(storage.writeFile()); // stock save without DraftService involvement
            storage.close();
        }
        QByteArray xml;
        QBuffer buffer(&xml);
        QVERIFY(buffer.open(QIODevice::WriteOnly));
        MyMoneyXmlWriter writer;
        writer.setFile(m_file);
        QVERIFY(writer.write(&buffer));
        buffer.close();
        m_file->unload();
        QVERIFY(buffer.open(QIODevice::ReadOnly));
        MyMoneyXmlReader reader;
        reader.setFile(m_file);
        QVERIFY(reader.read(&buffer));
        QCOMPARE(transactionObject(m_service.records().first().transaction), transactionObject(record.transaction));
        const auto id = m_service.restore(record.id, QDate(2023, 5, 6));
        QVERIFY(!id.isEmpty());
        QCOMPARE(m_file->transaction(id).splitCount(), 3U);
    }

    void savedRestorationSurvivesRestartBeforeCleanup()
    {
        auto transaction = fixture();
        // Stock XML no longer persists the deprecated transaction-level bank ID.
        transaction.setBankID(QString());
        {
            MyMoneyFileTransaction operation;
            m_file->addTransaction(transaction);
            operation.commit();
        }
        m_service.move({{transaction.id(), transaction.splits().first().id()}});
        const auto record = m_service.records().first();
        const auto restoredId = m_service.restore(record.id, QDate(2024, 6, 7));
        QByteArray xml;
        QBuffer buffer(&xml);
        QVERIFY(buffer.open(QIODevice::WriteOnly));
        MyMoneyXmlWriter writer;
        writer.setFile(m_file);
        QVERIFY(writer.write(&buffer));
        buffer.close();
        m_file->unload();
        QVERIFY(buffer.open(QIODevice::ReadOnly));
        MyMoneyXmlReader reader;
        reader.setFile(m_file);
        QVERIFY(reader.read(&buffer));
        m_file->setDirty(false); // what the host does after a successful load
        QCOMPARE(m_service.records().first().restoredId, restoredId);
        QVERIFY_EXCEPTION_THROWN(m_service.restore(record.id, QDate(2024, 6, 7)), MyMoneyException);
        QCOMPARE(m_service.completeSavedRestores(), 1);
        QVERIFY(m_service.records().isEmpty());
        QCOMPARE(m_file->transactionCount(), 1U);
        QCOMPARE(m_file->transaction(restoredId).postDate(), QDate(2024, 6, 7));
    }

    void failedXmlWriteRetainsRecoveryCopyAndDurableDraft()
    {
        const auto record = moveFixture();
        QByteArray durableXml;
        QBuffer buffer(&durableXml);
        QVERIFY(buffer.open(QIODevice::WriteOnly));
        MyMoneyXmlWriter writer;
        writer.setFile(m_file);
        QVERIFY(writer.write(&buffer));
        buffer.close();
        const auto savedBytes = durableXml;
        m_file->setDirty(false);
        const auto id = m_service.restore(record.id, record.transaction.postDate());
        QVERIFY(buffer.open(QIODevice::ReadOnly));
        QVERIFY(!writer.write(&buffer));
        buffer.close();
        QCOMPARE(durableXml, savedBytes);
        QVERIFY(m_file->dirty());
        QCOMPARE(m_service.completeSavedRestores(), 0);
        QCOMPARE(m_service.records().first().restoredId, id);
        m_file->unload();
        QVERIFY(buffer.open(QIODevice::ReadOnly));
        MyMoneyXmlReader reader;
        reader.setFile(m_file);
        QVERIFY(reader.read(&buffer));
        QVERIFY(m_service.records().first().restoredId.isEmpty());
        QCOMPARE(transactionObject(m_service.records().first().transaction), transactionObject(record.transaction));
        QCOMPARE(m_file->transactionCount(), 0U);
    }

    void failedSqlSaveKeepsDurableDraftAndPendingRecovery()
    {
        const auto record = moveFixture();
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        auto url = QUrl::fromLocalFile(directory.filePath(QStringLiteral("failure.sqlite")));
        url.setScheme(QStringLiteral("sql"));
        QUrlQuery query;
        query.addQueryItem(QStringLiteral("driver"), QStringLiteral("QSQLITE"));
        url.setQuery(query);
        MyMoneyStorageSql storage(m_file, url);
        QCOMPARE(storage.open(url, QIODevice::WriteOnly), 0);
        QVERIFY(storage.writeFile());
        m_file->setDirty(false);
        const auto id = m_service.restore(record.id, record.transaction.postDate());
        QSqlQuery injectFailure(storage);
        QVERIFY(injectFailure.exec(
            QStringLiteral("CREATE TRIGGER reject_restore BEFORE INSERT ON kmmTransactions BEGIN SELECT RAISE(ABORT, 'synthetic save failure'); END")));
        bool failed = false;
        try {
            failed = !storage.writeFile();
        } catch (const MyMoneyException&) {
            failed = true;
        } catch (const QString&) {
            failed = true;
        }
        QVERIFY(failed);
        QVERIFY(m_file->dirty());
        QCOMPARE(m_service.completeSavedRestores(), 0);
        QCOMPARE(m_service.records().first().restoredId, id);
        QSqlQuery persisted(storage);
        QVERIFY(persisted.exec(QStringLiteral("SELECT kvpData FROM kmmKeyValuePairs WHERE kvpType='STORAGE' AND kvpKey LIKE 'draft-transactions/item/%'")));
        QVERIFY(persisted.next());
        QCOMPARE(encode(decode(persisted.value(0).toString())), encode(record));
        QVERIFY(persisted.exec(QStringLiteral("SELECT COUNT(*) FROM kmmTransactions")));
        QVERIFY(persisted.next());
        QCOMPARE(persisted.value(0).toInt(), 0);
    }
#endif
};

QTEST_MAIN(DraftServiceTest)
#include "draftservicetest.moc"
