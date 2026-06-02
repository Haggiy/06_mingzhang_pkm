import Foundation
import XCTest
@testable import MingZhangCore

final class P1LiabilityRepaymentTests: XCTestCase {
    func testCreateLiabilityCostIncreasesCostAndRemainingLiabilityWithoutTouchingCash() throws {
        let useCases = try makeUseCases()
        let expense = try useCases.createManualRecord(input: creditCardExpense())

        let cost = try useCases.createLiabilityCost(input: CreateLiabilityCostInput(
            accountMonth: "2026-04",
            occurredAt: try Date.iso8601("2026-04-09T09:00:00Z"),
            liabilityObjectKey: "liability:广发卡",
            amount: Decimal(30),
            kind: .interest,
            note: "广发卡利息"
        ))

        XCTAssertEqual(cost.recordSource, .manual)
        XCTAssertEqual(cost.paymentMethodName, "广发卡")
        XCTAssertEqual(cost.paymentTypeName, "财务费用开支")
        XCTAssertEqual(cost.paymentDetailName, "金融利息支出")
        XCTAssertEqual(cost.objectKey, "liability:广发卡")

        let balance = try useCases.queryBalanceSummary(accountMonth: "2026-04")
        XCTAssertEqual(balance.cashBalance, Decimal(0))
        XCTAssertEqual(balance.liabilityItems, [
            LiabilityBalanceItem(
                name: "广发卡",
                objectKey: "liability:广发卡",
                amount: Decimal(130),
                formedAmount: Decimal(100),
                repaidAmount: Decimal(0),
                costAmount: Decimal(30),
                sourceRecordIds: [expense.id, cost.id]
            )
        ])

        let detail = try useCases.queryLiabilityDetail(accountMonth: "2026-04", objectKey: "liability:广发卡")
        XCTAssertEqual(detail.formedAmount, Decimal(100))
        XCTAssertEqual(detail.repaidAmount, Decimal(0))
        XCTAssertEqual(detail.costAmount, Decimal(30))
        XCTAssertEqual(detail.remainingAmount, Decimal(130))
        XCTAssertEqual(detail.formationSourceRecordIds, [expense.id])
        XCTAssertEqual(detail.costSourceRecordIds, [cost.id])
        XCTAssertEqual(detail.sourceRecordIds, [expense.id, cost.id])

        XCTAssertEqual(try useCases.queryHomeSummary(accountMonth: "2026-04").expenseTotal, Decimal(30))
        XCTAssertEqual(try useCases.queryStatisticsSummary(accountMonth: "2026-04").expenseByType, [
            ExpenseTypeSummary(typeName: "财务费用开支", amount: Decimal(30), sourceRecordIds: [cost.id])
        ])
    }

    func testLiabilityCostAndRepaymentCoexistInSameLiabilityObject() throws {
        let useCases = try makeUseCases()
        let expense = try useCases.createManualRecord(input: creditCardExpense())
        let cost = try useCases.createLiabilityCost(input: CreateLiabilityCostInput(
            accountMonth: "2026-04",
            occurredAt: try Date.iso8601("2026-04-09T09:00:00Z"),
            liabilityObjectKey: "liability:广发卡",
            amount: Decimal(30),
            kind: .fee,
            note: "广发卡手续费"
        ))
        let repayment = try useCases.createLiabilityRepayment(input: CreateLiabilityRepaymentInput(
            accountMonth: "2026-04",
            occurredAt: try Date.iso8601("2026-04-10T09:00:00Z"),
            liabilityObjectKey: "liability:广发卡",
            amount: Decimal(80),
            paymentMethodName: "电子钱包余额"
        ))

        XCTAssertEqual(cost.paymentDetailName, "金融手续费与罚款")

        let balance = try useCases.queryBalanceSummary(accountMonth: "2026-04")
        XCTAssertEqual(balance.cashBalance, Decimal(-80))
        XCTAssertEqual(balance.liabilityItems, [
            LiabilityBalanceItem(
                name: "广发卡",
                objectKey: "liability:广发卡",
                amount: Decimal(50),
                formedAmount: Decimal(100),
                repaidAmount: Decimal(80),
                costAmount: Decimal(30),
                sourceRecordIds: [expense.id, repayment.id, cost.id]
            )
        ])
    }

