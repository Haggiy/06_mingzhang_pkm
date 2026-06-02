# P1 设置与语义配置 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 实现阶段 F：P1 设置与语义配置，让用户可以维护收付手段、收付类型、类型明细和语义标签，并保护历史流水引用。

**Architecture:** `MingZhangCore` 继续作为配置与流水语义的事实源，设置项只停用不硬删除。新增配置元数据和流水名称快照，后续记账只使用启用配置，历史流水展示使用入账时快照，避免配置改名或停用改写旧记录。SwiftUI 仍通过 `LedgerStore` 调用 Use Case，设置页只做长期记账语义维护，不扩展为导入映射或自动规则中心。

**Tech Stack:** Swift 6、SwiftUI、GRDB、XCTest、Xcode iOS Simulator、本地 SQLite。

---

## 0. 上下文与边界

### 依据

- `docs/work-plans/2026-05-08-ios-product-to-development-roadmap.md` 的阶段 F。
- `docs/specs/settings-and-semantics-spec.md`。
- `docs/prd/mvp-prd.md` 的设置范围和 MVP 不做范围。
- `docs/prd/2026-05-09-v1-feature-acceptance-matrix.md` 的 `A-11` 设置维护。
- 当前实现：
  - `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
  - `ios/MingZhang/MingZhang/LedgerStore.swift`
  - `ios/MingZhang/MingZhang/RootView.swift`

### 当前代码事实

- `payment_methods`、`payment_types`、`payment_details` 已有 `is_active`，但没有 `semantic_tags`、`config_version`、自然语言说明。
- `journal_records` 只保存配置 id，`selectJournalRecordSQL` 通过 join 读取当前配置名称。若设置中重命名 `广发卡`，历史流水会跟着显示新名称，不满足“历史流水引用保护”。
- `SettingsView` 目前只读展示默认配置。
- App target 目前只显式编译 `MingZhangApp.swift`、`LedgerStore.swift`、`RootView.swift`。本阶段不新增 App Swift 文件，避免同时维护 `project.pbxproj`。

### 明确不做

- 不删除配置行，只提供停用。
- 不做导入字段映射配置。
- 不做复杂自动分类规则中心。
- 不做预算、预测、AI、云同步。
- 不新建独立 `SemanticTag` 表；本阶段用配置表上的 JSON 字符串数组保存语义标签。
- 不允许修改已被历史流水引用的结构性语义：收付手段类型、收付类型会计要素、类型明细所属收付类型。需要调整时新建配置项并停用旧项。

## 1. 命名与语义约定

### 新增/扩展公开类型

放在 `MingZhangCore.swift` 现有模型区附近。

```swift
public struct PaymentMethod: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var methodType: PaymentMethodType
    public var isActive: Bool
    public var semanticTags: [String]
    public var configVersion: Int
}

public struct PaymentType: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var element: AccountingElement
    public var isActive: Bool
    public var semanticTags: [String]
    public var configDescription: String?
    public var configVersion: Int
}

public struct PaymentDetail: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var paymentTypeId: UUID
    public var isActive: Bool
    public var semanticTags: [String]
    public var configDescription: String?
    public var configVersion: Int
}
```

### 设置 Use Case 输入

```swift
public struct CreatePaymentMethodInput: Equatable, Sendable {
    public var name: String
    public var methodType: PaymentMethodType
    public var semanticTags: [String]
}

public struct UpdatePaymentMethodInput: Equatable, Sendable {
    public var name: String?
    public var methodType: PaymentMethodType?
    public var semanticTags: [String]?
}

public struct CreatePaymentTypeInput: Equatable, Sendable {
    public var name: String
    public var element: AccountingElement
    public var semanticTags: [String]
    public var configDescription: String?
}

public struct UpdatePaymentTypeInput: Equatable, Sendable {
    public var name: String?
    public var element: AccountingElement?
    public var semanticTags: [String]?
    public var configDescription: String?
}

public struct CreatePaymentDetailInput: Equatable, Sendable {
    public var name: String
    public var paymentTypeId: UUID
    public var semanticTags: [String]
    public var configDescription: String?
}

public struct UpdatePaymentDetailInput: Equatable, Sendable {
    public var name: String?
    public var paymentTypeId: UUID?
    public var semanticTags: [String]?
    public var configDescription: String?
}

public enum SemanticTagTarget: Equatable, Sendable {
    case paymentMethod(UUID)
    case paymentType(UUID)
    case paymentDetail(UUID)
}
```

### 标签值

第一版标签保存中文稳定值，避免 UI 和文档之间再做一层映射。

```swift
public enum SemanticTagCatalog {
    public static let paymentMethodTags = ["资产型", "负债型", "账务处理型", "待补真实账户"]
    public static let paymentTypeTags = ["资产", "负债", "收入", "支出"]
    public static let paymentDetailTags = ["递延资产", "已实现投资收益", "已实现投资亏损", "金融费用", "账单还款"]
}
```

`待补真实账户` 是导入整理的内部占位配置，不作为用户可新增类型；设置页可以展示，但编辑和停用按钮应禁用。

## 2. 任务清单

### Task 1: Core 迁移、语义元数据与 seed 测试

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Create: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1SettingsFlowTests.swift`

**Step 1: Write the failing test**

新建 `P1SettingsFlowTests.swift`：

```swift
import Foundation
import XCTest
@testable import MingZhangCore

final class P1SettingsFlowTests: XCTestCase {
    func testSeedIncludesSemanticMetadataAndConfigVersion() throws {
        let database = try LedgerDatabase.inMemory()
        let useCases = LedgerUseCases(database: database)

        try useCases.initializeLedgerSeed()

        let methods = try useCases.queryPaymentMethods()
        let types = try useCases.queryPaymentTypes()
        let details = try useCases.queryPaymentDetails()

        XCTAssertEqual(methods.first { $0.name == "电子钱包余额" }?.semanticTags, ["资产型"])
        XCTAssertEqual(methods.first { $0.name == "广发卡" }?.semanticTags, ["负债型"])
        XCTAssertEqual(methods.first { $0.name == "账务处理" }?.semanticTags, ["账务处理型"])
        XCTAssertEqual(methods.first { $0.name == "待补真实账户" }?.semanticTags, ["待补真实账户"])
        XCTAssertTrue(methods.allSatisfy { $0.configVersion == 1 })

        XCTAssertEqual(types.first { $0.name == "生活必要开支" }?.semanticTags, ["支出"])
        XCTAssertEqual(types.first { $0.name == "生活必要开支" }?.configVersion, 1)
        XCTAssertEqual(details.first { $0.name == "伙食费" }?.semanticTags, [])
        XCTAssertEqual(details.first { $0.name == "伙食费" }?.configVersion, 1)
    }
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1SettingsFlowTests/testSeedIncludesSemanticMetadataAndConfigVersion
```

