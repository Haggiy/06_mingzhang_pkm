# P1 基金投资明细账 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 复刻 Excel 中的基金投资明细账，按平均成本法计算基金持仓和已实现结果，并把买入、卖出、收益、亏损回填成可追溯的流水记录。

**Architecture:** `MingZhangCore` 继续作为领域真源，新增投资交易、持仓、月度汇总和投资回填流水 Use Case；`LedgerStore.swift` 只包装投资 Use Case 与页面状态；`RootView.swift` 承接 v1.0 最小 SwiftUI 页面，包含资产负债入口、标的详情、交易新增/编辑/删除、统计跳转和只读回填展示。投资回填记录仍进入 `journal_records`，但直接编辑边界保持在投资明细账。

**Tech Stack:** Swift 6、SwiftUI、GRDB、SQLite、XCTest、XCUITest、Xcode iOS Simulator。

---

## Context

`事实`

- `docs/specs/investment-ledger-spec.md` 是基金投资明细账权威 Spec：第一版只做基金；买入入账金额等于交易金额；卖出入账金额等于交易份额乘历史平均持有成本；收益/亏损单独计算；回填记录使用 `record_source = investment_feed`。
- `docs/prd/mvp-prd.md` 和 `docs/prd/2026-05-09-v1-feature-acceptance-matrix.md` 中 `F-P1-07`、`F-P1-08`、`A-08` 要求：基金卖出按平均成本法生成入账金额，并回填流水日记账，结果可追溯到投资明细。
- `docs/specs/2026-05-09-ios-page-field-state-spec.md` 中 `B-05`、`B-06`、`S-04`、`S-05` 要求：资产负债承接基金投资明细账入口；交易编辑页负责新增/编辑/删除；统计页只能展示投资结果并跳转到投资明细，不直接编辑交易。
- 当前正式工程入口是 `ios/MingZhang`，Core 包入口是 `ios/MingZhang/Packages/MingZhangCore`。
- 当前 Core 已有 `RecordSource.investmentFeed`、`EngineFamily.investment`、`MutationType.investmentReflow`，但还没有投资交易表、平均成本法、投资回填 Use Case 或投资 UI。
- 当前 `journal_records` 已有导入回溯字段；投资回填需要新增投资交易来源关联字段。

`推断`

- 实现名采用用户指定的 `InvestmentTransaction`、`InvestmentHolding`、`InvestmentMonthlySummary`。它们承接 Spec 中的 `InvestmentEntry` 概念，但命名更贴近本阶段开发输入。
- 回填流水采用按 `账月 + 基金标的 + 回填类型` 删除旧行后重建的方式，保证修改投资交易后不会重复追加。
- `investment_feed` 行作为真源参与引擎；`engine` 行仍只读。现金引擎需要把 `资产类支出 / 金融资产投资` 纳入现金影响：买入正数减少现金，卖出负数增加现金。
- v1.0 投资资产仍按 `总投资资产` 展示，同时保留按基金标的下钻。

`待确认`

- 基金收益明细名称暂定为 `投资收益`。如果后续 Excel 样例出现更稳定名称，修改默认 seed 和测试 fixture。
- 本计划只做手工维护基金交易与手工净值记录，不做实时行情、非基金品类、复杂组合分析。

## Non-Goals

- 不做股票、债券、加密资产或其他非基金投资品类。
- 不做实时行情或自动净值同步。
- 不做复杂组合归因、收益率归因、高级图表。
- 不允许用户在流水详情中直接编辑或删除 `investment_feed` 回填金额。
- 不引入云同步、账号、多端冲突或 App Store 发布流程。
- 不重构当前 App 文件结构；SwiftUI 仍先放在 `RootView.swift`，避免同时修改 Xcode project 文件。

## Task 1: Core 投资模型、Schema 与默认科目

**Files:**
- Create: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/InvestmentModels.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P0LedgerFlowTests.swift`
- Create: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1InvestmentLedgerTests.swift`

**Step 1: Write the failing test**

Create `P1InvestmentLedgerTests.swift`:

```swift
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
```

Update `P0LedgerFlowTests.testInitializeSeedIsIdempotent` so it no longer asserts an exact full list of payment types/details, or include the new investment seed names in the expected arrays.

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1InvestmentLedgerTests/testInvestmentSchemaStartsEmptyAndSeedsInvestmentCategories
```

Expected: FAIL because `InvestmentTransaction` models, investment query Use Cases and schema do not exist.

**Step 3: Add public investment models**

Create `InvestmentModels.swift`:

```swift
import Foundation

public enum InvestmentTransactionType: String, Codable, Equatable, Sendable, CaseIterable {
    case buy
    case sell
    case nav
}

public struct InvestmentTransaction: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var accountMonth: String
    public var occurredAt: Date
    public var fundName: String
    public var transactionType: InvestmentTransactionType
    public var tradeAmount: Decimal?
    public var tradeShare: Decimal?
    public var nav: Decimal?
    public var note: String?
    public var bookAmount: Decimal?
    public var realizedGain: Decimal
    public var realizedLoss: Decimal
    public var holdingShare: Decimal
    public var averageCost: Decimal?
    public var bookValue: Decimal
    public var presentValue: Decimal?
    public var createdAt: Date
    public var updatedAt: Date
}