    func testUpdatingAndDeletingLiabilityCostSynchronizesDerivedResults() throws {
        let useCases = try makeUseCases()
        let expense = try useCases.createManualRecord(input: creditCardExpense())
        let cost = try useCases.createLiabilityCost(input: CreateLiabilityCostInput(
            accountMonth: "2026-04",
            occurredAt: try Date.iso8601("2026-04-09T09:00:00Z"),
            liabilityObjectKey: "liability:广发卡",
            amount: Decimal(30),
            kind: .interest
        ))

        _ = try useCases.updateJournalRecord(id: cost.id, changes: JournalRecordChanges(amount: Decimal(10)))

        var balance = try useCases.queryBalanceSummary(accountMonth: "2026-04")
        XCTAssertEqual(balance.liabilityItems, [
            LiabilityBalanceItem(
                name: "广发卡",
                objectKey: "liability:广发卡",
                amount: Decimal(110),
                formedAmount: Decimal(100),
                repaidAmount: Decimal(0),
                costAmount: Decimal(10),
                sourceRecordIds: [expense.id, cost.id]
            )
        ])

        XCTAssertThrowsError(try useCases.updateJournalRecord(id: cost.id, changes: JournalRecordChanges(amount: Decimal(0)))) { error in
            XCTAssertEqual(error as? MingZhangError, .validation("负债成本金额必须大于 0"))
        }

        try useCases.deleteJournalRecord(id: cost.id)

        balance = try useCases.queryBalanceSummary(accountMonth: "2026-04")
        XCTAssertEqual(balance.liabilityItems, [
            LiabilityBalanceItem(
                name: "广发卡",
                objectKey: "liability:广发卡",
                amount: Decimal(100),
                formedAmount: Decimal(100),
                repaidAmount: Decimal(0),
                costAmount: Decimal(0),
                sourceRecordIds: [expense.id]
            )
        ])
        XCTAssertTrue(try useCases.queryStatisticsSummary(accountMonth: "2026-04").expenseByType.isEmpty)
    }

    func testLiabilityCostValidationRequiresPositiveAmountAndValidObject() throws {
        let useCases = try makeUseCases()

        XCTAssertThrowsError(try useCases.createLiabilityCost(input: CreateLiabilityCostInput(
            accountMonth: "2026-04",
            occurredAt: try Date.iso8601("2026-04-09T09:00:00Z"),
            liabilityObjectKey: "liability:广发卡",
            amount: Decimal(0),
            kind: .interest
        ))) { error in
            XCTAssertEqual(error as? MingZhangError, .validation("负债成本金额必须大于 0"))
        }

        XCTAssertThrowsError(try useCases.createLiabilityCost(input: CreateLiabilityCostInput(
            accountMonth: "2026-04",
            occurredAt: try Date.iso8601("2026-04-09T09:00:00Z"),
            liabilityObjectKey: "liability:电子钱包余额",
            amount: Decimal(10),
            kind: .interest
        ))) { error in
            XCTAssertEqual(error as? MingZhangError, .validation("负债对象必须指向负债类收付手段"))
        }
    }

    func testCreateLiabilityRepaymentReducesCashAndLiabilityAcrossMonths() throws {
        let useCases = try makeUseCases()
        let expense = try useCases.createManualRecord(input: creditCardExpense())

        let repayment = try useCases.createLiabilityRepayment(input: CreateLiabilityRepaymentInput(
            accountMonth: "2026-04",
            occurredAt: try Date.iso8601("2026-04-10T09:00:00Z"),
            liabilityObjectKey: "liability:广发卡",
            amount: Decimal(100),
            paymentMethodName: "电子钱包余额",
            note: "广发卡还款"
        ))

        XCTAssertEqual(repayment.recordSource, .manual)
        XCTAssertEqual(repayment.paymentMethodName, "电子钱包余额")
        XCTAssertEqual(repayment.paymentTypeName, "负债类减记")
        XCTAssertEqual(repayment.paymentDetailName, "账单还款")
        XCTAssertEqual(repayment.objectKey, "liability:广发卡")

        XCTAssertEqual(try useCases.queryBalanceSummary(accountMonth: "2026-03").liabilityItems, [
            LiabilityBalanceItem(
                name: "广发卡",
                objectKey: "liability:广发卡",
                amount: Decimal(100),
                formedAmount: Decimal(100),
                repaidAmount: Decimal(0),
                costAmount: Decimal(0),
                sourceRecordIds: [expense.id]
            )
        ])

        let aprilBalance = try useCases.queryBalanceSummary(accountMonth: "2026-04")
        XCTAssertEqual(aprilBalance.cashBalance, Decimal(-100))
        XCTAssertEqual(aprilBalance.cashSourceRecordIds, [repayment.id])
        XCTAssertEqual(aprilBalance.liabilityItems, [
            LiabilityBalanceItem(
                name: "广发卡",
                objectKey: "liability:广发卡",
                amount: Decimal(0),
                formedAmount: Decimal(100),
                repaidAmount: Decimal(100),
                costAmount: Decimal(0),
                sourceRecordIds: [expense.id, repayment.id]
            )
        ])

        let detail = try useCases.queryLiabilityDetail(accountMonth: "2026-04", objectKey: "liability:广发卡")
        XCTAssertEqual(detail.formedAmount, Decimal(100))
        XCTAssertEqual(detail.repaidAmount, Decimal(100))
        XCTAssertEqual(detail.costAmount, Decimal(0))
        XCTAssertEqual(detail.remainingAmount, Decimal(0))
        XCTAssertEqual(detail.formationSourceRecordIds, [expense.id])
        XCTAssertEqual(detail.repaymentSourceRecordIds, [repayment.id])
        XCTAssertEqual(detail.sourceRecordIds, [expense.id, repayment.id])
    }

