import Foundation
import XCTest
@testable import MingZhangCore

final class P1SettingsFlowTests: XCTestCase {
    func testSeedIncludesFullDefaultSettingsAndSemanticMetadata() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)

        try useCases.initializeLedgerSeed()
        try useCases.initializeLedgerSeed()

        let userVisibleMethods = try useCases.queryPaymentMethods(includeInternal: false)
        let allMethods = try useCases.queryPaymentMethods(includeInternal: true)
        let types = try useCases.queryPaymentTypes()
        let details = try useCases.queryPaymentDetails()

        XCTAssertEqual(
            Set(userVisibleMethods.map(\.name)),
            Set(["现金", "电子钱包余额", "花呗", "广发卡", "招商卡", "平安卡", "北京卡", "蚂蚁卡", "京东白条", "账务处理"])
        )
        XCTAssertNil(userVisibleMethods.first { $0.name == "待补真实账户" })
        XCTAssertEqual(allMethods.first { $0.name == "待补真实账户" }?.semanticTags, ["待补真实账户"])
        XCTAssertEqual(allMethods.first { $0.name == "电子钱包余额" }?.semanticTags, ["资产型"])
        XCTAssertEqual(allMethods.first { $0.name == "广发卡" }?.semanticTags, ["负债型"])
        XCTAssertTrue(allMethods.allSatisfy { $0.configVersion == 1 })

        XCTAssertEqual(Set(types.map(\.name)), Set([
            "生活必要开支", "文娱游购开支", "财务费用开支", "投资自身开支", "其他必要开支",
            "工作收入", "理财收入", "其他收入",
            "资产类支出", "负债类增记", "负债类减记"
        ]))
        XCTAssertEqual(types.first { $0.name == "生活必要开支" }?.semanticTags, ["支出"])
        XCTAssertEqual(types.first { $0.name == "资产类支出" }?.semanticTags, ["资产"])

        let detailNames = Set(details.map(\.name))
        XCTAssertTrue(detailNames.isSuperset(of: [
            "伙食费", "交通通信费", "房租费", "饮食游乐费", "日常购物费",
            "金融利息支出", "投资亏损", "账单还款", "账单补记",
            "金融资产投资", "长期待摊费用", "投资收益"
        ]))
        XCTAssertEqual(details.first { $0.name == "长期待摊费用" }?.semanticTags, ["递延资产"])
        XCTAssertTrue(details.allSatisfy { $0.configVersion == 1 })
    }

    func testRenamingReferencedSettingsUpdatesHistoricalRecordsAndReadModels() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let record = try useCases.createManualRecord(input: sampleInput(amount: Decimal(100)))
        let guangfa = try XCTUnwrap(try useCases.queryPaymentMethods().first { $0.name == "广发卡" })
        let foodType = try XCTUnwrap(try useCases.queryPaymentTypes().first { $0.name == "生活必要开支" })
        let foodDetail = try XCTUnwrap(try useCases.queryPaymentDetails().first { $0.name == "伙食费" })

        _ = try useCases.updatePaymentMethod(
            id: guangfa.id,
            input: UpdatePaymentMethodInput(name: "广发信用卡")
        )
        _ = try useCases.updatePaymentType(
            id: foodType.id,
            input: UpdatePaymentTypeInput(name: "基本生活开支")
        )
        _ = try useCases.updatePaymentDetail(
            id: foodDetail.id,
            input: UpdatePaymentDetailInput(name: "餐食费")
        )

        let updatedRecord = try useCases.getJournalRecordDetail(id: record.id)
        XCTAssertEqual(updatedRecord.paymentMethodName, "广发信用卡")
        XCTAssertEqual(updatedRecord.paymentTypeName, "基本生活开支")
        XCTAssertEqual(updatedRecord.paymentDetailName, "餐食费")
        XCTAssertEqual(
            try useCases.queryBalanceSummary(accountMonth: "2026-04").liabilityItems,
            [
                LiabilityBalanceItem(
                    name: "广发信用卡",
                    objectKey: "liability:广发信用卡",
                    amount: Decimal(100),
                    formedAmount: Decimal(100),
                    repaidAmount: Decimal(0),
                    costAmount: Decimal(0),
                    sourceRecordIds: [record.id]
                )
            ]
        )
        XCTAssertEqual(
            try useCases.queryStatisticsSummary(accountMonth: "2026-04").expenseByType,
            [ExpenseTypeSummary(typeName: "基本生活开支", amount: Decimal(100), sourceRecordIds: [record.id])]
        )
    }

    func testDisabledSettingsRemainHistoricalButCannotBeUsedForFutureRecords() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let record = try useCases.createManualRecord(input: sampleInput(amount: Decimal(100)))
        let guangfa = try XCTUnwrap(try useCases.queryPaymentMethods().first { $0.name == "广发卡" })

        try useCases.disablePaymentMethod(id: guangfa.id)

        XCTAssertFalse(try XCTUnwrap(try useCases.queryPaymentMethods().first { $0.id == guangfa.id }).isActive)
        XCTAssertEqual(try useCases.getJournalRecordDetail(id: record.id).paymentMethodName, "广发卡")
        XCTAssertThrowsError(try useCases.createManualRecord(input: sampleInput(amount: Decimal(50)))) { error in
            XCTAssertEqual(error as? MingZhangError, .validation("收付手段已停用：广发卡"))
        }
    }

    func testHistoricalRecordCanBeEditedAfterReferencedSettingsAreDisabled() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)
        try useCases.initializeLedgerSeed()

        let record = try useCases.createManualRecord(input: sampleInput(amount: Decimal(100)))
        let guangfa = try XCTUnwrap(try useCases.queryPaymentMethods().first { $0.name == "广发卡" })
        let foodType = try XCTUnwrap(try useCases.queryPaymentTypes().first { $0.name == "生活必要开支" })
        let foodDetail = try XCTUnwrap(try useCases.queryPaymentDetails().first { $0.name == "伙食费" })

        try useCases.disablePaymentMethod(id: guangfa.id)
        try useCases.disablePaymentType(id: foodType.id)
        try useCases.disablePaymentDetail(id: foodDetail.id)

        let updated = try useCases.updateJournalRecord(
            id: record.id,
            changes: JournalRecordChanges(
                paymentMethodName: "广发卡",
                amount: Decimal(120),
                paymentTypeName: "生活必要开支",
                paymentDetailName: "伙食费",
                note: "历史修正"
            )
        )

        XCTAssertEqual(updated.amount, Decimal(120))
        XCTAssertEqual(updated.paymentMethodName, "广发卡")
        XCTAssertEqual(updated.paymentTypeName, "生活必要开支")
        XCTAssertEqual(updated.paymentDetailName, "伙食费")
        XCTAssertEqual(updated.note, "历史修正")
    }
}

private func sampleInput(
    accountMonth: String = "2026-04",
    amount: Decimal
) throws -> CreateManualRecordInput {
    CreateManualRecordInput(
        accountMonth: accountMonth,
        occurredAt: try p1Date("2026-04-15T12:00:00Z"),
        paymentMethodName: "广发卡",
        amount: amount,
        paymentTypeName: "生活必要开支",
        paymentDetailName: "伙食费",
        note: "午餐"
    )
}

private func p1Date(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = formatter.date(from: value) else {
        throw MingZhangError.invalidDate(value)
    }
    return date
}