public struct CreateInvestmentTransactionInput: Equatable, Sendable {
    public var accountMonth: String
    public var occurredAt: Date
    public var fundName: String
    public var transactionType: InvestmentTransactionType
    public var tradeAmount: Decimal?
    public var tradeShare: Decimal?
    public var nav: Decimal?
    public var note: String?

    public init(
        accountMonth: String,
        occurredAt: Date,
        fundName: String,
        transactionType: InvestmentTransactionType,
        tradeAmount: Decimal? = nil,
        tradeShare: Decimal? = nil,
        nav: Decimal? = nil,
        note: String? = nil
    ) {
        self.accountMonth = accountMonth
        self.occurredAt = occurredAt
        self.fundName = fundName
        self.transactionType = transactionType
        self.tradeAmount = tradeAmount
        self.tradeShare = tradeShare
        self.nav = nav
        self.note = note
    }
}

public struct InvestmentTransactionChanges: Equatable, Sendable {
    public var accountMonth: String?
    public var occurredAt: Date?
    public var fundName: String?
    public var transactionType: InvestmentTransactionType?
    public var tradeAmount: Decimal?
    public var tradeShare: Decimal?
    public var nav: Decimal?
    public var note: String?

    public init(
        accountMonth: String? = nil,
        occurredAt: Date? = nil,
        fundName: String? = nil,
        transactionType: InvestmentTransactionType? = nil,
        tradeAmount: Decimal? = nil,
        tradeShare: Decimal? = nil,
        nav: Decimal? = nil,
        note: String? = nil
    ) {
        self.accountMonth = accountMonth
        self.occurredAt = occurredAt
        self.fundName = fundName
        self.transactionType = transactionType
        self.tradeAmount = tradeAmount
        self.tradeShare = tradeShare
        self.nav = nav
        self.note = note
    }
}

public struct InvestmentHolding: Equatable, Identifiable, Sendable {
    public var id: String { fundName }
    public var fundName: String
    public var accountMonth: String
    public var holdingShare: Decimal
    public var averageCost: Decimal?
    public var bookValue: Decimal
    public var latestNav: Decimal?
    public var presentValue: Decimal?
    public var unrealizedGain: Decimal?
    public var sourceTransactionIds: [UUID]
}

public struct InvestmentMonthlySummary: Equatable, Sendable {
    public var accountMonth: String
    public var fundName: String?
    public var buyBookAmount: Decimal
    public var sellBookAmount: Decimal
    public var realizedGain: Decimal
    public var realizedLoss: Decimal
    public var endingBookValue: Decimal
    public var endingShare: Decimal
    public var feedJournalRecordIds: [UUID]
    public var sourceTransactionIds: [UUID]
}

public struct InvestmentFeedTrace: Equatable, Sendable {
    public var journalRecord: JournalRecord
    public var transactions: [InvestmentTransaction]
}
```

**Step 4: Add migration and query stubs**

In `MingZhangCore.swift`:

- Add `case investmentTransactionNotFound(UUID)` to `MingZhangError`.
- Add `sourceInvestmentTransactionIds: [UUID]` to `JournalRecord`.
- Migration `v3_p1_investment`:

```swift
migrator.registerMigration("v3_p1_investment") { db in
    try db.alter(table: "journal_records") { table in
        table.add(column: "source_investment_transaction_ids", .text)
            .notNull()
            .defaults(to: "")
    }

    try db.create(table: "investment_transactions", ifNotExists: true) { table in
        table.column("id", .text).primaryKey()
        table.column("account_month", .text).notNull().indexed()
        table.column("occurred_at", .text).notNull().indexed()
        table.column("fund_name", .text).notNull().indexed()
        table.column("transaction_type", .text).notNull()
        table.column("trade_amount", .text)
        table.column("trade_share", .text)
        table.column("nav", .text)
        table.column("note", .text)
        table.column("book_amount", .text)
        table.column("realized_gain", .text).notNull()
        table.column("realized_loss", .text).notNull()
        table.column("holding_share", .text).notNull()
        table.column("average_cost", .text)
        table.column("book_value", .text).notNull()
        table.column("present_value", .text)
        table.column("created_at", .text).notNull()
        table.column("updated_at", .text).notNull()
    }
}
```

Seed defaults in `initializeLedgerSeed()`:

```swift
let assetInvestmentType = try insertPaymentTypeIfNeeded(db, name: "资产类支出", element: .asset, now: now)
try insertPaymentDetailIfNeeded(db, name: "金融资产投资", paymentTypeId: assetInvestmentType.id, now: now)

let investmentIncomeType = try insertPaymentTypeIfNeeded(db, name: "理财收入", element: .income, now: now)
try insertPaymentDetailIfNeeded(db, name: "投资收益", paymentTypeId: investmentIncomeType.id, now: now)

let financeExpenseType = try insertPaymentTypeIfNeeded(db, name: "财务费用开支", element: .expense, now: now)
try insertPaymentDetailIfNeeded(db, name: "投资亏损", paymentTypeId: financeExpenseType.id, now: now)
```

Add compile-only query stubs returning empty arrays:

```swift
public func queryInvestmentTransactions(fundName: String? = nil) throws -> [InvestmentTransaction] { [] }

public func queryInvestmentHoldings(accountMonth: String) throws -> [InvestmentHolding] { [] }
```

Update `selectJournalRecordSQL`, `insertJournalRecord`, `persistJournalRecordUpdate`, `journalRecordArguments(_:)`, `journalRecord(from:)`, and all `JournalRecord(...)` initializers to include `sourceInvestmentTransactionIds`.

**Step 5: Run test to verify it passes**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1InvestmentLedgerTests/testInvestmentSchemaStartsEmptyAndSeedsInvestmentCategories
```