    func testUpdatingAndDeletingRepaymentSynchronizesDerivedResults() throws {
        let useCases = try makeUseCases()
        let expense = try useCases.createManualRecord(input: creditCardExpense())
        let repayment = try useCases.createLiabilityRepayment(input: CreateLiabilityRepaymentInput(
            accountMonth: "2026-04",
            occurredAt: try Date.iso8601("2026-04-10T09:00:00Z"),
            liabilityObjectKey: "liability:广发卡",
            amount: Decimal(100),
            paymentMethodName: "电子钱包余额"
        ))

        _ = try useCases.updateJournalRecord(id: repayment.id, changes: JournalRecordChanges(amount: Decimal(60)))

        var balance = try useCases.queryBalanceSummary(accountMonth: "2026-04")
        XCTAssertEqual(balance.cashBalance, Decimal(-60))
        XCTAssertEqual(balance.liabilityItems, [
            LiabilityBalanceItem(
                name: "广发卡",
                objectKey: "liability:广发卡",
                amount: Decimal(40),
                formedAmount: Decimal(100),
                repaidAmount: Decimal(60),
                costAmount: Decimal(0),
                sourceRecordIds: [expense.id, repayment.id]
            )
        ])

        try useCases.deleteJournalRecord(id: repayment.id)

        balance = try useCases.queryBalanceSummary(accountMonth: "2026-04")
        XCTAssertEqual(balance.cashBalance, Decimal(0))
        XCTAssertEqual(balance.liabilityItems, [
            LiabilityBalanceItem(
                name: "广发卡",
                objectKey: "liability:广发卡",
                amount: Decimal(100),
                formedAmount: Decimal(100),
                repaidAmount: Decimal(0),
                costAmount: Decimal(0),
                sourceRecordIds: [expense.id]
            )
        ])
    }

    func testImportRepaymentCandidateCarriesLiabilityObjectKeyIntoJournalRecord() throws {
        let useCases = try makeUseCases()
        _ = try useCases.createManualRecord(input: creditCardExpense())
        let batch = try useCases.createImportBatch(
            source: .alipay,
            fileName: "repayment.csv",
            contents: """
            -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
            交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
            2026-04-10 09:00:00,信用卡还款,广发银行信用卡,/,信用卡还款,不计收支,100.00,电子钱包余额,交易成功,ALIPAY-REPAY-001\t,\t,,
            """
        )
        let candidate = try XCTUnwrap(batch.candidates.first)

        let updated = try useCases.updateImportCandidate(
            id: candidate.id,
            changes: ImportCandidateChanges(
                paymentMethodName: "电子钱包余额",
                paymentTypeName: "负债类减记",
                paymentDetailName: "账单还款",
                objectKey: "liability:广发卡"
            )
        )
        XCTAssertEqual(updated.objectKey, "liability:广发卡")

        let record = try XCTUnwrap(try useCases.confirmImportCandidates(ids: [candidate.id]).first)
        XCTAssertEqual(record.recordSource, .import)
        XCTAssertEqual(record.objectKey, "liability:广发卡")
        XCTAssertEqual(try useCases.queryBalanceSummary(accountMonth: "2026-04").cashBalance, Decimal(-100))
        XCTAssertEqual(try useCases.queryLiabilityDetail(accountMonth: "2026-04", objectKey: "liability:广发卡").remainingAmount, Decimal(0))
    }

    func testRepaymentRequiresExplicitLiabilityObject() throws {
        let useCases = try makeUseCases()

        XCTAssertThrowsError(try useCases.createManualRecord(input: CreateManualRecordInput(
            accountMonth: "2026-04",
            occurredAt: try Date.iso8601("2026-04-10T09:00:00Z"),
            paymentMethodName: "电子钱包余额",
            amount: Decimal(100),
            paymentTypeName: "负债类减记",
            paymentDetailName: "账单还款",
            note: "缺少还款对象"
        ))) { error in
            XCTAssertEqual(error as? MingZhangError, .validation("还款记录必须选择负债对象"))
        }
    }

    private func makeUseCases() throws -> LedgerUseCases {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()
        return useCases
    }

    private func creditCardExpense() throws -> CreateManualRecordInput {
        CreateManualRecordInput(
            accountMonth: "2026-03",
            occurredAt: try Date.iso8601("2026-03-15T12:30:00Z"),
            paymentMethodName: "广发卡",
            amount: Decimal(100),
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
