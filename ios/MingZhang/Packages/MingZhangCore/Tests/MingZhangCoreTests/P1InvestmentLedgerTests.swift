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
