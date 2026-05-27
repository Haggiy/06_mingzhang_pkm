import Foundation
import XCTest
@testable import MingZhangCore

final class P1BackupRestoreTests: XCTestCase {
    func testAuditExportIncludesTraceableJournalRows() throws {
        let useCases = try makePopulatedLedger()

        let export = try useCases.exportAuditData()
        let csv = try XCTUnwrap(String(data: export.data, encoding: .utf8))

        XCTAssertTrue(export.fileName.hasSuffix(".csv"))
        XCTAssertTrue(csv.contains("id,账月,时间,收付手段,金额,收付类型,类型明细,备注,记录来源"))
        XCTAssertTrue(csv.contains("午餐"))
        XCTAssertTrue(csv.contains("import"))
        XCTAssertTrue(csv.contains("investment_feed"))
        XCTAssertTrue(csv.contains("source_import_batch_id"))
        XCTAssertTrue(csv.contains("source_investment_transaction_ids"))
    }

    func testBackupPackageContainsManifestAndValidatesChecksum() throws {
        let useCases = try makePopulatedLedger()

        let package = try useCases.createBackupPackage()
        let validation = try useCases.validateBackupPackage(data: package.data)

        XCTAssertTrue(package.fileName.hasSuffix(".mzbackup"))
        XCTAssertEqual(package.manifest.backupSchemaVersion, 1)
        XCTAssertEqual(package.manifest.appDataSchemaVersion, "v4_p1_settings_semantics")
        XCTAssertTrue(package.manifest.payloadChecksum.hasPrefix("sha256:"))
        XCTAssertEqual(package.manifest.recordCounts.paymentMethods, try useCases.queryPaymentMethods().count)
        XCTAssertGreaterThan(package.manifest.recordCounts.journalRecords, 0)
        XCTAssertGreaterThan(package.manifest.recordCounts.importCandidates, 0)
        XCTAssertGreaterThan(package.manifest.recordCounts.investmentTransactions, 0)

        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.manifest, package.manifest)
        XCTAssertTrue(validation.errors.isEmpty)
        XCTAssertEqual(validation.preview?.recordCounts, package.manifest.recordCounts)
    }

    func testValidationRejectsTamperedChecksumAndUnsupportedSchema() throws {
        let useCases = try makePopulatedLedger()
        let package = try useCases.createBackupPackage()

        let tampered = try replaceInBackup(package.data, target: "午餐", replacement: "晚餐")
        let tamperedValidation = try useCases.validateBackupPackage(data: tampered)
        XCTAssertFalse(tamperedValidation.isValid)
        XCTAssertTrue(tamperedValidation.errors.contains { $0.contains("checksum") || $0.contains("校验") })

        let unsupported = try replaceInBackup(package.data, target: "\"backupSchemaVersion\":1", replacement: "\"backupSchemaVersion\":999")
        let unsupportedValidation = try useCases.validateBackupPackage(data: unsupported)
        XCTAssertFalse(unsupportedValidation.isValid)
        XCTAssertTrue(unsupportedValidation.errors.contains { $0.contains("schema") || $0.contains("版本") })
    }

    func testRestoreBackupRecreatesLedgerAndRollbackOnFailure() throws {
        let source = try makePopulatedLedger()
        let package = try source.createBackupPackage()

        let targetDatabase = try LedgerDatabase.inMemory()
        let target = LedgerUseCases(database: targetDatabase)
        try target.initializeLedgerSeed()
        _ = try target.createManualRecord(input: sampleManualRecord(note: "保留校验"))

        let restored = try target.restoreBackupPackage(data: package.data, confirmed: true)
        XCTAssertEqual(restored.recordCounts, package.manifest.recordCounts)

        let restoredRecords = try target.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-04"], includeEngineRecords: true)
        )
        XCTAssertEqual(restoredRecords.count, package.manifest.recordCounts.journalRecords)
        XCTAssertTrue(restoredRecords.contains { $0.recordSource == .import && $0.sourceImportBatchId != nil })
        XCTAssertTrue(restoredRecords.contains { $0.recordSource == .investmentFeed && !$0.sourceInvestmentTransactionIds.isEmpty })
        XCTAssertFalse(restoredRecords.contains { $0.note == "保留校验" })

        let home = try target.queryHomeSummary(accountMonth: "2026-04")
        let balance = try target.queryBalanceSummary(accountMonth: "2026-04")
        let statistics = try target.queryStatisticsSummary(accountMonth: "2026-04")
        XCTAssertNotEqual(home.expenseTotal, Decimal(0))
        XCTAssertFalse(balance.liabilityItems.isEmpty)
        XCTAssertFalse(statistics.expenseByType.isEmpty)

        let beforeFailureIds = Set(restoredRecords.map(\.id))
        let tampered = try replaceInBackup(package.data, target: "午餐", replacement: "晚餐")
        XCTAssertThrowsError(try target.restoreBackupPackage(data: tampered, confirmed: true))
        let afterFailureIds = Set(try target.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-04"], includeEngineRecords: true)
        ).map(\.id))
        XCTAssertEqual(afterFailureIds, beforeFailureIds)
    }

    private func makePopulatedLedger() throws -> LedgerUseCases {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        _ = try useCases.createManualRecord(input: sampleManualRecord(note: "午餐"))

        let importResult = try useCases.createImportBatch(source: .alipay, fileName: "backup-alipay.csv", contents: alipayCSV())
        let candidate = try XCTUnwrap(importResult.candidates.first)
        _ = try useCases.updateImportCandidate(
            id: candidate.id,
            changes: ImportCandidateChanges(paymentTypeName: "生活必要开支", paymentDetailName: "伙食费")
        )
        _ = try useCases.confirmImportCandidates(ids: [candidate.id])

        _ = try useCases.createInvestmentTransaction(input: investmentInput(
            occurredAt: try iso8601("2026-04-01T00:00:00Z"),
            transactionType: .buy,
            tradeAmount: Decimal(1000),
            tradeShare: Decimal(1000),
            nav: Decimal(1),
            note: "买入"
        ))
        _ = try useCases.createInvestmentTransaction(input: investmentInput(
            occurredAt: try iso8601("2026-04-20T00:00:00Z"),
            transactionType: .sell,
            tradeAmount: Decimal(-120),
            tradeShare: Decimal(-100),
            nav: Decimal(1.2),
            note: "卖出"
        ))

        return useCases
    }

    private func sampleManualRecord(note: String) -> CreateManualRecordInput {
        CreateManualRecordInput(
            accountMonth: "2026-04",
            occurredAt: Date(timeIntervalSince1970: 1_775_214_000),
            paymentMethodName: "广发卡",
            amount: Decimal(100),
            paymentTypeName: "生活必要开支",
            paymentDetailName: "伙食费",
            note: note
        )
    }

    private func investmentInput(
        occurredAt: Date,
        transactionType: InvestmentTransactionType,
        tradeAmount: Decimal,
        tradeShare: Decimal,
        nav: Decimal,
        note: String
    ) -> CreateInvestmentTransactionInput {
        CreateInvestmentTransactionInput(
            accountMonth: "2026-04",
            occurredAt: occurredAt,
            fundName: "沪深300指数A",
            transactionType: transactionType,
            tradeAmount: tradeAmount,
            tradeShare: tradeShare,
            nav: nav,
            note: note
        )
    }

    private func alipayCSV() -> String {
        """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-15 12:30:45,餐饮美食,备份餐厅,/ ,套餐,支出,25.00,广发卡,交易成功,BACKUP-T-001\t,\t,,
        """
    }

    private func replaceInBackup(_ data: Data, target: String, replacement: String) throws -> Data {
        let string = try XCTUnwrap(String(data: data, encoding: .utf8))
        let replaced = string.replacingOccurrences(of: target, with: replacement)
        return try XCTUnwrap(replaced.data(using: .utf8))
    }

    private func iso8601(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw MingZhangError.invalidDate(value)
        }
        return date
    }
}
