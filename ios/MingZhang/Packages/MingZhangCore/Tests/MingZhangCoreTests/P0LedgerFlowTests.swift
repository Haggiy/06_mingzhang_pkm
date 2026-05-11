import Foundation
import XCTest
@testable import MingZhangCore

final class P0LedgerFlowTests: XCTestCase {
    func testInitializeSeedIsIdempotent() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)

        try useCases.initializeLedgerSeed()
        try useCases.initializeLedgerSeed()

        let methods = try useCases.queryPaymentMethods()
        let types = try useCases.queryPaymentTypes()
        let details = try useCases.queryPaymentDetails()

        XCTAssertEqual(methods.map(\.name).sorted(), ["广发卡", "电子钱包余额", "账务处理"])
        XCTAssertEqual(methods.first { $0.name == "广发卡" }?.methodType, .liability)
        XCTAssertEqual(methods.first { $0.name == "电子钱包余额" }?.methodType, .asset)
        XCTAssertEqual(types.first { $0.name == "生活必要开支" }?.element, .expense)
        XCTAssertEqual(details.first { $0.name == "伙食费" }?.paymentTypeId, types.first { $0.name == "生活必要开支" }?.id)
    }

    func testCreditCardExpenseCreatesLiabilityAndRecalculates() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let record = try useCases.createManualRecord(
            input: sampleInput(amount: Decimal(100))
        )

        let visibleRecords = try useCases.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-04"])
        )
        XCTAssertEqual(visibleRecords.map(\.id), [record.id])

        var home = try useCases.queryHomeSummary(accountMonth: "2026-04")
        var balance = try useCases.queryBalanceSummary(accountMonth: "2026-04")
        var statistics = try useCases.queryStatisticsSummary(accountMonth: "2026-04")
        var engineRecords = try useCases.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-04"], includeEngineRecords: true)
        ).filter { $0.recordSource == .engine }

        XCTAssertEqual(home.expenseTotal, Decimal(100))
        XCTAssertEqual(home.incomeTotal, Decimal(0))
        XCTAssertEqual(home.balance, Decimal(-100))
        XCTAssertEqual(balance.cashBalance, Decimal(0))
        XCTAssertEqual(balance.liabilityItems, [
            BalanceItem(name: "广发卡", amount: Decimal(100), sourceRecordIds: [record.id])
        ])
        XCTAssertEqual(statistics.expenseByType["生活必要开支"], Decimal(100))
        XCTAssertEqual(statistics.sourceRecordIds, [record.id])
        XCTAssertEqual(engineRecords.count, 1)
        XCTAssertEqual(engineRecords.first?.amount, Decimal(100))
        XCTAssertEqual(engineRecords.first?.engineKey, "2026-04:liability:ending_balance:liability:广发卡")

        let updated = try useCases.updateJournalRecord(
            id: record.id,
            changes: JournalRecordChanges(amount: Decimal(120))
        )
        XCTAssertEqual(updated.amount, Decimal(120))

        home = try useCases.queryHomeSummary(accountMonth: "2026-04")
        balance = try useCases.queryBalanceSummary(accountMonth: "2026-04")
        statistics = try useCases.queryStatisticsSummary(accountMonth: "2026-04")
        engineRecords = try useCases.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-04"], includeEngineRecords: true)
        ).filter { $0.recordSource == .engine }

        XCTAssertEqual(home.expenseTotal, Decimal(120))
        XCTAssertEqual(balance.liabilityItems, [
            BalanceItem(name: "广发卡", amount: Decimal(120), sourceRecordIds: [record.id])
        ])
        XCTAssertEqual(statistics.expenseByType["生活必要开支"], Decimal(120))
        XCTAssertEqual(engineRecords.count, 1)
        XCTAssertEqual(engineRecords.first?.amount, Decimal(120))

        try useCases.deleteJournalRecord(id: record.id)

        home = try useCases.queryHomeSummary(accountMonth: "2026-04")
        balance = try useCases.queryBalanceSummary(accountMonth: "2026-04")
        statistics = try useCases.queryStatisticsSummary(accountMonth: "2026-04")
        engineRecords = try useCases.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-04"], includeEngineRecords: true)
        ).filter { $0.recordSource == .engine }

        XCTAssertEqual(home.expenseTotal, Decimal(0))
        XCTAssertTrue(balance.liabilityItems.isEmpty)
        XCTAssertTrue(statistics.expenseByType.isEmpty)
        XCTAssertTrue(engineRecords.isEmpty)
    }

    func testEngineRecordDoesNotTriggerEngineAgain() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let record = try useCases.createManualRecord(input: sampleInput(amount: Decimal(100)))
        let engineRecord = try XCTUnwrap(try useCases.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-04"], includeEngineRecords: true)
        ).first { $0.recordSource == .engine })

        let result = try useCases.recalculateAfterMutation(
            Mutation(recordId: engineRecord.id, mutationType: .update)
        )

        let engineRecords = try useCases.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-04"], includeEngineRecords: true)
        ).filter { $0.recordSource == .engine }

        XCTAssertTrue(result.recalculatedMonths.isEmpty)
        XCTAssertEqual(engineRecords.count, 1)
        XCTAssertEqual(engineRecords.first?.sourceRecordIds, [record.id])
    }

    private func sampleInput(amount: Decimal) throws -> CreateManualRecordInput {
        let occurredAt = try Date.iso8601("2026-04-15T12:30:00Z")

        return CreateManualRecordInput(
            accountMonth: "2026-04",
            occurredAt: occurredAt,
            paymentMethodName: "广发卡",
            amount: amount,
            paymentTypeName: "生活必要开支",
            paymentDetailName: "伙食费",
            note: "午餐"
        )
    }
}

private extension Date {
    static func iso8601(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw TestError.invalidDate(value)
        }
        return date
    }
}

private enum TestError: Error {
    case invalidDate(String)
}