Expected: FAIL，`PaymentMethod` / `PaymentType` / `PaymentDetail` 没有 `semanticTags` 或 `configVersion`。

**Step 3: Add migration and model fields**

在 `LedgerDatabase.migrator` 的 `v2_p1_import` 之后追加：

```swift
migrator.registerMigration("v3_p1_settings_semantics") { db in
    try db.alter(table: "payment_methods") { table in
        table.add(column: "semantic_tags", .text).notNull().defaults(to: "[]")
        table.add(column: "config_version", .integer).notNull().defaults(to: 1)
    }

    try db.alter(table: "payment_types") { table in
        table.add(column: "semantic_tags", .text).notNull().defaults(to: "[]")
        table.add(column: "config_description", .text)
        table.add(column: "config_version", .integer).notNull().defaults(to: 1)
    }

    try db.alter(table: "payment_details") { table in
        table.add(column: "semantic_tags", .text).notNull().defaults(to: "[]")
        table.add(column: "config_description", .text)
        table.add(column: "config_version", .integer).notNull().defaults(to: 1)
    }

    try db.alter(table: "journal_records") { table in
        table.add(column: "payment_method_name_snapshot", .text)
        table.add(column: "payment_type_name_snapshot", .text)
        table.add(column: "payment_detail_name_snapshot", .text)
    }

    try db.execute(sql: """
        UPDATE journal_records
        SET payment_method_name_snapshot = (
                SELECT name FROM payment_methods WHERE payment_methods.id = journal_records.payment_method_id
            ),
            payment_type_name_snapshot = (
                SELECT name FROM payment_types WHERE payment_types.id = journal_records.payment_type_id
            ),
            payment_detail_name_snapshot = (
                SELECT name FROM payment_details WHERE payment_details.id = journal_records.payment_detail_id
            )
        """)
}
```

更新模型、row mapper 和查询字段：

```swift
private let selectJournalRecordSQL = """
    SELECT
        journal_records.id,
        journal_records.account_month,
        journal_records.occurred_at,
        journal_records.payment_method_id,
        COALESCE(journal_records.payment_method_name_snapshot, payment_methods.name) AS payment_method_name,
        journal_records.amount,
        journal_records.payment_type_id,
        COALESCE(journal_records.payment_type_name_snapshot, payment_types.name) AS payment_type_name,
        journal_records.payment_detail_id,
        COALESCE(journal_records.payment_detail_name_snapshot, payment_details.name) AS payment_detail_name,
        ...
    """
```

更新 `insertJournalRecord` / `persistJournalRecordUpdate`，写入三列 snapshot。注意：当用户只编辑备注、金额、账月时，沿用 `record.paymentMethodName` / `record.paymentTypeName` / `record.paymentDetailName`；只有用户明确选择新的配置项时，`updateJournalRecord` 才会把 snapshot 改成新配置名称。

添加 JSON helper：

```swift
private func encodeStringList(_ values: [String]) -> String {
    guard let data = try? JSONEncoder().encode(values),
          let text = String(data: data, encoding: .utf8)
    else { return "[]" }
    return text
}

private func decodeStringList(_ text: String?) -> [String] {
    guard let text, let data = text.data(using: .utf8) else { return [] }
    return (try? JSONDecoder().decode([String].self, from: data)) ?? []
}
```

更新 mapper：

```swift
private func paymentMethod(from row: Row) throws -> PaymentMethod {
    PaymentMethod(
        id: try requireUUID(row["id"]),
        name: row["name"],
        methodType: PaymentMethodType(rawValue: row["method_type"]) ?? .pendingRealAccount,
        isActive: row["is_active"],
        semanticTags: decodeStringList(row["semantic_tags"]),
        configVersion: row["config_version"]
    )
}
```

`paymentType(from:)` 和 `paymentDetail(from:)` 同步读取 `semantic_tags`、`config_description`、`config_version`。

**Step 4: Seed default semantic tags**

把 `insertPaymentMethodIfNeeded`、`insertPaymentTypeIfNeeded`、`insertPaymentDetailIfNeeded` 参数扩展为语义标签和说明。`initializeLedgerSeed()` 中使用：

```swift
try insertPaymentMethodIfNeeded(db, name: "电子钱包余额", methodType: .asset, semanticTags: ["资产型"], now: now)
try insertPaymentMethodIfNeeded(db, name: "广发卡", methodType: .liability, semanticTags: ["负债型"], now: now)
try insertPaymentMethodIfNeeded(db, name: "账务处理", methodType: .accounting, semanticTags: ["账务处理型"], now: now)
try insertPaymentMethodIfNeeded(db, name: "待补真实账户", methodType: .pendingRealAccount, semanticTags: ["待补真实账户"], now: now)

let type = try insertPaymentTypeIfNeeded(db, name: "生活必要开支", element: .expense, semanticTags: ["支出"], configDescription: nil, now: now)
try insertPaymentDetailIfNeeded(db, name: "伙食费", paymentTypeId: type.id, semanticTags: [], configDescription: nil, now: now)
```

**Step 5: Run test to verify it passes**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1SettingsFlowTests/testSeedIncludesSemanticMetadataAndConfigVersion
```

Expected: PASS.

**Step 6: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift \
        ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1SettingsFlowTests.swift
git commit -m "feat: add settings semantic metadata"
```

