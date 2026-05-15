import Foundation
import GRDB
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

        let alipayExpense = try XCTUnwrap(alipay.candidates.first { $0.rawTransactionId == "ALIPAY-001" })
        XCTAssertEqual(alipayExpense.accountMonth, "2026-04")
        XCTAssertEqual(alipayExpense.amount, Decimal(100))
        XCTAssertEqual(alipayExpense.paymentMethodName, "广发卡(4896)")
        XCTAssertEqual(alipayExpense.rawTransactionId, "ALIPAY-001")
        XCTAssertEqual(alipayExpense.note, "[餐饮美食] 便利店 - 午餐")

        let alipayIncome = try XCTUnwrap(alipay.candidates.first { $0.rawTransactionId == "ALIPAY-002" })
        XCTAssertEqual(alipayIncome.amount, Decimal(50))
        XCTAssertEqual(alipayIncome.paymentMethodName, "余额")

        XCTAssertEqual(wechat.batch.source, .wechat)
        XCTAssertEqual(wechat.candidates.count, 1)
        XCTAssertEqual(wechat.issues.count, 0)

        let wechatExpense = try XCTUnwrap(wechat.candidates.first)
        XCTAssertEqual(wechatExpense.amount, try decimal("20.50"))
        XCTAssertEqual(wechatExpense.paymentMethodName, "待补真实账户")
        XCTAssertEqual(wechatExpense.rawTransactionId, "WECHAT-001")
        XCTAssertEqual(wechatExpense.note, "[商户消费] 早餐店 - 早餐")
    }

    func testCreateImportBatchMapsWechatXLSXRowsToCandidates() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let result = try useCases.createImportBatch(
            source: .wechat,
            fileName: "wechat-minimal.xlsx",
            data: fixtureData("wechat-minimal.xlsx")
        )

        XCTAssertEqual(result.batch.source, .wechat)
        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertEqual(result.issues.count, 0)

        let candidate = try XCTUnwrap(result.candidates.first)
        XCTAssertEqual(candidate.accountMonth, "2026-04")
        XCTAssertEqual(candidate.amount, try decimal("20.50"))
        XCTAssertEqual(candidate.paymentMethodName, "待补真实账户")
        XCTAssertEqual(candidate.rawTransactionId, "WECHAT-XLSX-001")
        XCTAssertEqual(candidate.rawLineNumber, 18)
        XCTAssertEqual(candidate.note, "[商户消费] 早餐店 - 早餐")
    }

    func testCreateImportBatchMapsAlipayXLSXRowsToCandidates() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let result = try useCases.createImportBatch(
            source: .alipay,
            fileName: "alipay-minimal.xlsx",
            data: fixtureData("alipay-minimal.xlsx")
        )

        XCTAssertEqual(result.batch.source, .alipay)
        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertEqual(result.issues.count, 0)

        let candidate = try XCTUnwrap(result.candidates.first)
        XCTAssertEqual(candidate.accountMonth, "2026-04")
        XCTAssertEqual(candidate.amount, Decimal(100))
        XCTAssertEqual(candidate.paymentMethodName, "广发卡(4896)")
        XCTAssertEqual(candidate.rawTransactionId, "ALIPAY-XLSX-001")
        XCTAssertEqual(candidate.rawLineNumber, 26)
        XCTAssertEqual(candidate.note, "[餐饮美食] 便利店 - 午餐")
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
                amount: try decimal("-42.25"),
                paymentMethodName: "电子钱包余额",
                paymentTypeName: "生活必要开支",
                paymentDetailName: "伙食费",
                note: "便利店午餐"
            )
        )

        XCTAssertEqual(updated.accountMonth, "2026-03")
        XCTAssertEqual(updated.occurredAt, candidate.occurredAt)
        XCTAssertEqual(updated.amount, try decimal("-42.25"))
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
        let candidate = try XCTUnwrap(batch.candidates.first { $0.rawTransactionId == "ALIPAY-001" })
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

    func testConfirmImportCandidatePreservesSignedAmountSemantics() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()
        let batch = try useCases.createImportBatch(
            source: .wechat,
            fileName: "wechat-minimal.csv",
            contents: fixture("wechat-minimal.csv")
        )
        let candidate = try XCTUnwrap(batch.candidates.first)
        let updated = try useCases.updateImportCandidate(
            id: candidate.id,
            changes: ImportCandidateChanges(
                amount: try decimal("-20.50"),
                paymentMethodName: "广发卡",
                paymentTypeName: "生活必要开支",
                paymentDetailName: "伙食费"
            )
        )

        let record = try XCTUnwrap(try useCases.confirmImportCandidates(ids: [updated.id]).first)

        XCTAssertEqual(updated.amount, try decimal("-20.50"))
        XCTAssertEqual(record.amount, try decimal("-20.50"))
        XCTAssertEqual(record.sourceImportCandidateId, updated.id)
    }

    func testImportMemoryPrefillsClassificationWhenSameSourceMerchantAndProductHistoryIsConsistent() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let firstContents = """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-15 12:30:45,餐饮美食,记忆便利店,/,午餐套餐,支出,100.00,广发卡,交易成功,ALIPAY-MEMORY-001\t,\t,,
        """
        let firstBatch = try useCases.createImportBatch(source: .alipay, fileName: "memory-1.csv", contents: firstContents)
        let firstCandidate = try XCTUnwrap(firstBatch.candidates.first)
        _ = try useCases.updateImportCandidate(
            id: firstCandidate.id,
            changes: ImportCandidateChanges(
                paymentMethodName: "广发卡",
                paymentTypeName: "生活必要开支",
                paymentDetailName: "伙食费"
            )
        )
        _ = try useCases.confirmImportCandidates(ids: [firstCandidate.id])

        let secondContents = """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-16 08:10:00,餐饮美食,记忆便利店,/,午餐套餐,支出,25.00,广发卡,交易成功,ALIPAY-MEMORY-002\t,\t,,
        """
        let secondBatch = try useCases.createImportBatch(source: .alipay, fileName: "memory-2.csv", contents: secondContents)
        let secondCandidate = try XCTUnwrap(secondBatch.candidates.first)

        XCTAssertEqual(secondCandidate.paymentTypeName, "生活必要开支")
        XCTAssertEqual(secondCandidate.paymentDetailName, "伙食费")
        XCTAssertNotNil(secondCandidate.paymentTypeId)
        XCTAssertNotNil(secondCandidate.paymentDetailId)
    }

    func testImportMemoryLeavesClassificationEmptyWhenSameSourceMerchantAndProductHistoryConflicts() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()
        try insertPaymentTypeAndDetailForTest(database: database, typeName: "文娱游购开支", detailName: "饮食游乐费")

        let firstContents = """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-15 12:30:45,餐饮美食,冲突便利店,/,午餐套餐,支出,100.00,广发卡,交易成功,ALIPAY-MEMORY-CONFLICT-001\t,\t,,
        """
        let firstBatch = try useCases.createImportBatch(source: .alipay, fileName: "memory-conflict-1.csv", contents: firstContents)
        let firstCandidate = try XCTUnwrap(firstBatch.candidates.first)
        _ = try useCases.updateImportCandidate(
            id: firstCandidate.id,
            changes: ImportCandidateChanges(
                paymentMethodName: "广发卡",
                paymentTypeName: "生活必要开支",
                paymentDetailName: "伙食费"
            )
        )
        _ = try useCases.confirmImportCandidates(ids: [firstCandidate.id])

        let secondContents = """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-16 12:30:45,餐饮美食,冲突便利店,/,午餐套餐,支出,80.00,广发卡,交易成功,ALIPAY-MEMORY-CONFLICT-002\t,\t,,
        """
        let secondBatch = try useCases.createImportBatch(source: .alipay, fileName: "memory-conflict-2.csv", contents: secondContents)
        let secondCandidate = try XCTUnwrap(secondBatch.candidates.first)
        _ = try useCases.updateImportCandidate(
            id: secondCandidate.id,
            changes: ImportCandidateChanges(
                paymentMethodName: "广发卡",
                paymentTypeName: "文娱游购开支",
                paymentDetailName: "饮食游乐费"
            )
        )
        _ = try useCases.confirmImportCandidates(ids: [secondCandidate.id])

        let thirdContents = """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-17 12:30:45,餐饮美食,冲突便利店,/,午餐套餐,支出,35.00,广发卡,交易成功,ALIPAY-MEMORY-CONFLICT-003\t,\t,,
        """
        let thirdBatch = try useCases.createImportBatch(source: .alipay, fileName: "memory-conflict-3.csv", contents: thirdContents)
        let thirdCandidate = try XCTUnwrap(thirdBatch.candidates.first)

        XCTAssertNil(thirdCandidate.paymentTypeName)
        XCTAssertNil(thirdCandidate.paymentDetailName)
        XCTAssertNil(thirdCandidate.paymentTypeId)
        XCTAssertNil(thirdCandidate.paymentDetailId)
    }

    func testImportMemoryUsesCurrentImportedJournalClassificationAfterEdit() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()
        try insertPaymentTypeAndDetailForTest(database: database, typeName: "文娱游购开支", detailName: "饮食游乐费")

        let firstContents = """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-15 12:30:45,餐饮美食,编辑记忆店,/,晚餐套餐,支出,100.00,广发卡,交易成功,ALIPAY-MEMORY-EDIT-001\t,\t,,
        """
        let firstBatch = try useCases.createImportBatch(source: .alipay, fileName: "memory-edit-1.csv", contents: firstContents)
        let firstCandidate = try XCTUnwrap(firstBatch.candidates.first)
        _ = try useCases.updateImportCandidate(
            id: firstCandidate.id,
            changes: ImportCandidateChanges(
                paymentMethodName: "广发卡",
                paymentTypeName: "生活必要开支",
                paymentDetailName: "伙食费"
            )
        )
        let record = try XCTUnwrap(try useCases.confirmImportCandidates(ids: [firstCandidate.id]).first)

        _ = try useCases.updateJournalRecord(
            id: record.id,
            changes: JournalRecordChanges(
                paymentTypeName: "文娱游购开支",
                paymentDetailName: "饮食游乐费"
            )
        )

        let secondContents = """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-16 12:30:45,餐饮美食,编辑记忆店,/,晚餐套餐,支出,90.00,广发卡,交易成功,ALIPAY-MEMORY-EDIT-002\t,\t,,
        """
        let secondBatch = try useCases.createImportBatch(source: .alipay, fileName: "memory-edit-2.csv", contents: secondContents)
        let secondCandidate = try XCTUnwrap(secondBatch.candidates.first)

        XCTAssertEqual(secondCandidate.paymentTypeName, "文娱游购开支")
        XCTAssertEqual(secondCandidate.paymentDetailName, "饮食游乐费")
    }

    func testImportMemoryLeavesClassificationEmptyWhenMerchantMatchesButProductDiffers() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let firstContents = """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-15 12:30:45,餐饮美食,商品边界店,/,午餐套餐,支出,100.00,广发卡,交易成功,ALIPAY-MEMORY-PRODUCT-001\t,\t,,
        """
        let firstBatch = try useCases.createImportBatch(source: .alipay, fileName: "memory-product-1.csv", contents: firstContents)
        let firstCandidate = try XCTUnwrap(firstBatch.candidates.first)
        _ = try useCases.updateImportCandidate(
            id: firstCandidate.id,
            changes: ImportCandidateChanges(
                paymentMethodName: "广发卡",
                paymentTypeName: "生活必要开支",
                paymentDetailName: "伙食费"
            )
        )
        _ = try useCases.confirmImportCandidates(ids: [firstCandidate.id])

        let secondContents = """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-16 12:30:45,餐饮美食,商品边界店,/,晚餐套餐,支出,80.00,广发卡,交易成功,ALIPAY-MEMORY-PRODUCT-002\t,\t,,
        """
        let secondBatch = try useCases.createImportBatch(source: .alipay, fileName: "memory-product-2.csv", contents: secondContents)
        let secondCandidate = try XCTUnwrap(secondBatch.candidates.first)

        XCTAssertNil(secondCandidate.paymentTypeName)
        XCTAssertNil(secondCandidate.paymentDetailName)
        XCTAssertNil(secondCandidate.paymentTypeId)
        XCTAssertNil(secondCandidate.paymentDetailId)
    }

    func testImportMemoryLeavesClassificationEmptyWhenProductMatchesButMerchantDiffers() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let firstContents = """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-15 12:30:45,餐饮美食,商户边界一店,/,固定套餐,支出,100.00,广发卡,交易成功,ALIPAY-MEMORY-MERCHANT-001\t,\t,,
        """
        let firstBatch = try useCases.createImportBatch(source: .alipay, fileName: "memory-merchant-1.csv", contents: firstContents)
        let firstCandidate = try XCTUnwrap(firstBatch.candidates.first)
        _ = try useCases.updateImportCandidate(
            id: firstCandidate.id,
            changes: ImportCandidateChanges(
                paymentMethodName: "广发卡",
                paymentTypeName: "生活必要开支",
                paymentDetailName: "伙食费"
            )
        )
        _ = try useCases.confirmImportCandidates(ids: [firstCandidate.id])

        let secondContents = """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-16 12:30:45,餐饮美食,商户边界二店,/,固定套餐,支出,80.00,广发卡,交易成功,ALIPAY-MEMORY-MERCHANT-002\t,\t,,
        """
        let secondBatch = try useCases.createImportBatch(source: .alipay, fileName: "memory-merchant-2.csv", contents: secondContents)
        let secondCandidate = try XCTUnwrap(secondBatch.candidates.first)

        XCTAssertNil(secondCandidate.paymentTypeName)
        XCTAssertNil(secondCandidate.paymentDetailName)
        XCTAssertNil(secondCandidate.paymentTypeId)
        XCTAssertNil(secondCandidate.paymentDetailId)
    }

    func testImportMemoryDoesNotPrefillAcrossAlipayAndWechatSources() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let alipayContents = """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-15 12:30:45,餐饮美食,来源隔离店,/,通用套餐,支出,100.00,广发卡,交易成功,ALIPAY-MEMORY-SOURCE-001\t,\t,,
        """
        let alipayBatch = try useCases.createImportBatch(source: .alipay, fileName: "memory-source-alipay.csv", contents: alipayContents)
        let alipayCandidate = try XCTUnwrap(alipayBatch.candidates.first)
        _ = try useCases.updateImportCandidate(
            id: alipayCandidate.id,
            changes: ImportCandidateChanges(
                paymentMethodName: "广发卡",
                paymentTypeName: "生活必要开支",
                paymentDetailName: "伙食费"
            )
        )
        _ = try useCases.confirmImportCandidates(ids: [alipayCandidate.id])

        let wechatContents = """
        微信支付账单明细,,,,,,,,
        ----------------------微信支付账单明细列表--------------------,,,,,,,,
        交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
        2026-04-16 12:30:45,商户消费,来源隔离店,通用套餐,支出,¥80.00,零钱,支付成功,WECHAT-MEMORY-SOURCE-001\t,\t,/
        """
        let wechatBatch = try useCases.createImportBatch(source: .wechat, fileName: "memory-source-wechat.csv", contents: wechatContents)
        let wechatCandidate = try XCTUnwrap(wechatBatch.candidates.first)

        XCTAssertNil(wechatCandidate.paymentTypeName)
        XCTAssertNil(wechatCandidate.paymentDetailName)
        XCTAssertNil(wechatCandidate.paymentTypeId)
        XCTAssertNil(wechatCandidate.paymentDetailId)
    }

    func testImportMemoryLeavesClassificationEmptyWhenMerchantOrProductIsBlankOrSlash() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let blankMerchantContents = """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-15 12:30:45,餐饮美食,/,/,固定套餐,支出,100.00,广发卡,交易成功,ALIPAY-MEMORY-BLANK-001\t,\t,,
        2026-04-16 12:30:45,餐饮美食,/,/,固定套餐,支出,80.00,广发卡,交易成功,ALIPAY-MEMORY-BLANK-002\t,\t,,
        """
        let blankMerchantFirstBatch = try useCases.createImportBatch(source: .alipay, fileName: "memory-blank-merchant-1.csv", contents: blankMerchantContents)
        let blankMerchantFirstCandidate = try XCTUnwrap(blankMerchantFirstBatch.candidates.first { $0.rawTransactionId == "ALIPAY-MEMORY-BLANK-001" })
        _ = try useCases.updateImportCandidate(
            id: blankMerchantFirstCandidate.id,
            changes: ImportCandidateChanges(
                paymentMethodName: "广发卡",
                paymentTypeName: "生活必要开支",
                paymentDetailName: "伙食费"
            )
        )
        _ = try useCases.confirmImportCandidates(ids: [blankMerchantFirstCandidate.id])

        let blankMerchantSecondBatch = try useCases.createImportBatch(
            source: .alipay,
            fileName: "memory-blank-merchant-2.csv",
            contents: """
            -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
            交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
            2026-04-17 12:30:45,餐饮美食,/,/,固定套餐,支出,35.00,广发卡,交易成功,ALIPAY-MEMORY-BLANK-003\t,\t,,
            """
        )
        let blankMerchantCandidate = try XCTUnwrap(blankMerchantSecondBatch.candidates.first)

        let slashProductContents = """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-15 12:30:45,餐饮美食,斜杠商品店,/,/,支出,100.00,广发卡,交易成功,ALIPAY-MEMORY-SLASH-PRODUCT-001\t,\t,,
        """
        let slashProductFirstBatch = try useCases.createImportBatch(source: .alipay, fileName: "memory-slash-product-1.csv", contents: slashProductContents)
        let slashProductFirstCandidate = try XCTUnwrap(slashProductFirstBatch.candidates.first)
        _ = try useCases.updateImportCandidate(
            id: slashProductFirstCandidate.id,
            changes: ImportCandidateChanges(
                paymentMethodName: "广发卡",
                paymentTypeName: "生活必要开支",
                paymentDetailName: "伙食费"
            )
        )
        _ = try useCases.confirmImportCandidates(ids: [slashProductFirstCandidate.id])

        let slashProductSecondBatch = try useCases.createImportBatch(
            source: .alipay,
            fileName: "memory-slash-product-2.csv",
            contents: """
            -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
            交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
            2026-04-16 12:30:45,餐饮美食,斜杠商品店,/,/,支出,80.00,广发卡,交易成功,ALIPAY-MEMORY-SLASH-PRODUCT-002\t,\t,,
            """
        )
        let slashProductCandidate = try XCTUnwrap(slashProductSecondBatch.candidates.first)

        XCTAssertNil(blankMerchantCandidate.paymentTypeName)
        XCTAssertNil(blankMerchantCandidate.paymentDetailName)
        XCTAssertNil(blankMerchantCandidate.paymentTypeId)
        XCTAssertNil(blankMerchantCandidate.paymentDetailId)
        XCTAssertNil(slashProductCandidate.paymentTypeName)
        XCTAssertNil(slashProductCandidate.paymentDetailName)
        XCTAssertNil(slashProductCandidate.paymentTypeId)
        XCTAssertNil(slashProductCandidate.paymentDetailId)
    }

    func testImportMemoryDoesNotUseDeletedImportedJournalRecord() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let firstContents = """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-15 12:30:45,餐饮美食,删除记忆店,/,午餐套餐,支出,100.00,广发卡,交易成功,ALIPAY-MEMORY-DELETE-001\t,\t,,
        """
        let firstBatch = try useCases.createImportBatch(source: .alipay, fileName: "memory-delete-1.csv", contents: firstContents)
        let firstCandidate = try XCTUnwrap(firstBatch.candidates.first)
        _ = try useCases.updateImportCandidate(
            id: firstCandidate.id,
            changes: ImportCandidateChanges(
                paymentMethodName: "广发卡",
                paymentTypeName: "生活必要开支",
                paymentDetailName: "伙食费"
            )
        )
        let record = try XCTUnwrap(try useCases.confirmImportCandidates(ids: [firstCandidate.id]).first)

        try useCases.deleteJournalRecord(id: record.id)

        let secondContents = """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-16 12:30:45,餐饮美食,删除记忆店,/,午餐套餐,支出,80.00,广发卡,交易成功,ALIPAY-MEMORY-DELETE-002\t,\t,,
        """
        let secondBatch = try useCases.createImportBatch(source: .alipay, fileName: "memory-delete-2.csv", contents: secondContents)
        let secondCandidate = try XCTUnwrap(secondBatch.candidates.first)

        XCTAssertNil(secondCandidate.paymentTypeName)
        XCTAssertNil(secondCandidate.paymentDetailName)
        XCTAssertNil(secondCandidate.paymentTypeId)
        XCTAssertNil(secondCandidate.paymentDetailId)
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
        let candidate = try XCTUnwrap(batch.candidates.first { $0.rawTransactionId == "ALIPAY-001" })
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

    func testRowsWithoutTransactionIdUseFullRawPayloadFingerprint() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let result = try useCases.createImportBatch(
            source: .wechat,
            fileName: "wechat-no-transaction-id.csv",
            contents: """
            微信支付账单明细,,,,,,,,
            ----------------------微信支付账单明细列表--------------------,,,,,,,,
            交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
            2026-04-15 10:00:00,商户消费,同一商户,同一商品,支出,¥10.00,零钱,支付成功,/,M-001,/
            2026-04-15 10:00:00,商户消费,同一商户,同一商品,支出,¥10.00,中国银行储蓄卡,支付成功,/,M-002,/
            """
        )

        XCTAssertEqual(result.candidates.count, 2)
        XCTAssertFalse(result.issues.contains { $0.code == .duplicate })
        XCTAssertTrue(result.candidates.allSatisfy { $0.rawTransactionId == nil })
        XCTAssertEqual(Set(result.candidates.map(\.rawFingerprint)).count, 2)
    }

    func testZeroAndNullAmountsStillCreateImportCandidates() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let alipay = try useCases.createImportBatch(
            source: .alipay,
            fileName: "alipay-zero-null.csv",
            contents: """
            -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
            交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
            2026-04-15 09:00:00,转账,朋友,/,零金额,不计收支,0.00,余额,交易成功,ALIPAY-ZERO-001\t,\t,,
            2026-04-15 10:00:00,转账,朋友,/,空金额,不计收支,,余额,交易成功,ALIPAY-NULL-001\t,\t,,
            2026-04-15 11:00:00,转账,朋友,/,斜杠金额,不计收支,/,余额,交易成功,ALIPAY-NULL-002\t,\t,,
            """
        )
        let wechat = try useCases.createImportBatch(
            source: .wechat,
            fileName: "wechat-zero-null.csv",
            contents: """
            微信支付账单明细,,,,,,,,
            ----------------------微信支付账单明细列表--------------------,,,,,,,,
            交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
            2026-04-15 12:00:00,商户消费,商户,零金额,支出,¥0.00,零钱,支付成功,WECHAT-ZERO-001\t,\t,/
            2026-04-15 13:00:00,商户消费,商户,null金额,支出,null,零钱,支付成功,WECHAT-NULL-001\t,\t,/
            """
        )

        XCTAssertEqual(alipay.candidates.count, 3)
        XCTAssertEqual(wechat.candidates.count, 2)
        XCTAssertFalse((alipay.issues + wechat.issues).contains { $0.code == .invalidAmount })
        XCTAssertTrue((alipay.candidates + wechat.candidates).allSatisfy { $0.amount == Decimal(0) })

        let updated = try useCases.updateImportCandidate(
            id: try XCTUnwrap(alipay.candidates.first).id,
            changes: ImportCandidateChanges(
                amount: Decimal(0),
                paymentMethodName: "广发卡",
                paymentTypeName: "生活必要开支",
                paymentDetailName: "伙食费"
            )
        )
        XCTAssertEqual(updated.amount, Decimal(0))
        let record = try XCTUnwrap(try useCases.confirmImportCandidates(ids: [updated.id]).first)
        XCTAssertEqual(record.amount, Decimal(0))
        XCTAssertEqual(record.sourceImportCandidateId, updated.id)
    }

    func testDeleteImportedRecordAllowsSameRawLineToBeImportedAgain() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()
        let contents = """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-15 12:30:45,餐饮美食,便利店,/,午餐,支出,100.00,广发卡,交易成功,ALIPAY-REIMPORT-001\t,\t,,
        """
        let batch = try useCases.createImportBatch(source: .alipay, fileName: "reimport.csv", contents: contents)
        let candidate = try XCTUnwrap(batch.candidates.first)
        _ = try useCases.updateImportCandidate(
            id: candidate.id,
            changes: ImportCandidateChanges(
                paymentMethodName: "广发卡",
                paymentTypeName: "生活必要开支",
                paymentDetailName: "伙食费"
            )
        )
        let record = try XCTUnwrap(try useCases.confirmImportCandidates(ids: [candidate.id]).first)

        try useCases.deleteJournalRecord(id: record.id)
        let importedAgain = try useCases.createImportBatch(source: .alipay, fileName: "reimport-again.csv", contents: contents)

        XCTAssertEqual(importedAgain.candidates.count, 1)
        XCTAssertFalse(importedAgain.issues.contains { $0.code == .duplicate })
        XCTAssertEqual(importedAgain.candidates.first?.rawTransactionId, "ALIPAY-REIMPORT-001")
    }

    func testImportCreatesCandidatesForAllRevenueAndNeutralRows() throws {
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
        XCTAssertEqual(alipayNeutral.candidates.count, 3)
        XCTAssertTrue(alipayNeutral.issues.filter { $0.code == .unsupportedDirection }.isEmpty)
        XCTAssertEqual(Set(alipayNeutral.candidates.compactMap(\.rawTransactionId)), [
            "ALIPAY-NEUTRAL-001",
            "ALIPAY-NEUTRAL-002",
            "ALIPAY-VALID-001"
        ])

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
        XCTAssertEqual(wechatNeutral.candidates.count, 3)
        XCTAssertTrue(wechatNeutral.issues.filter { $0.code == .unsupportedDirection }.isEmpty)
        XCTAssertEqual(Set(wechatNeutral.candidates.compactMap(\.rawTransactionId)), [
            "WX-NEUTRAL-001",
            "WX-NEUTRAL-002",
            "WX-VALID-001"
        ])

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
        let transferIncome = try XCTUnwrap(wechatTransfer.candidates.first { $0.rawTransactionId == "WX-TRANSFER-001" })
        let transferExpense = try XCTUnwrap(wechatTransfer.candidates.first { $0.rawTransactionId == "WX-TRANSFER-002" })
        XCTAssertEqual(transferIncome.amount, Decimal(70))
        XCTAssertEqual(transferExpense.amount, Decimal(20))
    }

    func testP1AlipayWechatImportEndToEnd() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let alipay = try useCases.createImportBatch(source: .alipay, fileName: "alipay-minimal.csv", contents: fixture("alipay-minimal.csv"))
        let wechat = try useCases.createImportBatch(source: .wechat, fileName: "wechat-minimal.csv", contents: fixture("wechat-minimal.csv"))
        let ids = (alipay.candidates + wechat.candidates)
            .filter { ["ALIPAY-001", "WECHAT-001"].contains($0.rawTransactionId) }
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

    private func fixtureData(_ name: String) throws -> Data {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let fixtureURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        return try Data(contentsOf: fixtureURL)
    }

    private func decimal(_ value: String) throws -> Decimal {
        try XCTUnwrap(Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")))
    }

    private func insertPaymentTypeAndDetailForTest(
        database: LedgerDatabase,
        typeName: String,
        detailName: String
    ) throws {
        try database.writer.write { db in
            let now = ISO8601DateFormatter().string(from: Date())
            // 查询或插入 type（种子数据可能已存在同名 type）
            let typeId: String
            if let existing = try? Row.fetchOne(db, sql: "SELECT id FROM payment_types WHERE name = ?", arguments: [typeName]) {
                typeId = existing["id"]
            } else {
                typeId = UUID().uuidString
                try db.execute(sql: """
                    INSERT INTO payment_types (id, name, element, is_active, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [typeId, typeName, AccountingElement.expense.rawValue, true, now, now])
            }
            // 查询或插入 detail
            if (try? Row.fetchOne(db, sql: "SELECT id FROM payment_details WHERE name = ? AND payment_type_id = ?", arguments: [detailName, typeId])) == nil {
                let detailId = UUID().uuidString
                try db.execute(sql: """
                    INSERT INTO payment_details (id, name, payment_type_id, is_active, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [detailId, detailName, typeId, true, now, now])
            }
        }
    }
}
