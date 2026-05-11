import Foundation
import GRDB
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
        XCTAssertEqual(statistics.expenseByType, [
            ExpenseTypeSummary(typeName: "生活必要开支", amount: Decimal(100), sourceRecordIds: [record.id])
        ])
        XCTAssertEqual(statistics.sourceRecordIds, [record.id])
        XCTAssertEqual(engineRecords.count, 1)
        XCTAssertEqual(engineRecords.first?.amount, Decimal(100))
        XCTAssertEqual(engineRecords.first?.engineKey, "2026-04:liability:ending_balance:liability:广发卡")
        let sourceRecords = try useCases.queryJournalRecords(
            recordIds: [record.id, try XCTUnwrap(engineRecords.first?.id)]
        )
        XCTAssertEqual(sourceRecords.map(\.id), [record.id])

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
        XCTAssertEqual(statistics.expenseByType, [
            ExpenseTypeSummary(typeName: "生活必要开支", amount: Decimal(120), sourceRecordIds: [record.id])
        ])
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

    func testCashExpenseReducesCashAssetAndRecalculates() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let record = try useCases.createManualRecord(
            input: sampleInput(paymentMethodName: "电子钱包余额", amount: Decimal(100))
        )

        var home = try useCases.queryHomeSummary(accountMonth: "2026-04")
        var balance = try useCases.queryBalanceSummary(accountMonth: "2026-04")
        var statistics = try useCases.queryStatisticsSummary(accountMonth: "2026-04")
        var engineRecords = try useCases.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-04"], includeEngineRecords: true)
        ).filter { $0.recordSource == .engine }

        XCTAssertEqual(home.expenseTotal, Decimal(100))
        XCTAssertEqual(statistics.expenseByType, [
            ExpenseTypeSummary(typeName: "生活必要开支", amount: Decimal(100), sourceRecordIds: [record.id])
        ])
        XCTAssertEqual(balance.cashBalance, Decimal(-100))
        XCTAssertEqual(balance.cashSourceRecordIds, [record.id])
        XCTAssertTrue(balance.liabilityItems.isEmpty)
        XCTAssertEqual(engineRecords.count, 1)
        XCTAssertEqual(engineRecords.first?.engineFamily, .cash)
        XCTAssertEqual(engineRecords.first?.engineKey, "2026-04:cash:ending_balance:cash_pool:电子钱包余额")
        XCTAssertEqual(engineRecords.first?.sourceRecordIds, [record.id])

        try useCases.updateJournalRecord(
            id: record.id,
            changes: JournalRecordChanges(amount: Decimal(120))
        )

        home = try useCases.queryHomeSummary(accountMonth: "2026-04")
        balance = try useCases.queryBalanceSummary(accountMonth: "2026-04")
        statistics = try useCases.queryStatisticsSummary(accountMonth: "2026-04")
        engineRecords = try useCases.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-04"], includeEngineRecords: true)
        ).filter { $0.recordSource == .engine }

        XCTAssertEqual(home.expenseTotal, Decimal(120))
        XCTAssertEqual(statistics.expenseByType, [
            ExpenseTypeSummary(typeName: "生活必要开支", amount: Decimal(120), sourceRecordIds: [record.id])
        ])
        XCTAssertEqual(balance.cashBalance, Decimal(-120))
        XCTAssertEqual(balance.cashSourceRecordIds, [record.id])
        XCTAssertTrue(balance.liabilityItems.isEmpty)
        XCTAssertEqual(engineRecords.count, 1)
        XCTAssertEqual(engineRecords.first?.amount, Decimal(-120))

        try useCases.deleteJournalRecord(id: record.id)

        home = try useCases.queryHomeSummary(accountMonth: "2026-04")
        balance = try useCases.queryBalanceSummary(accountMonth: "2026-04")
        statistics = try useCases.queryStatisticsSummary(accountMonth: "2026-04")
        engineRecords = try useCases.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-04"], includeEngineRecords: true)
        ).filter { $0.recordSource == .engine }

        XCTAssertEqual(home.expenseTotal, Decimal(0))
        XCTAssertEqual(balance.cashBalance, Decimal(0))
        XCTAssertTrue(balance.cashSourceRecordIds.isEmpty)
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

    func testEngineRecalculationUpsertsExistingKeyWithoutDuplicates() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let record = try useCases.createManualRecord(input: sampleInput(amount: Decimal(100)))
        let initialEngineRecord = try XCTUnwrap(try engineRecords(useCases).first)

        let repeatedResult = try useCases.recalculateAfterMutation(
            Mutation(recordId: record.id, mutationType: .update)
        )
        var records = try engineRecords(useCases)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, initialEngineRecord.id)
        XCTAssertEqual(records.first?.engineKey, initialEngineRecord.engineKey)
        XCTAssertTrue(repeatedResult.createdEngineRecordIds.isEmpty)
        XCTAssertTrue(repeatedResult.updatedEngineRecordIds.isEmpty)
        XCTAssertTrue(repeatedResult.deletedEngineRecordIds.isEmpty)

        try useCases.updateJournalRecord(
            id: record.id,
            changes: JournalRecordChanges(amount: Decimal(120))
        )
        records = try engineRecords(useCases)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, initialEngineRecord.id)
        XCTAssertEqual(records.first?.amount, Decimal(120))
        XCTAssertEqual(records.first?.sourceRecordIds, [record.id])
    }

    func testEngineRecalculationDeletesStaleKeyWhenFamilyChanges() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let record = try useCases.createManualRecord(input: sampleInput(amount: Decimal(100)))
        XCTAssertEqual(try engineRecords(useCases).map(\.engineKey), [
            "2026-04:liability:ending_balance:liability:广发卡"
        ])

        try useCases.updateJournalRecord(
            id: record.id,
            changes: JournalRecordChanges(paymentMethodName: "电子钱包余额")
        )

        let records = try engineRecords(useCases)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.engineKey, "2026-04:cash:ending_balance:cash_pool:电子钱包余额")
        XCTAssertEqual(records.first?.amount, Decimal(-100))
        XCTAssertEqual(records.first?.sourceRecordIds, [record.id])
    }

    func testEngineRecalculationAggregatesMultipleSourcesAndDeletesEmptyKey() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let first = try useCases.createManualRecord(input: sampleInput(amount: Decimal(100)))
        let second = try useCases.createManualRecord(input: sampleInput(amount: Decimal(50)))
        var records = try engineRecords(useCases)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.amount, Decimal(150))
        XCTAssertEqual(records.first?.sourceRecordIds.sorted { $0.uuidString < $1.uuidString }, [first.id, second.id].sorted { $0.uuidString < $1.uuidString })

        try useCases.deleteJournalRecord(id: first.id)
        records = try engineRecords(useCases)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.amount, Decimal(50))
        XCTAssertEqual(records.first?.sourceRecordIds, [second.id])

        try useCases.deleteJournalRecord(id: second.id)
        XCTAssertTrue(try engineRecords(useCases).isEmpty)
    }

    func testValidationRejectsInvalidManualRecordInputs() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        XCTAssertThrowsError(try useCases.createManualRecord(
            input: try sampleInput(accountMonth: "2026-13", amount: Decimal(100))
        )) { error in
            XCTAssertEqual(error as? MingZhangError, .validation("账月必须是合法的 YYYY-MM"))
        }

        XCTAssertThrowsError(try useCases.createManualRecord(
            input: try sampleInput(amount: Decimal(0))
        )) { error in
            XCTAssertEqual(error as? MingZhangError, .validation("金额不能为 0"))
        }

        let record = try useCases.createManualRecord(input: sampleInput(amount: Decimal(100)))
        try insertPaymentTypeAndDetail(database, typeName: "交通费", detailName: "公交")

        XCTAssertThrowsError(try useCases.updateJournalRecord(
            id: record.id,
            changes: JournalRecordChanges(paymentTypeName: "交通费")
        )) { error in
            XCTAssertEqual(error as? MingZhangError, .validation("类型明细必须归属于当前收付类型"))
        }
    }

    func testEngineAndInvestmentFeedRecordsAreNotEditableOrDeletable() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let record = try useCases.createManualRecord(input: sampleInput(amount: Decimal(100)))
        let engineRecord = try XCTUnwrap(try useCases.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-04"], includeEngineRecords: true)
        ).first { $0.recordSource == .engine })

        XCTAssertThrowsError(try useCases.updateJournalRecord(
            id: engineRecord.id,
            changes: JournalRecordChanges(amount: Decimal(120))
        )) { error in
            XCTAssertEqual(error as? MingZhangError, .recordNotEditable(engineRecord.id))
        }
        XCTAssertThrowsError(try useCases.deleteJournalRecord(id: engineRecord.id)) { error in
            XCTAssertEqual(error as? MingZhangError, .recordNotEditable(engineRecord.id))
        }

        try database.writer.write { db in
            try db.execute(
                sql: "UPDATE journal_records SET record_source = ? WHERE id = ?",
                arguments: [RecordSource.investmentFeed.rawValue, record.id.uuidString]
            )
        }

        XCTAssertThrowsError(try useCases.updateJournalRecord(
            id: record.id,
            changes: JournalRecordChanges(amount: Decimal(120))
        )) { error in
            XCTAssertEqual(error as? MingZhangError, .recordNotEditable(record.id))
        }
        XCTAssertThrowsError(try useCases.deleteJournalRecord(id: record.id)) { error in
            XCTAssertEqual(error as? MingZhangError, .recordNotEditable(record.id))
        }
    }

    private func sampleInput(
        accountMonth: String = "2026-04",
        paymentMethodName: String = "广发卡",
        amount: Decimal
    ) throws -> CreateManualRecordInput {
        let occurredAt = try Date.iso8601("2026-04-15T12:30:00Z")

        return CreateManualRecordInput(
            accountMonth: accountMonth,
            occurredAt: occurredAt,
            paymentMethodName: paymentMethodName,
            amount: amount,
            paymentTypeName: "生活必要开支",
            paymentDetailName: "伙食费",
            note: "午餐"
        )
    }

    private func insertPaymentTypeAndDetail(
        _ database: LedgerDatabase,
        typeName: String,
        detailName: String
    ) throws {
        let typeId = UUID()
        let detailId = UUID()
        let now = "2026-04-15T12:30:00Z"
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO payment_types (id, name, element, is_active, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [
                    typeId.uuidString,
                    typeName,
                    AccountingElement.expense.rawValue,
                    true,
                    now,
                    now
                ])
            try db.execute(sql: """
                INSERT INTO payment_details (id, name, payment_type_id, is_active, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [
                    detailId.uuidString,
                    detailName,
                    typeId.uuidString,
                    true,
                    now,
                    now
                ])
        }
    }

    private func engineRecords(_ useCases: LedgerUseCases) throws -> [JournalRecord] {
        try useCases.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-04"], includeEngineRecords: true)
        )
        .filter { $0.recordSource == .engine }
        .sorted { ($0.engineKey ?? "") < ($1.engineKey ?? "") }
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
