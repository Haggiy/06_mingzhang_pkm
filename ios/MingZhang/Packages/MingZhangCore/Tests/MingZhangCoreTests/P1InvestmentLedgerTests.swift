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
}