Expected: PASS.

**Step 6: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests
git commit -m "feat: add investment ledger schema"
```

## Task 2: 平均成本法计算

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1InvestmentLedgerTests.swift`

**Step 1: Write the failing test**

Append:

```swift
func testAverageCostCalculatesSellBookAmountAndLoss() throws {
    let database = try LedgerDatabase.inMemory()
    let useCases = LedgerUseCases(database: database)
    try useCases.initializeLedgerSeed()

    _ = try useCases.createInvestmentTransaction(input: investmentInput(
        accountMonth: "2026-03",
        occurredAt: "2026-03-10T00:00:00Z",
        type: .buy,
        amount: Decimal(300),
        share: Decimal(200),
        nav: Decimal(string: "1.50")!,
        note: "起始买入"
    ))
    let sell = try useCases.createInvestmentTransaction(input: investmentInput(
        accountMonth: "2026-04",
        occurredAt: "2026-04-10T00:00:00Z",
        type: .sell,
        amount: Decimal(-120),
        share: Decimal(-100),
        note: "赎回"
    ))

    let transactions = try useCases.queryInvestmentTransactions(fundName: "沪深300指数A")
    let calculatedSell = try XCTUnwrap(transactions.first { $0.id == sell.id })
    XCTAssertEqual(calculatedSell.bookAmount, Decimal(-150))
    XCTAssertEqual(calculatedSell.realizedGain, Decimal(0))
    XCTAssertEqual(calculatedSell.realizedLoss, Decimal(30))
    XCTAssertEqual(calculatedSell.holdingShare, Decimal(100))
    XCTAssertEqual(calculatedSell.averageCost, Decimal(string: "1.50")!)
    XCTAssertEqual(calculatedSell.bookValue, Decimal(150))
}
```

Add helpers at the bottom of the test file:

```swift
private func investmentInput(
    accountMonth: String = "2026-04",
    occurredAt: String = "2026-04-15T00:00:00Z",
    fundName: String = "沪深300指数A",
    type: InvestmentTransactionType,
    amount: Decimal? = nil,
    share: Decimal? = nil,
    nav: Decimal? = nil,
    note: String? = nil
) throws -> CreateInvestmentTransactionInput {
    CreateInvestmentTransactionInput(
        accountMonth: accountMonth,
        occurredAt: try Date.iso8601(occurredAt),
        fundName: fundName,
        transactionType: type,
        tradeAmount: amount,
        tradeShare: share,
        nav: nav,
        note: note
    )
}

private extension Date {
    static func iso8601(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw MingZhangError.invalidDate(value)
        }
        return date
    }
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1InvestmentLedgerTests/testAverageCostCalculatesSellBookAmountAndLoss
```

Expected: FAIL because `createInvestmentTransaction` does not exist or does not calculate fields.

**Step 3: Implement investment creation and recalculation**

Add public Use Cases:

```swift
@discardableResult
public func createInvestmentTransaction(input: CreateInvestmentTransactionInput) throws -> InvestmentTransaction {
    let transaction = try database.writer.write { db in
        try validateInvestmentInput(input)
        let now = Date()
        let transaction = InvestmentTransaction(
            id: UUID(),
            accountMonth: input.accountMonth,
            occurredAt: input.occurredAt,
            fundName: input.fundName.trimmingCharacters(in: .whitespacesAndNewlines),
            transactionType: input.transactionType,
            tradeAmount: input.tradeAmount,
            tradeShare: input.tradeShare,
            nav: input.nav,
            note: input.note,
            bookAmount: nil,
            realizedGain: 0,
            realizedLoss: 0,
            holdingShare: 0,
            averageCost: nil,
            bookValue: 0,
            presentValue: nil,
            createdAt: now,
            updatedAt: now
        )
        try insertInvestmentTransaction(db, transaction: transaction)
        return transaction
    }
    try recalculateInvestmentLedger(fundName: transaction.fundName)
    return try requireInvestmentTransaction(id: transaction.id)
}
```

Add private calculation:

```swift
private func recalculateInvestmentLedger(fundName: String) throws {
    try database.writer.write { db in
        let transactions = try fetchInvestmentTransactions(db, fundName: fundName)
        var holdingShare = Decimal(0)
        var bookValue = Decimal(0)
        var latestNav: Decimal?

        for var transaction in transactions {
            transaction.realizedGain = 0
            transaction.realizedLoss = 0
            transaction.bookAmount = nil

            switch transaction.transactionType {
            case .buy:
                let amount = transaction.tradeAmount ?? 0
                let share = transaction.tradeShare ?? 0
                transaction.bookAmount = roundCurrency(amount)
                holdingShare += share
                bookValue += amount
            case .sell:
                let amount = transaction.tradeAmount ?? 0
                let share = transaction.tradeShare ?? 0
                let averageCost = holdingShare == 0 ? Decimal(0) : bookValue / holdingShare
                let bookAmount = roundCurrency(share * averageCost)
                let realized = abs(amount) - abs(bookAmount)
                transaction.bookAmount = bookAmount
                if realized >= 0 {
                    transaction.realizedGain = roundCurrency(realized)
                } else {
                    transaction.realizedLoss = roundCurrency(abs(realized))
                }
                holdingShare += share
                bookValue += bookAmount
            case .nav:
                if let nav = transaction.nav {
                    latestNav = nav
                }
            }

            if let nav = transaction.nav {
                latestNav = nav
            }
            transaction.holdingShare = roundShare(holdingShare)
            transaction.bookValue = roundCurrency(bookValue)
            transaction.averageCost = holdingShare == 0 ? nil : roundUnitCost(bookValue / holdingShare)
            transaction.presentValue = latestNav.map { roundCurrency(holdingShare * $0) }
            transaction.updatedAt = Date()
            try persistInvestmentTransactionUpdate(db, transaction: transaction)
        }
    }
}
```