### Task 2: 收付手段新增、编辑、停用与历史快照保护

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1SettingsFlowTests.swift`

**Step 1: Write the failing test**

追加：

```swift
func testPaymentMethodRenameAndDisableProtectsHistoricalRecordSnapshot() throws {
    let database = try LedgerDatabase.inMemory()
    let useCases = LedgerUseCases(database: database)
    try useCases.initializeLedgerSeed()

    let method = try useCases.createPaymentMethod(
        input: CreatePaymentMethodInput(
            name: "招商卡",
            methodType: .liability,
            semanticTags: ["负债型"]
        )
    )

    let original = try useCases.createManualRecord(
        input: CreateManualRecordInput(
            accountMonth: "2026-04",
            occurredAt: try Date.iso8601("2026-04-15T12:00:00Z"),
            paymentMethodName: "招商卡",
            amount: Decimal(88),
            paymentTypeName: "生活必要开支",
            paymentDetailName: "伙食费",
            note: "午餐"
        )
    )

    let renamed = try useCases.updatePaymentMethod(
        id: method.id,
        input: UpdatePaymentMethodInput(
            name: "招商信用卡",
            methodType: nil,
            semanticTags: nil
        )
    )
    XCTAssertEqual(renamed.name, "招商信用卡")
    XCTAssertEqual(renamed.configVersion, method.configVersion + 1)

    let history = try useCases.queryJournalRecords(
        filter: JournalRecordFilter(accountMonths: ["2026-04"])
    )
    XCTAssertEqual(history.first { $0.id == original.id }?.paymentMethodName, "招商卡")

    _ = try useCases.createManualRecord(
        input: CreateManualRecordInput(
            accountMonth: "2026-04",
            occurredAt: try Date.iso8601("2026-04-16T12:00:00Z"),
            paymentMethodName: "招商信用卡",
            amount: Decimal(66),
            paymentTypeName: "生活必要开支",
            paymentDetailName: "伙食费",
            note: "晚餐"
        )
    )

    try useCases.disablePaymentMethod(id: method.id)

    XCTAssertThrowsError(
        try useCases.createManualRecord(
            input: CreateManualRecordInput(
                accountMonth: "2026-04",
                occurredAt: try Date.iso8601("2026-04-17T12:00:00Z"),
                paymentMethodName: "招商信用卡",
                amount: Decimal(20),
                paymentTypeName: "生活必要开支",
                paymentDetailName: "伙食费",
                note: "停用后不应可用"
            )
        )
    )

    let recordsAfterDisable = try useCases.queryJournalRecords(
        filter: JournalRecordFilter(accountMonths: ["2026-04"])
    )
    XCTAssertEqual(recordsAfterDisable.first { $0.id == original.id }?.paymentMethodName, "招商卡")
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1SettingsFlowTests/testPaymentMethodRenameAndDisableProtectsHistoricalRecordSnapshot
```

Expected: FAIL，缺少 `CreatePaymentMethodInput`、`updatePaymentMethod`、`disablePaymentMethod` 等 API。

**Step 3: Implement validation helpers**

在私有 helper 区添加：

```swift
private func normalizedConfigName(_ name: String) throws -> String {
    let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
        throw MingZhangError.validation("名称不能为空")
    }
    return normalized
}

private func assertUserEditablePaymentMethod(_ method: PaymentMethod) throws {
    guard method.methodType != .pendingRealAccount else {
        throw MingZhangError.validation("待补真实账户是导入整理占位，不能在设置中编辑或停用")
    }
}

