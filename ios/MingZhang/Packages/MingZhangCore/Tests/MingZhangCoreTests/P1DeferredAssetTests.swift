import Foundation
import XCTest
@testable import MingZhangCore

final class P1DeferredAssetTests: XCTestCase {
    func testPrepaidExpenseFormsDeferredAssetAndReleaseRecognizesExpense() throws {
        let useCases = try makeUseCases()
        let objectName = "12个月健身房费用(202601-202612)"
        let objectKey = "deferred:\(objectName)"

        let prepaid = try useCases.createManualRecord(input: CreateManualRecordInput(
            accountMonth: "2026-01",
            occurredAt: try Date.iso8601("2026-01-05T10:00:00Z"),
            paymentMethodName: "电子钱包余额",
            amount: Decimal(1200),
            paymentTypeName: "资产类支出",
            paymentDetailName: "长期待摊费用",
            note: objectName
        ))

        let januaryBalance = try useCases.queryBalanceSummary(accountMonth: "2026-01")
        XCTAssertEqual(januaryBalance.cashBalance, Decimal(-1200))
        XCTAssertEqual(januaryBalance.deferredItems, [
            DeferredBalanceItem(
                name: objectName,
                objectKey: objectKey,
                amount: Decimal(1200),
                formedAmount: Decimal(1200),
                releasedAmount: Decimal(0),
                sourceRecordIds: [prepaid.id]
            )
        ])
        XCTAssertEqual(try useCases.queryHomeSummary(accountMonth: "2026-01").expenseTotal, Decimal(0))

        let release = try useCases.createDeferredRelease(input: CreateDeferredReleaseInput(
            accountMonth: "2026-02",
            occurredAt: try Date.iso8601("2026-02-28T00:00:00Z"),
            deferredObjectKey: objectKey,
            amount: Decimal(120),
            expensePaymentTypeName: "投资自身开支",
            expensePaymentDetailName: "健身训练费",
            note: "12个月健身房费用 2/12"
        ))

        XCTAssertEqual(release.assetReleaseRecord.paymentMethodName, "账务处理")
        XCTAssertEqual(release.assetReleaseRecord.amount, Decimal(-120))
        XCTAssertEqual(release.assetReleaseRecord.paymentTypeName, "资产类支出")
        XCTAssertEqual(release.assetReleaseRecord.paymentDetailName, "长期待摊费用")
        XCTAssertEqual(release.assetReleaseRecord.recordKind, .carryForward)
        XCTAssertEqual(release.assetReleaseRecord.carryForwardRole, .accountingSkeleton)
        XCTAssertEqual(release.assetReleaseRecord.objectKey, objectKey)

        XCTAssertEqual(release.expenseRecord.amount, Decimal(120))
        XCTAssertEqual(release.expenseRecord.paymentTypeName, "投资自身开支")
        XCTAssertEqual(release.expenseRecord.paymentDetailName, "健身训练费")
        XCTAssertEqual(release.expenseRecord.recordKind, .carryForward)
        XCTAssertEqual(release.expenseRecord.carryForwardRole, .accountingSkeleton)
        XCTAssertEqual(release.expenseRecord.objectKey, objectKey)

        let februaryBalance = try useCases.queryBalanceSummary(accountMonth: "2026-02")
        XCTAssertEqual(februaryBalance.cashBalance, Decimal(0))
        XCTAssertEqual(februaryBalance.deferredItems, [
            DeferredBalanceItem(
                name: objectName,
                objectKey: objectKey,
                amount: Decimal(1080),
                formedAmount: Decimal(1200),
                releasedAmount: Decimal(120),
                sourceRecordIds: [prepaid.id, release.assetReleaseRecord.id]
            )
        ])

        XCTAssertEqual(try useCases.queryHomeSummary(accountMonth: "2026-02").expenseTotal, Decimal(120))
        XCTAssertEqual(try useCases.queryStatisticsSummary(accountMonth: "2026-02").expenseByType, [
            ExpenseTypeSummary(typeName: "投资自身开支", amount: Decimal(120), sourceRecordIds: [release.expenseRecord.id])
        ])

        let engineRecords = try useCases.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-02"], includeEngineRecords: true)
        ).filter { $0.recordSource == .engine && $0.engineFamily == .deferred }
        XCTAssertEqual(engineRecords.count, 1)
        XCTAssertEqual(engineRecords.first?.amount, Decimal(1080))
        XCTAssertEqual(engineRecords.first?.engineKey, "2026-02:deferred:ending_balance:\(objectKey)")
        XCTAssertEqual(engineRecords.first?.sourceRecordIds, [prepaid.id, release.assetReleaseRecord.id])
    }

    private func makeUseCases() throws -> LedgerUseCases {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()
        return useCases
    }
}

private extension Date {
    static func iso8601(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw XCTSkip("Invalid date fixture: \(value)")
        }
        return date
    }
}