Add helpers `roundCurrency`, `roundShare`, `roundUnitCost` using `NSDecimalRound`, plus `insertInvestmentTransaction`, `persistInvestmentTransactionUpdate`, `fetchInvestmentTransactions`, `investmentTransaction(from:)`, and `requireInvestmentTransaction(id:)`.

Validation rules:

- `fundName` trimmed and non-empty.
- `buy`: `tradeAmount > 0`, `tradeShare > 0`.
- `sell`: `tradeAmount < 0`, `tradeShare < 0`, cannot sell more than current holding after recalculation.
- `nav`: `nav > 0`.
- `accountMonth` uses existing `validateAccountMonth`.

**Step 4: Run test to verify it passes**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1InvestmentLedgerTests/testAverageCostCalculatesSellBookAmountAndLoss
```

Expected: PASS.

**Step 5: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1InvestmentLedgerTests.swift
git commit -m "feat: calculate investment average cost"
```

## Task 3: 投资回填流水与现金/投资引擎影响

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1InvestmentLedgerTests.swift`

**Step 1: Write the failing test**

Append:

```swift
func testInvestmentSellCreatesFeedRecordsAndRecalculatesCashAndInvestmentAsset() throws {
    let database = try LedgerDatabase.inMemory()
    let useCases = LedgerUseCases(database: database)
    try useCases.initializeLedgerSeed()

    _ = try useCases.createInvestmentTransaction(input: investmentInput(
        accountMonth: "2026-03",
        occurredAt: "2026-03-10T00:00:00Z",
        type: .buy,
        amount: Decimal(300),
        share: Decimal(200),
        nav: Decimal(string: "1.50")!
    ))
    let sell = try useCases.createInvestmentTransaction(input: investmentInput(
        accountMonth: "2026-04",
        occurredAt: "2026-04-10T00:00:00Z",
        type: .sell,
        amount: Decimal(-120),
        share: Decimal(-100),
        note: "赎回"
    ))

    let feedRecords = try useCases.queryJournalRecords(
        filter: JournalRecordFilter(accountMonths: ["2026-04"], includeEngineRecords: true)
    ).filter { $0.recordSource == .investmentFeed }

    XCTAssertEqual(feedRecords.count, 2)
    let sellCost = try XCTUnwrap(feedRecords.first { $0.paymentDetailName == "金融资产投资" })
    XCTAssertEqual(sellCost.amount, Decimal(-150))
    XCTAssertEqual(sellCost.paymentTypeName, "资产类支出")
    XCTAssertEqual(sellCost.sourceInvestmentTransactionIds, [sell.id])

    let loss = try XCTUnwrap(feedRecords.first { $0.paymentDetailName == "投资亏损" })
    XCTAssertEqual(loss.amount, Decimal(30))
    XCTAssertEqual(loss.paymentTypeName, "财务费用开支")
    XCTAssertEqual(loss.sourceInvestmentTransactionIds, [sell.id])

    let home = try useCases.queryHomeSummary(accountMonth: "2026-04")
    XCTAssertEqual(home.expenseTotal, Decimal(30))

    let balance = try useCases.queryBalanceSummary(accountMonth: "2026-04")
    XCTAssertEqual(balance.cashBalance, Decimal(120))
    XCTAssertEqual(balance.investmentItems, [
        BalanceItem(name: "总投资资产", amount: Decimal(150), sourceRecordIds: [])
    ])
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1InvestmentLedgerTests/testInvestmentSellCreatesFeedRecordsAndRecalculatesCashAndInvestmentAsset
```

Expected: FAIL because feed records and investment balance integration do not exist.

**Step 3: Generate monthly feed records**

After recalculating transactions, group changed fund transactions by `accountMonth`. For each affected month and fund:

- Delete stale rows:

```swift
try db.execute(sql: """
    DELETE FROM journal_records
    WHERE record_source = ?
      AND account_month = ?
      AND object_key = ?
    """, arguments: [
        RecordSource.investmentFeed.rawValue,
        accountMonth,
        "investment:\(fundName)"
    ])
```

- Insert up to three `investment_feed` rows:

```swift
private enum InvestmentFeedKind {
    case bookAmount
    case realizedGain
    case realizedLoss
}
```

Rules:

- `bookAmount = sum(buy.bookAmount + sell.bookAmount)`; if non-zero, create `资产类支出 / 金融资产投资` with that signed amount.
- `realizedGain = sum(realizedGain)`; if non-zero, create `理财收入 / 投资收益`.
- `realizedLoss = sum(realizedLoss)`; if non-zero, create `财务费用开支 / 投资亏损`.
- `paymentMethodName = "电子钱包余额"`.
- `recordSource = .investmentFeed`.
- `recordKind = .carryForward`.
- `carryForwardRole = .accountingSkeleton`.
- `objectKey = "investment:\(fundName)"`.
- `sourceInvestmentTransactionIds = affected transaction ids sorted by UUID`.
- `occurredAt = monthEndPlaceholder(accountMonth)`.

**Step 4: Update engine cash and investment balance**

In `makeP0EngineDrafts`, rename to `makeEngineDrafts` and update cash rows:

```swift
let cashRows = rows.filter {
    $0.paymentMethod.methodType == .asset &&
    ($0.paymentType.element == .expense || $0.paymentType.element == .asset)
}
let cashAmount = cashRows.reduce(Decimal(0)) { $0 - $1.record.amount }
```

Add an investment engine draft for the selected `accountMonth`:

```swift
let holdingRows = try fetchInvestmentHoldings(db, accountMonth: accountMonth)
let investmentAmount = holdingRows.reduce(Decimal(0)) { $0 + $1.bookValue }
if investmentAmount != 0 {
    drafts.append(EngineRecordDraft(
        accountMonth: accountMonth,
        occurredAt: monthEndPlaceholder(accountMonth),
        amount: investmentAmount,
        note: "总投资资产期末余额",
        engineFamily: .investment,
        engineKey: "\(accountMonth):investment:ending_balance:investment:总投资资产",
        objectKey: "investment:总投资资产",
        sourceRecordIds: [],
        sourceInvestmentTransactionIds: holdingRows.flatMap(\.sourceTransactionIds).sorted { $0.uuidString < $1.uuidString }
    ))
}
```

Extend `EngineRecordDraft` and `makeEngineRecord` to include `sourceInvestmentTransactionIds`.

Update `fetchP0EngineRecords` to include `.investment`.

Update `BalanceSummary` to add:

```swift
public var investmentItems: [BalanceItem]
```

In `queryBalanceSummary`, map `.investment` engine records to `investmentItems`, with display name `总投资资产`.

**Step 5: Run test to verify it passes**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1InvestmentLedgerTests/testInvestmentSellCreatesFeedRecordsAndRecalculatesCashAndInvestmentAsset
```

Expected: PASS.

**Step 6: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1InvestmentLedgerTests.swift
git commit -m "feat: reflow investment feed records"
```

## Task 4: 编辑/删除投资交易与受影响账月重算

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1InvestmentLedgerTests.swift`

**Step 1: Write the failing test**

Append:

```swift
func testUpdatingAndDeletingInvestmentTransactionReplacesAffectedMonthlyFeeds() throws {
    let database = try LedgerDatabase.inMemory()
    let useCases = LedgerUseCases(database: database)
    try useCases.initializeLedgerSeed()

    _ = try useCases.createInvestmentTransaction(input: investmentInput(
        accountMonth: "2026-03",
        occurredAt: "2026-03-10T00:00:00Z",
        type: .buy,
        amount: Decimal(300),
        share: Decimal(200)
    ))
    let sell = try useCases.createInvestmentTransaction(input: investmentInput(
        accountMonth: "2026-04",
        occurredAt: "2026-04-10T00:00:00Z",
        type: .sell,
        amount: Decimal(-120),
        share: Decimal(-100)
    ))

    _ = try useCases.updateInvestmentTransaction(
        id: sell.id,
        changes: InvestmentTransactionChanges(tradeAmount: Decimal(-180), tradeShare: Decimal(-100))
    )
    var feedRecords = try useCases.queryJournalRecords(
        filter: JournalRecordFilter(accountMonths: ["2026-04"], includeEngineRecords: true)
    ).filter { $0.recordSource == .investmentFeed }

    XCTAssertEqual(feedRecords.count, 2)
    XCTAssertEqual(feedRecords.first { $0.paymentDetailName == "金融资产投资" }?.amount, Decimal(-150))
    XCTAssertEqual(feedRecords.first { $0.paymentDetailName == "投资收益" }?.amount, Decimal(30))
    XCTAssertNil(feedRecords.first { $0.paymentDetailName == "投资亏损" })

    try useCases.deleteInvestmentTransaction(id: sell.id)
    feedRecords = try useCases.queryJournalRecords(
        filter: JournalRecordFilter(accountMonths: ["2026-04"], includeEngineRecords: true)
    ).filter { $0.recordSource == .investmentFeed }
    XCTAssertTrue(feedRecords.isEmpty)
    XCTAssertEqual(try useCases.queryBalanceSummary(accountMonth: "2026-04").investmentItems.first?.amount, Decimal(300))
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1InvestmentLedgerTests/testUpdatingAndDeletingInvestmentTransactionReplacesAffectedMonthlyFeeds
```

Expected: FAIL because update/delete Use Cases do not exist.

**Step 3: Implement update/delete Use Cases**

Add:

```swift
@discardableResult
public func updateInvestmentTransaction(id: UUID, changes: InvestmentTransactionChanges) throws -> InvestmentTransaction

public func deleteInvestmentTransaction(id: UUID) throws
```

Implementation rules:

- Load original transaction before mutation.
- Apply changed fields.
- Validate final input.
- Persist.
- Recalculate the old fund and the new fund if fund name changed.
- Recalculate all account months touched by that fund's transactions and stale feed rows.
- After investment reflow, call `recalculateAccountMonth` for every affected month.
- Delete uses the same reflow path and includes the deleted transaction's old month to clean stale feed rows.

**Step 4: Run test to verify it passes**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1InvestmentLedgerTests/testUpdatingAndDeletingInvestmentTransactionReplacesAffectedMonthlyFeeds
```

Expected: PASS.

**Step 5: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1InvestmentLedgerTests.swift
git commit -m "feat: update and delete investment transactions"
```

## Task 5: 投资读模型、回填追溯与只读边界

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1InvestmentLedgerTests.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P0LedgerFlowTests.swift`

**Step 1: Write the failing test**

Append:

```swift
func testInvestmentReadModelsAndFeedTraceExposeSourceTransactions() throws {
    let database = try LedgerDatabase.inMemory()
    let useCases = LedgerUseCases(database: database)
    try useCases.initializeLedgerSeed()

    let buy = try useCases.createInvestmentTransaction(input: investmentInput(
        accountMonth: "2026-03",
        occurredAt: "2026-03-10T00:00:00Z",
        type: .buy,
        amount: Decimal(300),
        share: Decimal(200),
        nav: Decimal(string: "1.50")!
    ))
    let sell = try useCases.createInvestmentTransaction(input: investmentInput(
        accountMonth: "2026-04",
        occurredAt: "2026-04-10T00:00:00Z",
        type: .sell,
        amount: Decimal(-180),
        share: Decimal(-100)
    ))
    _ = try useCases.createInvestmentTransaction(input: investmentInput(
        accountMonth: "2026-04",
        occurredAt: "2026-04-30T00:00:00Z",
        type: .nav,
        nav: Decimal(string: "1.80")!,
        note: "月末净值"
    ))

    let holdings = try useCases.queryInvestmentHoldings(accountMonth: "2026-04")
    XCTAssertEqual(holdings.map(\.fundName), ["沪深300指数A"])
    XCTAssertEqual(holdings.first?.holdingShare, Decimal(100))
    XCTAssertEqual(holdings.first?.bookValue, Decimal(150))
    XCTAssertEqual(holdings.first?.presentValue, Decimal(180))
    XCTAssertEqual(holdings.first?.unrealizedGain, Decimal(30))
    XCTAssertEqual(holdings.first?.sourceTransactionIds.sorted { $0.uuidString < $1.uuidString }, [buy.id, sell.id].sorted { $0.uuidString < $1.uuidString })

    let summary = try useCases.queryInvestmentMonthlySummary(accountMonth: "2026-04", fundName: "沪深300指数A")
    XCTAssertEqual(summary.sellBookAmount, Decimal(-150))
    XCTAssertEqual(summary.realizedGain, Decimal(30))
    XCTAssertEqual(summary.realizedLoss, Decimal(0))
    XCTAssertEqual(summary.endingBookValue, Decimal(150))

    let feed = try XCTUnwrap(try useCases.queryInvestmentFeedRecords(accountMonth: "2026-04", fundName: "沪深300指数A").first)
    let trace = try XCTUnwrap(try useCases.getInvestmentFeedTrace(recordId: feed.id))
    XCTAssertEqual(trace.transactions.map(\.id), [sell.id])
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1InvestmentLedgerTests/testInvestmentReadModelsAndFeedTraceExposeSourceTransactions
```

Expected: FAIL because monthly summary, feed query and trace query do not exist.

**Step 3: Implement read models**

Add public Use Cases:

```swift
public func queryInvestmentTransactions(fundName: String? = nil) throws -> [InvestmentTransaction]

public func queryInvestmentHoldings(accountMonth: String) throws -> [InvestmentHolding]

public func queryInvestmentMonthlySummary(accountMonth: String, fundName: String? = nil) throws -> InvestmentMonthlySummary

public func queryInvestmentFeedRecords(accountMonth: String, fundName: String? = nil) throws -> [JournalRecord]

public func getInvestmentFeedTrace(recordId: UUID) throws -> InvestmentFeedTrace?
```

Rules:

- Holdings use the latest calculated transaction per fund at or before `accountMonth` month end.
- Monthly summary includes transactions in that `accountMonth`, but ending book value/share come from the latest transaction at or before month end.
- Feed trace returns `nil` unless `recordSource == .investmentFeed` and `sourceInvestmentTransactionIds` is non-empty.
- `queryJournalRecords(recordIds:)` remains for journal ids; investment transaction trace uses the new investment query.

**Step 4: Strengthen non-editable record test**

Update `P0LedgerFlowTests.testEngineAndInvestmentFeedRecordsAreNotEditableOrDeletable` to create a real investment feed record through `createInvestmentTransaction`, then assert `updateJournalRecord` and `deleteJournalRecord` throw `.recordNotEditable(feed.id)`.

**Step 5: Run tests**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1InvestmentLedgerTests/testInvestmentReadModelsAndFeedTraceExposeSourceTransactions
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P0LedgerFlowTests/testEngineAndInvestmentFeedRecordsAreNotEditableOrDeletable
```

Expected: both PASS.

**Step 6: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests
git commit -m "feat: add investment read models"
```

## Task 6: LedgerStore 投资状态与 UITest 注入

**Files:**
- Modify: `ios/MingZhang/MingZhang/LedgerStore.swift`

**Step 1: Write compile-facing app state changes**

Add published state:

```swift
@Published private(set) var investmentHoldings: [InvestmentHolding] = []
@Published private(set) var investmentTransactions: [InvestmentTransaction] = []
@Published private(set) var investmentMonthlySummary = InvestmentMonthlySummary(
    accountMonth: "2026-04",
    fundName: nil,
    buyBookAmount: 0,
    sellBookAmount: 0,
    realizedGain: 0,
    realizedLoss: 0,
    endingBookValue: 0,
    endingShare: 0,
    feedJournalRecordIds: [],
    sourceTransactionIds: []
)
```

Update `refresh()`:

```swift
investmentHoldings = try useCases.queryInvestmentHoldings(accountMonth: accountMonth)
investmentMonthlySummary = try useCases.queryInvestmentMonthlySummary(accountMonth: accountMonth, fundName: nil)
```

**Step 2: Add store wrappers**

Add:

```swift
func loadInvestmentTransactions(fundName: String?) -> [InvestmentTransaction]
func loadInvestmentMonthlySummary(fundName: String?) -> InvestmentMonthlySummary?
func loadInvestmentFeedRecords(fundName: String?) -> [JournalRecord]
func loadInvestmentTrace(recordId: UUID) -> InvestmentFeedTrace?
func createInvestmentTransaction(input: InvestmentFormInput) -> Bool
func updateInvestmentTransaction(id: UUID, input: InvestmentFormInput) -> Bool
func deleteInvestmentTransaction(id: UUID) -> Bool
```

Add `InvestmentFormInput`:

```swift
struct InvestmentFormInput: Equatable {
    var accountMonth = "2026-04"
    var occurredDateText = "2026-04-10"
    var fundName = "沪深300指数A"
    var transactionType: InvestmentTransactionType = .buy
    var tradeAmountText = ""
    var tradeShareText = ""
    var navText = ""
    var note = ""
}
```

Parsing rules:

- `occurredDateText` parses `yyyy-MM-dd` and stores `00:00:00Z`.
- Amount/share/nav parse with `Locale(identifier: "en_US_POSIX")`.
- Empty amount/share/nav become `nil`.

**Step 3: Add UITest investment setup**

Extend `processUITestSetup()`:

```swift
if let setup = env["MZ_INVESTMENT_SETUP"] {
    for line in setup.split(separator: "\n") {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 8 else { continue }
        let input = try InvestmentFormInput(
            accountMonth: parts[0],
            occurredDateText: parts[1],
            fundName: parts[2],
            transactionType: InvestmentTransactionType(rawValue: parts[3]) ?? .buy,
            tradeAmountText: parts[4],
            tradeShareText: parts[5],
            navText: parts[6],
            note: parts[7]
        ).toCreateInput()
        _ = try useCases.createInvestmentTransaction(input: input)
    }
    try refresh()
}
```

**Step 4: Run app build**

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
git commit -m "feat: expose investment ledger state"
```

## Task 7: SwiftUI 投资入口、标的详情与交易编辑

**Files:**
- Modify: `ios/MingZhang/MingZhang/RootView.swift`

**Step 1: Add Balance entry**

Modify `BalanceView`:

- In Section `资产`, after cash asset, show `基金投资资产`.
- If `store.investmentHoldings` is empty, show `SummaryRow(title: "基金投资资产", value: 0)`.
- If not empty, navigate to `InvestmentFundListView()`.

Add accessibility identifiers:

- `investment_asset_entry`
- `investment_fund_row_<fundName>`
- `investment_add_transaction_button`
- `investment_save_button`

**Step 2: Add investment views in `RootView.swift`**

Add:

```swift
struct InvestmentFundListView: View
struct InvestmentLedgerView: View
struct InvestmentTransactionFormView: View
struct InvestmentFeedRecordsSection: View
struct InvestmentTransactionRow: View
```

Minimum behavior:

- `InvestmentFundListView`: lists `store.investmentHoldings`; each row opens `InvestmentLedgerView(fundName:)`.
- `InvestmentLedgerView`: shows fund name, book value, holding share, PV, unrealized gain, monthly summary, feed records and transactions; toolbar `plus` opens transaction form.
- `InvestmentTransactionFormView`: create/edit/delete investment transactions; save triggers store wrapper; delete has confirmation.
- `InvestmentFeedRecordsSection`: shows `investment_feed` records for current month/fund; tap opens `JournalFormView(mode: .edit(record))`, which is read-only because `recordSource == .investmentFeed`.

**Step 3: Add form controls**

Use controls:

- `TextField("账月", text: $input.accountMonth)`
- `TextField("日期", text: $input.occurredDateText)`
- `TextField("标的名称", text: $input.fundName)`
- `Picker("交易类别", selection: $input.transactionType)` with `.segmented`
- `TextField("交易金额", text: $input.tradeAmountText)`
- `TextField("交易份额", text: $input.tradeShareText)`
- `TextField("单位净值", text: $input.navText)`
- `TextField("备注", text: $input.note, axis: .vertical)`

For `nav` records, keep amount/share optional and disable nothing in v1.0; validation comes from Core.

**Step 4: Run app build**

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
git add ios/MingZhang/MingZhang/RootView.swift
git commit -m "feat: add investment ledger UI"
```

## Task 8: 统计投资结果入口与跳转

**Files:**
- Modify: `ios/MingZhang/MingZhang/RootView.swift`
- Modify: `ios/MingZhang/MingZhang/LedgerStore.swift`

**Step 1: Add failing UI-facing expectation manually**

Before implementation, run the app and confirm `统计` tab has no investment result section. This task is UI-only; no separate unit test is required before code, because Task 9 adds XCUITest.

**Step 2: Implement statistics investment section**

Modify `StatisticsView`:

- Add Section `投资结果`.
- Show:
  - `已实现收益`
  - `已实现亏损`
  - `已实现净结果`
  - `投资资产期末`
- Add `NavigationLink` to `InvestmentResultView()`.

Add:

```swift
struct InvestmentResultView: View
struct InvestmentFundResultView: View
```

Rules:

- `InvestmentResultView` lists current `store.investmentHoldings`.
- Tapping a fund opens `InvestmentFundResultView(fundName:)`.
- `InvestmentFundResultView` shows summary and links to `InvestmentLedgerView(fundName:)`.
- No add/edit/delete controls in statistics views.

**Step 3: Run app build**

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

**Step 4: Commit**

```bash
git add ios/MingZhang/MingZhang/RootView.swift ios/MingZhang/MingZhang/LedgerStore.swift
git commit -m "feat: link investment results from statistics"
```

## Task 9: XCUITest 覆盖投资主路径

**Files:**
- Modify: `ios/MingZhang/MingZhangUITests/MingZhangUITests.swift`

**Step 1: Write the failing UI test**

Append a new test class:

```swift
final class InvestmentLedgerUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment["MZ_INVESTMENT_SETUP"] = """
        2026-03|2026-03-10|沪深300指数A|buy|300|200|1.50|起始买入
        2026-04|2026-04-10|沪深300指数A|sell|-120|-100||赎回
        """
    }

    override func tearDown() {
        app.terminate()
    }

    func testInvestmentLedgerShowsHoldingFeedAndReadOnlyJournalRecord() {
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["资产负债"].waitForExistence(timeout: 10))
        app.tabBars.buttons["资产负债"].tap()

        XCTAssertTrue(app.buttons["investment_asset_entry"].waitForExistence(timeout: 10))
        app.buttons["investment_asset_entry"].tap()

        XCTAssertTrue(app.buttons["investment_fund_row_沪深300指数A"].waitForExistence(timeout: 10))
        app.buttons["investment_fund_row_沪深300指数A"].tap()

        XCTAssertTrue(app.staticTexts["沪深300指数A"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["投资亏损"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["金融资产投资"].waitForExistence(timeout: 10))

        app.staticTexts["投资亏损"].tap()
        XCTAssertTrue(app.navigationBars["记录详情"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["btn_save"].isEnabled)
    }
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
  -project ios/MingZhang/MingZhang.xcodeproj \
  -scheme MingZhang \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath ios/MingZhang/SourcePackages \
  -only-testing:MingZhangUITests/InvestmentLedgerUITests/testInvestmentLedgerShowsHoldingFeedAndReadOnlyJournalRecord
```

Expected before Task 6-8 implementation: FAIL. Expected after implementation: PASS.

**Step 3: Fix identifiers and UI navigation until test passes**

Only adjust SwiftUI accessibility identifiers, labels and navigation required by this test. Do not change domain rules in this task.

**Step 4: Run UI test**

Run the same `xcodebuild test` command.

Expected: PASS.

**Step 5: Commit**

```bash
git add ios/MingZhang/MingZhangUITests/MingZhangUITests.swift ios/MingZhang/MingZhang/RootView.swift ios/MingZhang/MingZhang/LedgerStore.swift
git commit -m "test: cover investment ledger UI flow"
```

## Task 10: Final verification and docs

**Files:**
- Modify: `ios/MingZhang/README.md`

**Step 1: Update README current scope**

Replace the P0-only note with:

```markdown
## 当前已覆盖范围

- P0 手工流水纵向闭环。
- P1 支付宝 / 微信导入整理。
- P1 基金投资明细账：基金交易事实、平均成本法、投资回填流水、资产负债和统计入口。

基金投资当前只支持手工维护交易和净值记录，不支持实时行情、非基金品类或复杂组合分析。
```

**Step 2: Run Core tests**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: all tests PASS.

**Step 3: Run app build**

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

**Step 4: Run investment UI test**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
  -project ios/MingZhang/MingZhang.xcodeproj \
  -scheme MingZhang \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath ios/MingZhang/SourcePackages \
  -only-testing:MingZhangUITests/InvestmentLedgerUITests/testInvestmentLedgerShowsHoldingFeedAndReadOnlyJournalRecord
```

Expected: PASS.

**Step 5: Inspect git diff**

Run:

```bash
git diff --stat
git diff -- ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests ios/MingZhang/MingZhang ios/MingZhang/MingZhangUITests ios/MingZhang/README.md
```

Expected:

- No unrelated files changed.
- `investment_feed` records are generated only from investment Use Cases.
- No `rm`, reset or unrelated cleanup.

**Step 6: Commit**

```bash
git add ios/MingZhang/README.md
git commit -m "docs: document investment ledger scope"
```

## Final Review Checklist

Run @superpowers:verification-before-completion before claiming done.

- Core tests pass.
- App builds on iPhone 17 simulator.
- Investment UI test passes or the failure is documented with exact simulator/output.
- `investment_feed` rows are read-only in journal detail.
- Buy uses `bookAmount = tradeAmount`.
- Sell uses `bookAmount = tradeShare * historicalAverageCost`, not trade amount.
- Realized gain and loss are separate feed rows.
- Modifying/deleting a transaction replaces stale feed rows.
- Asset负债 and 统计 can jump into investment details.
- No non-fund asset class, real-time quote, cloud sync, or AI scope was added.