private func paymentMethodReferenceCount(_ db: Database, id: UUID) throws -> Int {
    try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM journal_records WHERE payment_method_id = ?",
        arguments: [id.uuidString]
    ) ?? 0
}
```

新增 active require：

```swift
private func requireActivePaymentMethod(_ db: Database, name: String) throws -> PaymentMethod {
    let method = try requirePaymentMethod(db, name: name)
    guard method.isActive else {
        throw MingZhangError.validation("收付手段已停用：\(name)")
    }
    return method
}
```

把 `createManualRecord`、`updateJournalRecord` 中用户选择新收付手段的地方改为 `requireActivePaymentMethod`。`fetchSourceRecordsWithSemantics` 继续用 id 查询，不受停用影响。

**Step 4: Implement payment method Use Cases**

在 `LedgerUseCases` 中添加：

```swift
@discardableResult
public func createPaymentMethod(input: CreatePaymentMethodInput) throws -> PaymentMethod {
    try database.writer.write { db in
        guard input.methodType != .pendingRealAccount else {
            throw MingZhangError.validation("不能新增待补真实账户")
        }
        let name = try normalizedConfigName(input.name)
        let now = Date()
        let method = PaymentMethod(
            id: UUID(),
            name: name,
            methodType: input.methodType,
            isActive: true,
            semanticTags: input.semanticTags,
            configVersion: 1
        )
        try db.execute(sql: """
            INSERT INTO payment_methods (id, name, method_type, is_active, semantic_tags, config_version, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                method.id.uuidString,
                method.name,
                method.methodType.rawValue,
                method.isActive,
                encodeStringList(method.semanticTags),
                method.configVersion,
                encodeDate(now),
                encodeDate(now)
            ])
        return method
    }
}

@discardableResult
public func updatePaymentMethod(id: UUID, input: UpdatePaymentMethodInput) throws -> PaymentMethod {
    try database.writer.write { db in
        var method = try requirePaymentMethod(db, id: id)
        try assertUserEditablePaymentMethod(method)

        if let name = input.name {
            method.name = try normalizedConfigName(name)
        }
        if let methodType = input.methodType, methodType != method.methodType {
            guard try paymentMethodReferenceCount(db, id: id) == 0 else {
                throw MingZhangError.validation("已有流水引用该收付手段，不能修改资产/负债/账务处理属性")
            }
            guard methodType != .pendingRealAccount else {
                throw MingZhangError.validation("不能改为待补真实账户")
            }
            method.methodType = methodType
        }
        if let semanticTags = input.semanticTags {
            method.semanticTags = semanticTags
        }
        method.configVersion += 1

        try db.execute(sql: """
            UPDATE payment_methods
            SET name = ?, method_type = ?, semantic_tags = ?, config_version = ?, updated_at = ?
            WHERE id = ?
            """, arguments: [
                method.name,
                method.methodType.rawValue,
                encodeStringList(method.semanticTags),
                method.configVersion,
                encodeDate(Date()),
                id.uuidString
            ])
        return method
    }
}

public func disablePaymentMethod(id: UUID) throws {
    try database.writer.write { db in
        let method = try requirePaymentMethod(db, id: id)
        try assertUserEditablePaymentMethod(method)
        try db.execute(sql: """
            UPDATE payment_methods
            SET is_active = ?, config_version = config_version + 1, updated_at = ?
            WHERE id = ?
            """, arguments: [false, encodeDate(Date()), id.uuidString])
    }
}
```

**Step 5: Run test to verify it passes**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1SettingsFlowTests/testPaymentMethodRenameAndDisableProtectsHistoricalRecordSnapshot
```

Expected: PASS.

**Step 6: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift \
        ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1SettingsFlowTests.swift
git commit -m "feat: manage payment methods"
```

### Task 3: 收付类型与类型明细维护

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1SettingsFlowTests.swift`

**Step 1: Write the failing test**

追加：

```swift
func testPaymentTypeAndDetailMaintenanceProtectsReferencedStructure() throws {
    let database = try LedgerDatabase.inMemory()
    let useCases = LedgerUseCases(database: database)
    try useCases.initializeLedgerSeed()

    let transportType = try useCases.createPaymentType(
        input: CreatePaymentTypeInput(
            name: "交通通信开支",
            element: .expense,
            semanticTags: ["支出"],
            configDescription: nil
        )
    )
    let detail = try useCases.createPaymentDetail(
        input: CreatePaymentDetailInput(
            name: "公交地铁",
            paymentTypeId: transportType.id,
            semanticTags: [],
            configDescription: nil
        )
    )

    let record = try useCases.createManualRecord(
        input: CreateManualRecordInput(
            accountMonth: "2026-04",
            occurredAt: try Date.iso8601("2026-04-18T08:00:00Z"),
            paymentMethodName: "电子钱包余额",
            amount: Decimal(6),
            paymentTypeName: "交通通信开支",
            paymentDetailName: "公交地铁",
            note: "地铁"
        )
    )

    let renamedDetail = try useCases.updatePaymentDetail(
        id: detail.id,
        input: UpdatePaymentDetailInput(
            name: "公共交通",
            paymentTypeId: nil,
            semanticTags: nil,
            configDescription: nil
        )
    )
    XCTAssertEqual(renamedDetail.name, "公共交通")

    let records = try useCases.queryJournalRecords(
        filter: JournalRecordFilter(accountMonths: ["2026-04"])
    )
    XCTAssertEqual(records.first { $0.id == record.id }?.paymentDetailName, "公交地铁")

    let otherType = try useCases.createPaymentType(
        input: CreatePaymentTypeInput(
            name: "其他交通",
            element: .expense,
            semanticTags: ["支出"],
            configDescription: nil
        )
    )
    XCTAssertThrowsError(
        try useCases.updatePaymentDetail(
            id: detail.id,
            input: UpdatePaymentDetailInput(
                name: nil,
                paymentTypeId: otherType.id,
                semanticTags: nil,
                configDescription: nil
            )
        )
    )

    try useCases.disablePaymentDetail(id: detail.id)

    XCTAssertThrowsError(
        try useCases.createManualRecord(
            input: CreateManualRecordInput(
                accountMonth: "2026-04",
                occurredAt: try Date.iso8601("2026-04-19T08:00:00Z"),
                paymentMethodName: "电子钱包余额",
                amount: Decimal(6),
                paymentTypeName: "交通通信开支",
                paymentDetailName: "公共交通",
                note: "停用后不应可用"
            )
        )
    )
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1SettingsFlowTests/testPaymentTypeAndDetailMaintenanceProtectsReferencedStructure
```

Expected: FAIL，缺少收付类型和类型明细维护 API。

**Step 3: Add require active helpers and reference counters**

```swift
private func requireActivePaymentType(_ db: Database, name: String) throws -> PaymentType {
    let type = try requirePaymentType(db, name: name)
    guard type.isActive else {
        throw MingZhangError.validation("收付类型已停用：\(name)")
    }
    return type
}

private func requireActivePaymentDetail(_ db: Database, name: String, paymentTypeId: UUID) throws -> PaymentDetail {
    let detail = try requirePaymentDetail(db, name: name, paymentTypeId: paymentTypeId)
    guard detail.isActive else {
        throw MingZhangError.validation("类型明细已停用：\(name)")
    }
    return detail
}

private func paymentTypeReferenceCount(_ db: Database, id: UUID) throws -> Int {
    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM journal_records WHERE payment_type_id = ?", arguments: [id.uuidString]) ?? 0
}

private func paymentDetailReferenceCount(_ db: Database, id: UUID) throws -> Int {
    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM journal_records WHERE payment_detail_id = ?", arguments: [id.uuidString]) ?? 0
}
```

把 `createManualRecord`、`updateJournalRecord`、`applyImportCandidateChanges`、`confirmImportCandidates` 中用户新选择的类型和明细改为 active helper。按 id 确认导入时也要检查 `isActive`。

**Step 4: Implement payment type Use Cases**

```swift
@discardableResult
public func createPaymentType(input: CreatePaymentTypeInput) throws -> PaymentType {
    try database.writer.write { db in
        let name = try normalizedConfigName(input.name)
        let now = Date()
        let type = PaymentType(
            id: UUID(),
            name: name,
            element: input.element,
            isActive: true,
            semanticTags: input.semanticTags,
            configDescription: input.configDescription,
            configVersion: 1
        )
        try db.execute(sql: """
            INSERT INTO payment_types (id, name, element, is_active, semantic_tags, config_description, config_version, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                type.id.uuidString,
                type.name,
                type.element.rawValue,
                type.isActive,
                encodeStringList(type.semanticTags),
                type.configDescription,
                type.configVersion,
                encodeDate(now),
                encodeDate(now)
            ])
        return type
    }
}

@discardableResult
public func updatePaymentType(id: UUID, input: UpdatePaymentTypeInput) throws -> PaymentType {
    try database.writer.write { db in
        var type = try requirePaymentType(db, id: id)
        if let name = input.name {
            type.name = try normalizedConfigName(name)
        }
        if let element = input.element, element != type.element {
            guard try paymentTypeReferenceCount(db, id: id) == 0 else {
                throw MingZhangError.validation("已有流水引用该收付类型，不能修改资产/负债/收入/支出语义")
            }
            type.element = element
        }
        if let tags = input.semanticTags {
            type.semanticTags = tags
        }
        if let description = input.configDescription {
            type.configDescription = description
        }
        type.configVersion += 1
        try db.execute(sql: """
            UPDATE payment_types
            SET name = ?, element = ?, semantic_tags = ?, config_description = ?, config_version = ?, updated_at = ?
            WHERE id = ?
            """, arguments: [
                type.name,
                type.element.rawValue,
                encodeStringList(type.semanticTags),
                type.configDescription,
                type.configVersion,
                encodeDate(Date()),
                id.uuidString
            ])
        return type
    }
}

