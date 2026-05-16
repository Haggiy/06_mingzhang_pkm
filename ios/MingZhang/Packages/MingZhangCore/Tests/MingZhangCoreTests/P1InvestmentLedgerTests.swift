import Foundation
import GRDB
import XCTest
@testable import MingZhangCore

final class P1InvestmentLedgerTests: XCTestCase {
    func testInvestmentSchemaStartsEmptyAndSeedsInvestmentCategories() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        XCTAssertTrue(try useCases.queryInvestmentTransactions(fundName: nil).isEmpty)
        XCTAssertTrue(try useCases.queryInvestmentHoldings(accountMonth: "2026-04").isEmpty)

        let types = try useCases.queryPaymentTypes()
        let details = try useCases.queryPaymentDetails()
        XCTAssertEqual(types.first { $0.name == "资产类支出" }?.element, .asset)
        XCTAssertEqual(types.first { $0.name == "理财收入" }?.element, .income)
        XCTAssertEqual(types.first { $0.name == "财务费用开支" }?.element, .expense)
        XCTAssertNotNil(details.first { $0.name == "金融资产投资" })
        XCTAssertNotNil(details.first { $0.name == "投资收益" })
        XCTAssertNotNil(details.first { $0.name == "投资亏损" })
    }

    func testAverageCostCalculatesSellBookAmountAndLoss() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        _ = try useCases.createInvestmentTransaction(input: investmentInput(
            accountMonth: "2026-03",
            occurredAt: "2026-03-10T00:00:00Z",
            type: .buy,
            amount: Decimal(300),
            share: Decimal(200),
            nav: Decimal(string: "1.50")!,
            note: "起始买入"
        ))
        let sell = try useCases.createInvestmentTransaction(input: investmentInput(
            accountMonth: "2026-04",
            occurredAt: "2026-04-10T00:00:00Z",
            type: .sell,
            amount: Decimal(-120),
            share: Decimal(-100),
            note: "赎回"
        ))

        let transactions = try useCases.queryInvestmentTransactions(fundName: "沪深300指数A")
        let calculatedSell = try XCTUnwrap(transactions.first { $0.id == sell.id })
        XCTAssertEqual(calculatedSell.bookAmount, Decimal(-150))
        XCTAssertEqual(calculatedSell.realizedGain, Decimal(0))
        XCTAssertEqual(calculatedSell.realizedLoss, Decimal(30))
        XCTAssertEqual(calculatedSell.holdingShare, Decimal(100))
        XCTAssertEqual(calculatedSell.averageCost, Decimal(string: "1.50")!)
        XCTAssertEqual(calculatedSell.bookValue, Decimal(150))
    }

    func testInvestmentSellCreatesFeedRecordsAndRecalculatesCashAndInvestmentAsset() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        _ = try useCases.createInvestmentTransaction(input: investmentInput(
            accountMonth: "2026-03",
            occurredAt: "2026-03-10T00:00:00Z",
            type: .buy,
            amount: Decimal(300),
            share: Decimal(200),
            nav: Decimal(string: "1.50")!
        ))
        let sell = try useCases.createInvestmentTransaction(input: investmentInput(
            accountMonth: "2026-04",
            occurredAt: "2026-04-10T00:00:00Z",
            type: .sell,
            amount: Decimal(-120),
            share: Decimal(-100),
            note: "赎回"
        ))

        let feedRecords = try useCases.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-04"], includeEngineRecords: true)
        ).filter { $0.recordSource == .investmentFeed }

        XCTAssertEqual(feedRecords.count, 2)
        let sellCost = try XCTUnwrap(feedRecords.first { $0.paymentDetailName == "金融资产投资" })
        XCTAssertEqual(sellCost.amount, Decimal(-150))
        XCTAssertEqual(sellCost.paymentTypeName, "资产类支出")
        XCTAssertEqual(sellCost.sourceInvestmentTransactionIds, [sell.id])

        let loss = try XCTUnwrap(feedRecords.first { $0.paymentDetailName == "投资亏损" })
        XCTAssertEqual(loss.amount, Decimal(30))
        XCTAssertEqual(loss.paymentTypeName, "财务费用开支")
        XCTAssertEqual(loss.sourceInvestmentTransactionIds, [sell.id])

        let home = try useCases.queryHomeSummary(accountMonth: "2026-04")
        XCTAssertEqual(home.expenseTotal, Decimal(30))

        let balance = try useCases.queryBalanceSummary(accountMonth: "2026-04")
        XCTAssertEqual(balance.cashBalance, Decimal(120))
        XCTAssertEqual(balance.investmentItems, [
            BalanceItem(name: "总投资资产", amount: Decimal(150), sourceRecordIds: [])
        ])
    }

    func testUpdatingAndDeletingInvestmentTransactionReplacesAffectedMonthlyFeeds() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        _ = try useCases.createInvestmentTransaction(input: investmentInput(
            accountMonth: "2026-03",
            occurredAt: "2026-03-10T00:00:00Z",
            type: .buy,
            amount: Decimal(300),
            share: Decimal(200)
        ))
        let sell = try useCases.createInvestmentTransaction(input: investmentInput(
            accountMonth: "2026-04",
            occurredAt: "2026-04-10T00:00:00Z",
            type: .sell,
            amount: Decimal(-120),
            share: Decimal(-100)
        ))

        _ = try useCases.updateInvestmentTransaction(
            id: sell.id,
            changes: InvestmentTransactionChanges(tradeAmount: Decimal(-180), tradeShare: Decimal(-100))
        )
        var feedRecords = try useCases.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-04"], includeEngineRecords: true)
        ).filter { $0.recordSource == .investmentFeed }

        XCTAssertEqual(feedRecords.count, 2)
        XCTAssertEqual(feedRecords.first { $0.paymentDetailName == "金融资产投资" }?.amount, Decimal(-150))
        XCTAssertEqual(feedRecords.first { $0.paymentDetailName == "投资收益" }?.amount, Decimal(30))
        XCTAssertNil(feedRecords.first { $0.paymentDetailName == "投资亏损" })

        try useCases.deleteInvestmentTransaction(id: sell.id)
        feedRecords = try useCases.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-04"], includeEngineRecords: true)
        ).filter { $0.recordSource == .investmentFeed }
        XCTAssertTrue(feedRecords.isEmpty)
        XCTAssertEqual(try useCases.queryBalanceSummary(accountMonth: "2026-04").investmentItems.first?.amount, Decimal(300))
    }

    func testInvestmentReadModelsAndFeedTraceExposeSourceTransactions() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let buy = try useCases.createInvestmentTransaction(input: investmentInput(
            accountMonth: "2026-03",
            occurredAt: "2026-03-10T00:00:00Z",
            type: .buy,
            amount: Decimal(300),
            share: Decimal(200),
            nav: Decimal(string: "1.50")!
        ))
        let sell = try useCases.createInvestmentTransaction(input: investmentInput(
            accountMonth: "2026-04",
            occurredAt: "2026-04-10T00:00:00Z",
            type: .sell,
            amount: Decimal(-180),
            share: Decimal(-100)
        ))
        _ = try useCases.createInvestmentTransaction(input: investmentInput(
            accountMonth: "2026-04",
            occurredAt: "2026-04-30T00:00:00Z",
            type: .nav,
            nav: Decimal(string: "1.80")!,
            note: "月末净值"
        ))

        let holdings = try useCases.queryInvestmentHoldings(accountMonth: "2026-04")
        XCTAssertEqual(holdings.map(\.fundName), ["沪深300指数A"])
        XCTAssertEqual(holdings.first?.holdingShare, Decimal(100))
        XCTAssertEqual(holdings.first?.bookValue, Decimal(150))
        XCTAssertEqual(holdings.first?.presentValue, Decimal(180))
        XCTAssertEqual(holdings.first?.unrealizedGain, Decimal(30))
        XCTAssertEqual(holdings.first?.sourceTransactionIds.sorted { $0.uuidString < $1.uuidString }, [buy.id, sell.id].sorted { $0.uuidString < $1.uuidString })

        let summary = try useCases.queryInvestmentMonthlySummary(accountMonth: "2026-04", fundName: "沪深300指数A")
        XCTAssertEqual(summary.sellBookAmount, Decimal(-150))
        XCTAssertEqual(summary.realizedGain, Decimal(30))
        XCTAssertEqual(summary.realizedLoss, Decimal(0))
        XCTAssertEqual(summary.endingBookValue, Decimal(150))

        let feed = try XCTUnwrap(try useCases.queryInvestmentFeedRecords(accountMonth: "2026-04", fundName: "沪深300指数A").first)
        let trace = try XCTUnwrap(try useCases.getInvestmentFeedTrace(recordId: feed.id))
        XCTAssertEqual(trace.transactions.map(\.id), [sell.id])
    }
}

private func investmentInput(
    accountMonth: String = "2026-04",
    occurredAt: String = "2026-04-15T00:00:00Z",
    fundName: String = "沪深300指数A",
    type: InvestmentTransactionType,
    amount: Decimal? = nil,
    share: Decimal? = nil,
    nav: Decimal? = nil,
    note: String? = nil
) throws -> CreateInvestmentTransactionInput {
    CreateInvestmentTransactionInput(
        accountMonth: accountMonth,
        occurredAt: try Date.iso8601(occurredAt),
        fundName: fundName,
        transactionType: type,
        tradeAmount: amount,
        tradeShare: share,
        nav: nav,
        note: note
    )
}

private extension Date {
    static func iso8601(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw MingZhangError.invalidDate(value)
        }
        return date
    }
}
