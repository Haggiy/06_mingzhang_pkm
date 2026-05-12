import Foundation
import XCTest
@testable import MingZhangCore

final class P1ImportFlowTests: XCTestCase {
    func testImportSchemaStartsEmptyAndSeedsPendingRealAccount() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        XCTAssertTrue(try useCases.queryImportBatches().isEmpty)
        XCTAssertTrue(try useCases.queryImportCandidates(batchId: UUID()).isEmpty)
        XCTAssertEqual(
            try useCases.queryPaymentMethods().first { $0.name == "待补真实账户" }?.methodType,
            .pendingRealAccount
        )
    }

    func testCreateImportBatchMapsAlipayAndWechatRowsToCandidates() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let alipay = try useCases.createImportBatch(
            source: .alipay,
            fileName: "alipay-minimal.csv",
            contents: fixture("alipay-minimal.csv")
        )
        let wechat = try useCases.createImportBatch(
            source: .wechat,
            fileName: "wechat-minimal.csv",
            contents: fixture("wechat-minimal.csv")
        )

        XCTAssertEqual(alipay.batch.source, .alipay)
        XCTAssertEqual(alipay.candidates.count, 2)
        XCTAssertEqual(alipay.issues.count, 0)

        let alipayExpense = try XCTUnwrap(alipay.candidates.first { $0.amount < 0 })
        XCTAssertEqual(alipayExpense.accountMonth, "2026-04")
        XCTAssertEqual(alipayExpense.amount, Decimal(-100))
        XCTAssertEqual(alipayExpense.paymentMethodName, "广发卡(4896)")
        XCTAssertEqual(alipayExpense.rawTransactionId, "ALIPAY-001")
        XCTAssertEqual(alipayExpense.note, "[餐饮美食] 便利店 - 午餐")

        let alipayIncome = try XCTUnwrap(alipay.candidates.first { $0.amount > 0 })
        XCTAssertEqual(alipayIncome.amount, Decimal(50))
        XCTAssertEqual(alipayIncome.paymentMethodName, "余额")

        XCTAssertEqual(wechat.batch.source, .wechat)
        XCTAssertEqual(wechat.candidates.count, 1)
        XCTAssertEqual(wechat.issues.count, 0)

        let wechatExpense = try XCTUnwrap(wechat.candidates.first)
        XCTAssertEqual(wechatExpense.amount, try decimal("-20.50"))
        XCTAssertEqual(wechatExpense.paymentMethodName, "待补真实账户")
        XCTAssertEqual(wechatExpense.rawTransactionId, "WECHAT-001")
        XCTAssertEqual(wechatExpense.note, "[商户消费] 早餐店 - 早餐")
    }

    func testImportCandidatesDoNotAffectLedgerBeforeConfirmation() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        _ = try useCases.createImportBatch(
            source: .alipay,
            fileName: "alipay-minimal.csv",
            contents: fixture("alipay-minimal.csv")
        )

        XCTAssertTrue(try useCases.queryJournalRecords(filter: JournalRecordFilter(accountMonths: ["2026-04"])).isEmpty)
        XCTAssertTrue(try useCases.queryAccountMonths().isEmpty)
        XCTAssertEqual(try useCases.queryHomeSummary(accountMonth: "2026-04").expenseTotal, Decimal(0))
        XCTAssertEqual(try useCases.queryBalanceSummary(accountMonth: "2026-04").cashBalance, Decimal(0))
        XCTAssertTrue(try useCases.queryStatisticsSummary(accountMonth: "2026-04").expenseByType.isEmpty)
    }

    func testUpdateAndBatchUpdateImportCandidatesDoNotChangeOccurredAt() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()
        let result = try useCases.createImportBatch(
            source: .alipay,
            fileName: "alipay-minimal.csv",
            contents: fixture("alipay-minimal.csv")
        )
        let candidate = try XCTUnwrap(result.candidates.first)

        let updated = try useCases.updateImportCandidate(
            id: candidate.id,
            changes: ImportCandidateChanges(
                accountMonth: "2026-03",
                paymentMethodName: "电子钱包余额",
                paymentTypeName: "生活必要开支",
                paymentDetailName: "伙食费",
                note: "便利店午餐"
            )
        )

        XCTAssertEqual(updated.accountMonth, "2026-03")
        XCTAssertEqual(updated.occurredAt, candidate.occurredAt)
        XCTAssertEqual(updated.paymentMethodName, "电子钱包余额")

        let batched = try useCases.batchUpdateImportCandidates(
            ids: [candidate.id],
            changes: ImportCandidateChanges(accountMonth: "2026-04", paymentMethodName: "广发卡")
        )

        XCTAssertEqual(batched.first?.accountMonth, "2026-04")
        XCTAssertEqual(batched.first?.occurredAt, candidate.occurredAt)
        XCTAssertEqual(batched.first?.paymentMethodName, "广发卡")

        let ignored = try useCases.ignoreImportCandidates(ids: [candidate.id])
        XCTAssertEqual(ignored.first?.status, .ignored)
    }

    func testConfirmImportCandidatesCreatesImportRecordsAndRecalculates() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()
        let batch = try useCases.createImportBatch(
            source: .alipay,
            fileName: "alipay-minimal.csv",
            contents: fixture("alipay-minimal.csv")
        )
        let candidate = try XCTUnwrap(batch.candidates.first { $0.amount < 0 })
        _ = try useCases.updateImportCandidate(
            id: candidate.id,
            changes: ImportCandidateChanges(
                paymentMethodName: "广发卡",
                paymentTypeName: "生活必要开支",
                paymentDetailName: "伙食费"
            )
        )

        let records = try useCases.confirmImportCandidates(ids: [candidate.id])

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.recordSource, .import)
        XCTAssertEqual(records.first?.sourceImportBatchId, batch.batch.id)
        XCTAssertEqual(records.first?.sourceImportCandidateId, candidate.id)
        XCTAssertEqual(try useCases.queryHomeSummary(accountMonth: "2026-04").expenseTotal, Decimal(100))
        XCTAssertEqual(try useCases.queryBalanceSummary(accountMonth: "2026-04").liabilityItems.first?.amount, Decimal(100))
        XCTAssertEqual(try useCases.queryStatisticsSummary(accountMonth: "2026-04").expenseByType.first?.amount, Decimal(100))

        let confirmedCandidate = try XCTUnwrap(try useCases.queryImportCandidates(batchId: batch.batch.id).first { $0.id == candidate.id })
        XCTAssertEqual(confirmedCandidate.status, .confirmed)
        XCTAssertEqual(confirmedCandidate.createdJournalRecordId, records.first?.id)
    }

    func testImportRecordCanTraceBackToBatchAndRawCandidate() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()
        let batch = try useCases.createImportBatch(
            source: .alipay,
            fileName: "alipay-minimal.csv",
            contents: fixture("alipay-minimal.csv")
        )
        let candidate = try XCTUnwrap(batch.candidates.first { $0.amount < 0 })
        _ = try useCases.batchUpdateImportCandidates(
            ids: [candidate.id],
            changes: ImportCandidateChanges(
                paymentMethodName: "广发卡",
                paymentTypeName: "生活必要开支",
                paymentDetailName: "伙食费"
            )
        )
        let record = try XCTUnwrap(try useCases.confirmImportCandidates(ids: [candidate.id]).first)

        let trace = try useCases.getImportTrace(recordId: record.id)

        XCTAssertEqual(trace?.batch.id, batch.batch.id)
        XCTAssertEqual(trace?.batch.fileName, "alipay-minimal.csv")
        XCTAssertEqual(trace?.candidate.id, candidate.id)
        XCTAssertEqual(trace?.candidate.rawLineNumber, 26)
        XCTAssertTrue(trace?.candidate.rawPayload.contains("ALIPAY-001") == true)
    }

    func testImportReportsInvalidAmountUnknownFieldsAndDuplicates() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        XCTAssertThrowsError(try useCases.createImportBatch(
            source: .alipay,
            fileName: "unknown.csv",
            contents: "时间,金额\n2026-04-15,100"
        )) { error in
            XCTAssertEqual(error as? MingZhangError, .validation("无法识别支付宝账单字段"))
        }

        let invalid = try useCases.createImportBatch(
            source: .alipay,
            fileName: "invalid-amount.csv",
            contents: """
            -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
            交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
            2026-04-15 12:30:45,餐饮美食,便利店,/,午餐,支出,abc,广发卡,交易成功,ALIPAY-BAD\t,\t,,
            """
        )
        XCTAssertTrue(invalid.candidates.isEmpty)
        XCTAssertEqual(invalid.issues.first?.code, .invalidAmount)

        _ = try useCases.createImportBatch(
            source: .alipay,
            fileName: "alipay-minimal.csv",
            contents: fixture("alipay-minimal.csv")
        )
        let duplicate = try useCases.createImportBatch(
            source: .alipay,
            fileName: "alipay-minimal-copy.csv",
            contents: fixture("alipay-minimal.csv")
        )
        XCTAssertTrue(duplicate.candidates.isEmpty)
        XCTAssertEqual(duplicate.issues.first?.code, .duplicate)
    }

    func testImportSkipsNonRevenueExpenseTransactions() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let alipayNeutral = try useCases.createImportBatch(
            source: .alipay,
            fileName: "alipay-neutral.csv",
            contents: """
            -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
            交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
            2026-04-15 10:00:00,投资理财,余额宝,hua***@example.com,余额宝-转入,不计收支,500.00,中国银行储蓄卡(6863),交易成功,ALIPAY-NEUTRAL-001\t,\t,,
            2026-04-15 12:00:00,信用卡还款,招商银行信用卡,/,信用卡还款,不计收支,1000.00,中国银行储蓄卡(6863),交易成功,ALIPAY-NEUTRAL-002\t,\t,,
            2026-04-15 14:00:00,餐饮美食,便利店,/,午餐,支出,30.00,广发卡,交易成功,ALIPAY-VALID-001\t,\t,,
            """
        )
        XCTAssertEqual(alipayNeutral.candidates.count, 1)
        XCTAssertEqual(alipayNeutral.issues.filter { $0.code == .unsupportedDirection }.count, 2)

        let wechatNeutral = try useCases.createImportBatch(
            source: .wechat,
            fileName: "wechat-neutral.csv",
            contents: """
            微信支付账单明细,,,,,,,,
            微信昵称：[test],,,,,,,,
            起始时间：[2026-04-01 00:00:00] 终止时间：[2026-04-30 23:59:59],,,,,,,,
            导出类型：[全部],,,,,,,,
            导出时间：[2026-05-11 10:00:00],,,,,,,,
            ,,,,,,,,
            共3笔记录,,,,,,,,
            收入：0笔 0.00元,,,,,,,,
            支出：1笔 30.00元,,,,,,,,
            中性交易：2笔 1500.00元,,,,,,,,
            注：,,,,,,,,
            1. 充值/提现/理财通购买/零钱通存取/信用卡还款等交易，将计入中性交易,,,,,,,,
            2. 本明细仅展示当前账单中的交易，不包括已删除的记录,,,,,,,,
            3. 本明细仅供个人对账使用,,,,,,,,
            ,,,,,,,,
            ----------------------微信支付账单明细列表--------------------,,,,,,,,
            交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
            2026-04-15 10:00:00,零钱提现,零钱提现,零钱提现,支出,¥500.00,中国银行储蓄卡,支付成功,WX-NEUTRAL-001\t,\t,/
            2026-04-15 12:00:00,信用卡还款,信用卡还款,信用卡还款,支出,¥1000.00,中国银行储蓄卡,支付成功,WX-NEUTRAL-002\t,\t,/
            2026-04-15 14:00:00,商户消费,便利店,午餐,支出,¥30.00,零钱,支付成功,WX-VALID-001\t,\t,/
            """
        )
        XCTAssertEqual(wechatNeutral.candidates.count, 1)
        XCTAssertEqual(wechatNeutral.issues.filter { $0.code == .unsupportedDirection }.count, 2)

        let wechatTransfer = try useCases.createImportBatch(
            source: .wechat,
            fileName: "wechat-transfer.csv",
            contents: """
            微信支付账单明细,,,,,,,,
            微信昵称：[test],,,,,,,,
            起始时间：[2026-04-01 00:00:00] 终止时间：[2026-04-01 23:59:59],,,,,,,,
            导出类型：[全部],,,,,,,,
            导出时间：[2026-05-11 10:00:00],,,,,,,,
            ,,,,,,,,
            共2笔记录,,,,,,,,
            收入：1笔 70.00元,,,,,,,,
            支出：1笔 20.00元,,,,,,,,
            中性交易：0笔 0.00元,,,,,,,,
            注：,,,,,,,,
            1. 充值/提现/理财通购买/零钱通存取/信用卡还款等交易，将计入中性交易,,,,,,,,
            2. 本明细仅展示当前账单中的交易，不包括已删除的记录,,,,,,,,
            3. 本明细仅供个人对账使用,,,,,,,,
            ,,,,,,,,
            ----------------------微信支付账单明细列表--------------------,,,,,,,,
            交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
            2026-04-01 10:00:00,转账,同事李四,转账备注:AA制聚餐,收入,¥70.00,/,已存入零钱,WX-TRANSFER-001\t,\t,/
            2026-04-01 12:00:00,转账,同事李四,转账备注:还款,支出,¥20.00,零钱,对方已收钱,WX-TRANSFER-002\t,\t,/
            """
        )
        XCTAssertEqual(wechatTransfer.candidates.count, 2)
        let transferIncome = try XCTUnwrap(wechatTransfer.candidates.first { $0.amount > 0 })
        let transferExpense = try XCTUnwrap(wechatTransfer.candidates.first { $0.amount < 0 })
        XCTAssertEqual(transferIncome.amount, Decimal(70))
        XCTAssertEqual(transferExpense.amount, Decimal(-20))
    }

    func testP1AlipayWechatImportEndToEnd() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let alipay = try useCases.createImportBatch(source: .alipay, fileName: "alipay-minimal.csv", contents: fixture("alipay-minimal.csv"))
        let wechat = try useCases.createImportBatch(source: .wechat, fileName: "wechat-minimal.csv", contents: fixture("wechat-minimal.csv"))
        let ids = (alipay.candidates + wechat.candidates)
            .filter { $0.amount < 0 }
            .map(\.id)

        _ = try useCases.batchUpdateImportCandidates(
            ids: ids,
            changes: ImportCandidateChanges(
                paymentMethodName: "广发卡",
                paymentTypeName: "生活必要开支",
                paymentDetailName: "伙食费"
            )
        )
        let records = try useCases.confirmImportCandidates(ids: ids)

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map(\.recordSource), [.import, .import])
        XCTAssertEqual(
            try useCases.queryHomeSummary(accountMonth: "2026-04").expenseTotal,
            try decimal("120.50")
        )
        XCTAssertEqual(try useCases.queryStatisticsSummary(accountMonth: "2026-04").sourceRecordIds.count, 2)
        XCTAssertNotNil(try useCases.getImportTrace(recordId: try XCTUnwrap(records.first?.id)))
    }

    private func fixture(_ name: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let fixtureURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        return try String(contentsOf: fixtureURL, encoding: .utf8)
    }

    private func decimal(_ value: String) throws -> Decimal {
        try XCTUnwrap(Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")))
    }
}