public func disablePaymentType(id: UUID) throws {
    try database.writer.write { db in
        let activeDetailCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM payment_details WHERE payment_type_id = ? AND is_active = ?",
            arguments: [id.uuidString, true]
        ) ?? 0
        guard activeDetailCount == 0 else {
            throw MingZhangError.validation("请先停用该收付类型下的类型明细")
        }
        try db.execute(sql: """
            UPDATE payment_types
            SET is_active = ?, config_version = config_version + 1, updated_at = ?
            WHERE id = ?
            """, arguments: [false, encodeDate(Date()), id.uuidString])
    }
}
```

**Step 5: Implement payment detail Use Cases**

```swift
@discardableResult
public func createPaymentDetail(input: CreatePaymentDetailInput) throws -> PaymentDetail {
    try database.writer.write { db in
        let type = try requirePaymentType(db, id: input.paymentTypeId)
        guard type.isActive else {
            throw MingZhangError.validation("不能在已停用收付类型下新增类型明细")
        }
        let name = try normalizedConfigName(input.name)
        let now = Date()
        let detail = PaymentDetail(
            id: UUID(),
            name: name,
            paymentTypeId: input.paymentTypeId,
            isActive: true,
            semanticTags: input.semanticTags,
            configDescription: input.configDescription,
            configVersion: 1
        )
        try db.execute(sql: """
            INSERT INTO payment_details (id, name, payment_type_id, is_active, semantic_tags, config_description, config_version, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                detail.id.uuidString,
                detail.name,
                detail.paymentTypeId.uuidString,
                detail.isActive,
                encodeStringList(detail.semanticTags),
                detail.configDescription,
                detail.configVersion,
                encodeDate(now),
                encodeDate(now)
            ])
        return detail
    }
}

@discardableResult
public func updatePaymentDetail(id: UUID, input: UpdatePaymentDetailInput) throws -> PaymentDetail {
    try database.writer.write { db in
        var detail = try requirePaymentDetail(db, id: id)
        if let name = input.name {
            detail.name = try normalizedConfigName(name)
        }
        if let paymentTypeId = input.paymentTypeId, paymentTypeId != detail.paymentTypeId {
            guard try paymentDetailReferenceCount(db, id: id) == 0 else {
                throw MingZhangError.validation("已有流水引用该类型明细，不能调整所属收付类型")
            }
            let targetType = try requirePaymentType(db, id: paymentTypeId)
            guard targetType.isActive else {
                throw MingZhangError.validation("不能移动到已停用收付类型")
            }
            detail.paymentTypeId = paymentTypeId
        }
        if let tags = input.semanticTags {
            detail.semanticTags = tags
        }
        if let description = input.configDescription {
            detail.configDescription = description
        }
        detail.configVersion += 1
        try db.execute(sql: """
            UPDATE payment_details
            SET name = ?, payment_type_id = ?, semantic_tags = ?, config_description = ?, config_version = ?, updated_at = ?
            WHERE id = ?
            """, arguments: [
                detail.name,
                detail.paymentTypeId.uuidString,
                encodeStringList(detail.semanticTags),
                detail.configDescription,
                detail.configVersion,
                encodeDate(Date()),
                id.uuidString
            ])
        return detail
    }
}

public func disablePaymentDetail(id: UUID) throws {
    try database.writer.write { db in
        try db.execute(sql: """
            UPDATE payment_details
            SET is_active = ?, config_version = config_version + 1, updated_at = ?
            WHERE id = ?
            """, arguments: [false, encodeDate(Date()), id.uuidString])
    }
}
```

**Step 6: Run test to verify it passes**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1SettingsFlowTests/testPaymentTypeAndDetailMaintenanceProtectsReferencedStructure
```

Expected: PASS.

**Step 7: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift \
        ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1SettingsFlowTests.swift
git commit -m "feat: manage payment types and details"
```

### Task 4: 语义标签更新与配置版本

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1SettingsFlowTests.swift`

**Step 1: Write the failing test**

追加：

```swift
func testUpdateSemanticTagsIncrementsConfigVersion() throws {
    let database = try LedgerDatabase.inMemory()
    let useCases = LedgerUseCases(database: database)
    try useCases.initializeLedgerSeed()

    let method = try XCTUnwrap(try useCases.queryPaymentMethods().first { $0.name == "广发卡" })

    let updated = try useCases.updateSemanticTags(
        target: .paymentMethod(method.id),
        tags: ["负债型", "信用支付"]
    )

    XCTAssertEqual(updated.semanticTags, ["负债型", "信用支付"])
    XCTAssertEqual(updated.configVersion, method.configVersion + 1)
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1SettingsFlowTests/testUpdateSemanticTagsIncrementsConfigVersion
```

Expected: FAIL，缺少 `updateSemanticTags`。

**Step 3: Implement UpdateSemanticTag**

返回一个轻量结果，避免 generic 复杂度：

```swift
public struct SemanticTagUpdateResult: Equatable, Sendable {
    public var target: SemanticTagTarget
    public var semanticTags: [String]
    public var configVersion: Int
}
```

实现：

```swift
@discardableResult
public func updateSemanticTags(target: SemanticTagTarget, tags: [String]) throws -> SemanticTagUpdateResult {
    let normalizedTags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    return try database.writer.write { db in
        switch target {
        case .paymentMethod(let id):
            let method = try requirePaymentMethod(db, id: id)
            try assertUserEditablePaymentMethod(method)
            let version = method.configVersion + 1
            try db.execute(sql: """
                UPDATE payment_methods
                SET semantic_tags = ?, config_version = ?, updated_at = ?
                WHERE id = ?
                """, arguments: [encodeStringList(normalizedTags), version, encodeDate(Date()), id.uuidString])
            return SemanticTagUpdateResult(target: target, semanticTags: normalizedTags, configVersion: version)

        case .paymentType(let id):
            let type = try requirePaymentType(db, id: id)
            let version = type.configVersion + 1
            try db.execute(sql: """
                UPDATE payment_types
                SET semantic_tags = ?, config_version = ?, updated_at = ?
                WHERE id = ?
                """, arguments: [encodeStringList(normalizedTags), version, encodeDate(Date()), id.uuidString])
            return SemanticTagUpdateResult(target: target, semanticTags: normalizedTags, configVersion: version)

        case .paymentDetail(let id):
            let detail = try requirePaymentDetail(db, id: id)
            let version = detail.configVersion + 1
            try db.execute(sql: """
                UPDATE payment_details
                SET semantic_tags = ?, config_version = ?, updated_at = ?
                WHERE id = ?
                """, arguments: [encodeStringList(normalizedTags), version, encodeDate(Date()), id.uuidString])
            return SemanticTagUpdateResult(target: target, semanticTags: normalizedTags, configVersion: version)
        }
    }
}
```

如果测试代码需要 `updated.semanticTags`，保持 `SemanticTagUpdateResult` 字段名一致；若返回具体模型，则同步改测试。

**Step 4: Run test to verify it passes**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1SettingsFlowTests/testUpdateSemanticTagsIncrementsConfigVersion
```

Expected: PASS.

**Step 5: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift \
        ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1SettingsFlowTests.swift
git commit -m "feat: update semantic tags"
```

### Task 5: 后续记账只使用启用配置，筛选保留历史配置

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1SettingsFlowTests.swift`

**Step 1: Write the failing test**

追加：

```swift
func testActiveQueriesExcludeDisabledConfigsButAllQueriesKeepHistoryFilters() throws {
    let database = try LedgerDatabase.inMemory()
    let useCases = LedgerUseCases(database: database)
    try useCases.initializeLedgerSeed()

    let method = try useCases.createPaymentMethod(
        input: CreatePaymentMethodInput(name: "北京卡", methodType: .liability, semanticTags: ["负债型"])
    )
    XCTAssertTrue(try useCases.queryActivePaymentMethods().contains { $0.id == method.id })

    try useCases.disablePaymentMethod(id: method.id)

    XCTAssertTrue(try useCases.queryPaymentMethods().contains { $0.id == method.id })
    XCTAssertFalse(try useCases.queryActivePaymentMethods().contains { $0.id == method.id })
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1SettingsFlowTests/testActiveQueriesExcludeDisabledConfigsButAllQueriesKeepHistoryFilters
```

Expected: FAIL，缺少 active query API。

**Step 3: Implement active queries**

```swift
public func queryActivePaymentMethods() throws -> [PaymentMethod] {
    try database.writer.read { db in
        try Row.fetchAll(db, sql: """
            SELECT id, name, method_type, is_active, semantic_tags, config_version
            FROM payment_methods
            WHERE is_active = ?
            ORDER BY name
            """, arguments: [true]).map(paymentMethod(from:))
    }
}

public func queryActivePaymentTypes() throws -> [PaymentType] {
    try database.writer.read { db in
        try Row.fetchAll(db, sql: """
            SELECT id, name, element, is_active, semantic_tags, config_description, config_version
            FROM payment_types
            WHERE is_active = ?
            ORDER BY name
            """, arguments: [true]).map(paymentType(from:))
    }
}

public func queryActivePaymentDetails(paymentTypeId: UUID? = nil) throws -> [PaymentDetail] {
    try database.writer.read { db in
        if let paymentTypeId {
            return try Row.fetchAll(db, sql: """
                SELECT id, name, payment_type_id, is_active, semantic_tags, config_description, config_version
                FROM payment_details
                WHERE is_active = ? AND payment_type_id = ?
                ORDER BY name
                """, arguments: [true, paymentTypeId.uuidString]).map(paymentDetail(from:))
        }
        return try Row.fetchAll(db, sql: """
            SELECT id, name, payment_type_id, is_active, semantic_tags, config_description, config_version
            FROM payment_details
            WHERE is_active = ?
            ORDER BY name
            """, arguments: [true]).map(paymentDetail(from:))
    }
}
```

同步更新原有 `queryPaymentMethods`、`queryPaymentTypes`、`queryPaymentDetails` 的 SELECT 字段，包含新增列但不加 `is_active` 过滤。

**Step 4: Run test to verify it passes**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1SettingsFlowTests/testActiveQueriesExcludeDisabledConfigsButAllQueriesKeepHistoryFilters
```

Expected: PASS.

**Step 5: Run existing P0/P1 core tests**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: PASS. 如果导入确认测试因停用校验失败，修正测试数据，不要放宽 active 校验。

**Step 6: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift \
        ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1SettingsFlowTests.swift
git commit -m "feat: separate active and historical config queries"
```

### Task 6: LedgerStore 设置操作封装

**Files:**
- Modify: `ios/MingZhang/MingZhang/LedgerStore.swift`

**Step 1: Add active published state**

在 `LedgerStore` 中新增：

```swift
@Published private(set) var activeMethods: [PaymentMethod] = []
@Published private(set) var activeTypes: [PaymentType] = []
@Published private(set) var activeDetails: [PaymentDetail] = []
```

`refresh()` 中同时查询：

```swift
methods = try useCases.queryPaymentMethods()
types = try useCases.queryPaymentTypes()
details = try useCases.queryPaymentDetails()
activeMethods = try useCases.queryActivePaymentMethods()
activeTypes = try useCases.queryActivePaymentTypes()
activeDetails = try useCases.queryActivePaymentDetails()
```

**Step 2: Add settings mutation wrappers**

```swift
func createPaymentMethod(input: CreatePaymentMethodInput) -> Bool {
    do {
        guard let useCases else { return false }
        _ = try useCases.createPaymentMethod(input: input)
        try refresh()
        return true
    } catch {
        lastError = error.localizedDescription
        return false
    }
}

func updatePaymentMethod(id: UUID, input: UpdatePaymentMethodInput) -> Bool {
    do {
        guard let useCases else { return false }
        _ = try useCases.updatePaymentMethod(id: id, input: input)
        try refresh()
        return true
    } catch {
        lastError = error.localizedDescription
        return false
    }
}

func disablePaymentMethod(id: UUID) -> Bool {
    do {
        guard let useCases else { return false }
        try useCases.disablePaymentMethod(id: id)
        try refresh()
        return true
    } catch {
        lastError = error.localizedDescription
        return false
    }
}
```

按同一模式添加：

- `createPaymentType(input:)`
- `updatePaymentType(id:input:)`
- `disablePaymentType(id:)`
- `createPaymentDetail(input:)`
- `updatePaymentDetail(id:input:)`
- `disablePaymentDetail(id:)`
- `updateSemanticTags(target:tags:)`

**Step 3: Update record/import pickers to use active arrays**

在 `RootView.swift` 后续任务中修改，但本任务先保证 store 暴露状态。约定：

- 新增/编辑流水表单、导入整理表单使用 `activeMethods`、`activeTypes`、`activeDetails`。
- 流水筛选可继续使用 `methods`、`types`、`details`，以便筛到历史停用配置。

**Step 4: Build app**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project ios/MingZhang/MingZhang.xcodeproj \
  -scheme MingZhang \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath ios/MingZhang/SourcePackages \
  build
```

Expected: BUILD SUCCEEDED.

**Step 5: Commit**

```bash
git add ios/MingZhang/MingZhang/LedgerStore.swift
git commit -m "feat: expose settings mutations to app store"
```

### Task 7: SwiftUI 设置页交互

**Files:**
- Modify: `ios/MingZhang/MingZhang/RootView.swift`

**Step 1: Replace read-only SettingsView with settings navigation**

将现有 `SettingsView` 替换为：

```swift
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("记账配置") {
                    NavigationLink {
                        PaymentMethodSettingsView()
                    } label: {
                        Label("收付手段", systemImage: "creditcard")
                    }

                    NavigationLink {
                        PaymentCategorySettingsView()
                    } label: {
                        Label("收付类型与明细", systemImage: "list.bullet.indent")
                    }

                    NavigationLink {
                        SemanticTagSettingsView()
                    } label: {
                        Label("语义标签", systemImage: "tag")
                    }
                }

                Section("边界") {
                    Text("设置只维护长期记账语义，不承接日常记账、导入字段映射或自动分类规则。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
        }
    }
}
```

**Step 2: Add payment method settings view**

```swift
struct PaymentMethodSettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var editingMethod: PaymentMethod?
    @State private var isCreating = false

    var body: some View {
        List {
            Section("收付手段") {
                ForEach(store.methods) { method in
                    Button {
                        editingMethod = method
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(method.name)
                                Text(method.methodType.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !method.isActive {
                                Text("已停用")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(method.methodType == .pendingRealAccount)
                }
            }
        }
        .navigationTitle("收付手段")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新增收付手段")
            }
        }
        .sheet(isPresented: $isCreating) {
            PaymentMethodFormView(mode: .create)
                .environmentObject(store)
        }
        .sheet(item: $editingMethod) { method in
            PaymentMethodFormView(mode: .edit(method))
                .environmentObject(store)
        }
    }
}
```

添加 display helper：

```swift
private extension PaymentMethodType {
    var displayName: String {
        switch self {
        case .asset: return "资产型"
        case .liability: return "负债型"
        case .accounting: return "账务处理型"
        case .pendingRealAccount: return "待补真实账户"
        }
    }

    static var editableCases: [PaymentMethodType] {
        [.asset, .liability, .accounting]
    }
}
```

**Step 3: Add payment method form**

```swift
enum PaymentMethodFormMode: Identifiable {
    case create
    case edit(PaymentMethod)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let method): return method.id.uuidString
        }
    }
}

struct PaymentMethodFormView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let mode: PaymentMethodFormMode
    @State private var name = ""
    @State private var methodType: PaymentMethodType = .asset
    @State private var semanticTags: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称", text: $name)
                    Picker("属性", selection: $methodType) {
                        ForEach(PaymentMethodType.editableCases, id: \.self) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                }

                Section("语义标签") {
                    SemanticTagChecklist(tags: SemanticTagCatalog.paymentMethodTags, selection: $semanticTags)
                }

                if case .edit(let method) = mode, method.isActive {
                    Section {
                        Button("停用", role: .destructive) {
                            if store.disablePaymentMethod(id: method.id) {
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: loadInitialValues)
        }
    }

    private var navigationTitle: String {
        if case .create = mode { return "新增收付手段" }
        return "编辑收付手段"
    }

    private func loadInitialValues() {
        guard case .edit(let method) = mode else { return }
        name = method.name
        methodType = method.methodType == .pendingRealAccount ? .asset : method.methodType
        semanticTags = Set(method.semanticTags)
    }

    private func save() {
        let tags = Array(semanticTags).sorted()
        switch mode {
        case .create:
            if store.createPaymentMethod(input: CreatePaymentMethodInput(name: name, methodType: methodType, semanticTags: tags)) {
                dismiss()
            }
        case .edit(let method):
            if store.updatePaymentMethod(id: method.id, input: UpdatePaymentMethodInput(name: name, methodType: methodType, semanticTags: tags)) {
                dismiss()
            }
        }
    }
}
```

**Step 4: Add payment type/detail settings views**

实现 `PaymentCategorySettingsView`，一个列表展示所有收付类型，每个类型下展示类型明细。最小实现不做拖拽排序。

```swift
struct PaymentCategorySettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var editingType: PaymentType?
    @State private var editingDetail: PaymentDetail?
    @State private var isCreatingType = false

    var body: some View {
        List {
            ForEach(store.types) { type in
                Section {
                    Button {
                        editingType = type
                    } label: {
                        HStack {
                            Text(type.name)
                            Spacer()
                            Text(type.element.displayName)
                                .foregroundStyle(.secondary)
                            if !type.isActive {
                                Text("已停用")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    ForEach(store.details.filter { $0.paymentTypeId == type.id }) { detail in
                        Button {
                            editingDetail = detail
                        } label: {
                            HStack {
                                Text(detail.name)
                                Spacer()
                                if !detail.isActive {
                                    Text("已停用")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Button {
                        editingDetail = PaymentDetail(
                            id: UUID(),
                            name: "",
                            paymentTypeId: type.id,
                            isActive: true,
                            semanticTags: [],
                            configDescription: nil,
                            configVersion: 1
                        )
                    } label: {
                        Label("新增类型明细", systemImage: "plus")
                    }
                    .disabled(!type.isActive)
                } header: {
                    Text(type.name)
                }
            }
        }
        .navigationTitle("收付类型与明细")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreatingType = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新增收付类型")
            }
        }
        .sheet(isPresented: $isCreatingType) {
            PaymentTypeFormView(mode: .create)
                .environmentObject(store)
        }
        .sheet(item: $editingType) { type in
            PaymentTypeFormView(mode: .edit(type))
                .environmentObject(store)
        }
        .sheet(item: $editingDetail) { detail in
            PaymentDetailFormView(detail: detail, isCreate: detail.name.isEmpty)
                .environmentObject(store)
        }
    }
}
```

为 `AccountingElement` 添加 display helper：

```swift
private extension AccountingElement {
    var displayName: String {
        switch self {
        case .asset: return "资产"
        case .liability: return "负债"
        case .income: return "收入"
        case .expense: return "支出"
        }
    }
}
```

`PaymentTypeFormView` 与 `PaymentDetailFormView` 采用与 `PaymentMethodFormView` 相同结构：名称、会计要素/所属类型、语义标签、说明、保存、停用。

**Step 5: Add semantic tag checklist and semantic tag overview**

```swift
struct SemanticTagChecklist: View {
    let tags: [String]
    @Binding var selection: Set<String>

    var body: some View {
        ForEach(tags, id: \.self) { tag in
            Toggle(tag, isOn: Binding(
                get: { selection.contains(tag) },
                set: { isOn in
                    if isOn {
                        selection.insert(tag)
                    } else {
                        selection.remove(tag)
                    }
                }
            ))
        }
    }
}

struct SemanticTagSettingsView: View {
    @EnvironmentObject private var store: LedgerStore

    var body: some View {
        List {
            Section("收付手段") {
                ForEach(store.methods) { method in
                    LabeledContent(method.name, value: method.semanticTags.joined(separator: " / "))
                }
            }
            Section("收付类型") {
                ForEach(store.types) { type in
                    LabeledContent(type.name, value: type.semanticTags.joined(separator: " / "))
                }
            }
            Section("类型明细") {
                ForEach(store.details) { detail in
                    LabeledContent(detail.name, value: detail.semanticTags.joined(separator: " / "))
                }
            }
        }
        .navigationTitle("语义标签")
    }
}
```

**Step 6: Update existing pickers**

在新增/编辑流水表单、导入候选编辑和批量编辑表单中：

- `ForEach(store.methods)` 改为 `ForEach(store.activeMethods)`。
- `ForEach(store.types)` 改为 `ForEach(store.activeTypes)`。
- 可选类型明细改为从 `store.activeDetails` 中筛选。

在流水筛选视图中保留 `store.methods` / `store.types` / `store.details`，因为历史停用项仍可能用于筛选旧流水。

**Step 7: Build app**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project ios/MingZhang/MingZhang.xcodeproj \
  -scheme MingZhang \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath ios/MingZhang/SourcePackages \
  build
```

Expected: BUILD SUCCEEDED.

**Step 8: Commit**

```bash
git add ios/MingZhang/MingZhang/RootView.swift
git commit -m "feat: add settings configuration UI"
```

### Task 8: 端到端验收与路线图状态更新

**Files:**
- Modify: `docs/work-plans/2026-05-08-ios-product-to-development-roadmap.md`

**Step 1: Run all Core tests**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: PASS.

**Step 2: Build iOS app**

Run from repo root:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project ios/MingZhang/MingZhang.xcodeproj \
  -scheme MingZhang \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath ios/MingZhang/SourcePackages \
  build
```

Expected: BUILD SUCCEEDED.

**Step 3: Manual acceptance checklist**

在模拟器中手动确认：

- 设置页进入 `收付手段`，可以新增资产型、负债型、账务处理型收付手段。
- 可以编辑收付手段名称和语义标签。
- 停用收付手段后，新增流水和导入整理选择器不再出现该项。
- 停用收付手段后，历史流水仍显示入账时名称。
- `待补真实账户` 可见但不能编辑或停用。
- 设置页进入 `收付类型与明细`，可以新增/编辑收付类型。
- 可以在启用收付类型下新增/编辑/停用类型明细。
- 类型明细只归属于一个收付类型；已被流水引用的类型明细不能移动归属。
- 流水筛选仍能看到停用配置，用于查历史记录。
- 设置页没有导入字段映射、账月规则、继承偏好、自动规则中心入口。

**Step 4: Update roadmap status**

在 `docs/work-plans/2026-05-08-ios-product-to-development-roadmap.md` 的阶段 F 下追加执行状态：

```markdown
执行状态（2026-05-14）：

- 已实现收付手段新增、编辑、停用。
- 已实现收付类型和类型明细维护。
- 已实现语义标签配置。
- 已实现历史流水配置名称快照，配置改名或停用不改写历史展示。
- 保持设置边界：不提供导入字段映射、账月规则和自动分类规则中心。
```

**Step 5: Commit**

```bash
git add docs/work-plans/2026-05-08-ios-product-to-development-roadmap.md
git commit -m "docs: mark p1 settings phase complete"
```

## 3. 最终验证

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: PASS.

Run from repo root:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project ios/MingZhang/MingZhang.xcodeproj \
  -scheme MingZhang \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath ios/MingZhang/SourcePackages \
  build
```

Expected: BUILD SUCCEEDED.

## 4. 风险点

- `journal_records` 当前通过 join 展示配置名，本计划新增 snapshot 后必须保证所有 insert/update 都写 snapshot。
- 配置改名后，历史展示用 snapshot；引擎计算仍按配置 id 读取当前 `methodType` 和 `element`。因此结构性语义一旦被历史流水引用就不允许修改。
- `pending_real_account` 是导入整理占位，不进入用户可维护的收付手段属性集合。
- SQLite 唯一约束仍不允许停用后创建同名新配置；这是有意限制，避免同名不同语义破坏历史查询。
- App 没有 UI test target，本阶段 UI 以 `xcodebuild` 和手动验收覆盖。

## 5. 完成标准

- `P1SettingsFlowTests` 覆盖 seed 元数据、收付手段维护、收付类型/明细维护、语义标签更新、active query。
- `swift test` 全量通过。
- iOS app build 通过。
- 设置页能完成 A-11 验收路径。
- 停用或改名配置不会导致历史流水丢失入账时可见名称。
