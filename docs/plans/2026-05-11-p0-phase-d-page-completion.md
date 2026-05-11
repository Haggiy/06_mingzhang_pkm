# P0 Phase D Page Completion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 补齐 P0 阶段 D 剩余核心页面能力：账月工作区、流水筛选与搜索、来源标记、资产/负债/统计分类详情，并保持所有结果可回溯到流水真源。

**Architecture:** 继续以 `ios/MingZhang` 为唯一工程入口，领域查询能力放在 `MingZhangCore`，SwiftUI 只承接页面状态、导航和展示。P0 只支持单账月选择，不实现全部/YTD/自定义范围；结果详情只解释当前账月 P0 cash/liability/expense 分类，不进入还款、导入、投资、备份和设置维护。

**Tech Stack:** Swift 6、SwiftUI、GRDB、XCTest、Xcode iOS Simulator。

---

## Context

`事实`

- 当前 P0 纵向闭环已经完成：新增 100、修改 120、删除归零、来源回溯、表单校验、现金资产、engine upsert/stale 清理。
- 当前 Core 自动化测试位于 `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P0LedgerFlowTests.swift`。
- 当前 SwiftUI 入口集中在 `ios/MingZhang/MingZhang/RootView.swift`，状态集中在 `ios/MingZhang/MingZhang/LedgerStore.swift`。
- 当前 App 没有独立 App test target；本轮 Core 可自动化的查询行为写 XCTest，SwiftUI 页面用 iOS build 和手动验收覆盖。

`依据`

- G-01、J-01、J-02、J-03、J-06、B-01、B-02、B-04、S-01、S-02：`docs/specs/2026-05-09-ios-page-field-state-spec.md`
- P0/P1 边界：`docs/prd/2026-05-09-v1-feature-acceptance-matrix.md`
- 当前路线图状态：`docs/work-plans/2026-05-08-ios-product-to-development-roadmap.md`

## Non-Goals

- 不做支付宝 / 微信导入候选、批量改账月、确认导入。
- 不做基金投资明细、investment_feed 回填、平均成本法。
- 不做递延资产、继承行释放、跨月传播。
- 不做备份、恢复、导出文件格式。
- 不做复杂设置维护、停用历史配置、语义标签编辑。
- 不做全部/YTD/自定义账月范围；P0 只做单账月选择。
- 不新增 App test target；UI 行为用 iOS build 和手动验收覆盖。

## Task 1: Core 账月列表查询

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P0LedgerFlowTests.swift`

**Step 1: Write the failing test**

在 `P0LedgerFlowTests` 增加测试，创建两个不同账月的真源记录，断言账月列表去重并按新账月在前排序。

```swift
func testQueryAccountMonthsReturnsDistinctMonthsDescending() throws {
    let database = try LedgerDatabase.inMemory()
    let useCases = LedgerUseCases(database: database)
    try useCases.initializeLedgerSeed()

    _ = try useCases.createManualRecord(input: sampleInput(accountMonth: "2026-03", amount: Decimal(80)))
    _ = try useCases.createManualRecord(input: sampleInput(accountMonth: "2026-04", amount: Decimal(100)))
    _ = try useCases.createManualRecord(input: sampleInput(accountMonth: "2026-04", amount: Decimal(50)))

    XCTAssertEqual(try useCases.queryAccountMonths(), ["2026-04", "2026-03"])
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P0LedgerFlowTests/testQueryAccountMonthsReturnsDistinctMonthsDescending
```

Expected: FAIL because `LedgerUseCases.queryAccountMonths()` does not exist.

**Step 3: Write minimal implementation**

在 `LedgerUseCases` 中新增：

```swift
public func queryAccountMonths() throws -> [String] {
    try database.writer.read { db in
        try String.fetchAll(db, sql: """
            SELECT DISTINCT account_month
            FROM journal_records
            WHERE record_source != ?
            ORDER BY account_month DESC
            """, arguments: [RecordSource.engine.rawValue])
    }
}
```

说明：

- 默认排除 `engine`，账月列表只由真源记录形成。
- P0 允许 `investment_feed` 出现在账月列表，因为它是真源；但本轮不实现投资编辑入口。

**Step 4: Run test to verify it passes**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P0LedgerFlowTests/testQueryAccountMonthsReturnsDistinctMonthsDescending
```

Expected: PASS.

**Step 5: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore
git commit -m "feat: query P0 account months"
```

## Task 2: Core 流水筛选与搜索查询

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P0LedgerFlowTests.swift`

**Step 1: Write the failing filter test**

新增测试：按收付手段、收付类型、类型明细、备注关键词和金额范围筛选，只返回匹配真源记录。

```swift
func testQueryJournalRecordsSupportsVisibleFieldFilters() throws {
    let database = try LedgerDatabase.inMemory()
    let useCases = LedgerUseCases(database: database)
    try useCases.initializeLedgerSeed()

    let lunch = try useCases.createManualRecord(input: sampleInput(amount: Decimal(100)))
    _ = try useCases.createManualRecord(
        input: CreateManualRecordInput(
            accountMonth: "2026-04",
            occurredAt: try Date.iso8601("2026-04-16T08:00:00Z"),
            paymentMethodName: "电子钱包余额",
            amount: Decimal(20),
            paymentTypeName: "生活必要开支",
            paymentDetailName: "伙食费",
            note: "早餐"
        )
    )

    let records = try useCases.queryJournalRecords(
        filter: JournalRecordFilter(
            accountMonths: ["2026-04"],
            paymentMethodNames: ["广发卡"],
            paymentTypeNames: ["生活必要开支"],
            paymentDetailNames: ["伙食费"],
            amountMin: Decimal(80),
            amountMax: Decimal(120),
            noteKeyword: "午餐"
        )
    )

    XCTAssertEqual(records.map(\.id), [lunch.id])
}
```

**Step 2: Write the failing search test**

新增测试：搜索关键词覆盖金额、收付手段、收付类型、类型明细、备注。

```swift
func testQueryJournalRecordsSupportsKeywordSearch() throws {
    let database = try LedgerDatabase.inMemory()
    let useCases = LedgerUseCases(database: database)
    try useCases.initializeLedgerSeed()

    let lunch = try useCases.createManualRecord(input: sampleInput(amount: Decimal(100)))
    _ = try useCases.createManualRecord(
        input: CreateManualRecordInput(
            accountMonth: "2026-04",
            occurredAt: try Date.iso8601("2026-04-16T08:00:00Z"),
            paymentMethodName: "电子钱包余额",
            amount: Decimal(20),
            paymentTypeName: "生活必要开支",
            paymentDetailName: "伙食费",
            note: "早餐"
        )
    )

    XCTAssertEqual(
        try useCases.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-04"], searchKeyword: "广发")
        ).map(\.id),
        [lunch.id]
    )
    XCTAssertEqual(
        try useCases.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-04"], searchKeyword: "午餐")
        ).map(\.id),
        [lunch.id]
    )
    XCTAssertEqual(
        try useCases.queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: ["2026-04"], searchKeyword: "100")
        ).map(\.id),
        [lunch.id]
    )
}
```

**Step 3: Run tests to verify they fail**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P0LedgerFlowTests/testQueryJournalRecordsSupportsVisibleFieldFilters
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P0LedgerFlowTests/testQueryJournalRecordsSupportsKeywordSearch
```

Expected: FAIL because `JournalRecordFilter` does not have these fields.

**Step 4: Extend `JournalRecordFilter`**

Replace the current struct with:

```swift
public struct JournalRecordFilter: Equatable, Sendable {
    public var accountMonths: [String]
    public var includeEngineRecords: Bool
    public var paymentMethodNames: [String]
    public var paymentTypeNames: [String]
    public var paymentDetailNames: [String]
    public var amountMin: Decimal?
    public var amountMax: Decimal?
    public var noteKeyword: String?
    public var searchKeyword: String?

    public init(
        accountMonths: [String],
        includeEngineRecords: Bool = false,
        paymentMethodNames: [String] = [],
        paymentTypeNames: [String] = [],
        paymentDetailNames: [String] = [],
        amountMin: Decimal? = nil,
        amountMax: Decimal? = nil,
        noteKeyword: String? = nil,
        searchKeyword: String? = nil
    ) {
        self.accountMonths = accountMonths
        self.includeEngineRecords = includeEngineRecords
        self.paymentMethodNames = paymentMethodNames
        self.paymentTypeNames = paymentTypeNames
        self.paymentDetailNames = paymentDetailNames
        self.amountMin = amountMin
        self.amountMax = amountMax
        self.noteKeyword = noteKeyword
        self.searchKeyword = searchKeyword
    }
}
```

**Step 5: Implement SQL predicates**

Update `queryJournalRecords(filter:)` to build conditions from user-visible fields only:

```swift
public func queryJournalRecords(filter: JournalRecordFilter) throws -> [JournalRecord] {
    guard !filter.accountMonths.isEmpty else { return [] }

    return try database.writer.read { db in
        var sql = selectJournalRecordSQL + " WHERE journal_records.account_month IN \(sqlPlaceholders(filter.accountMonths.count))"
        var arguments = StatementArguments(filter.accountMonths)

        if !filter.includeEngineRecords {
            sql += " AND journal_records.record_source != ?"
            arguments += [RecordSource.engine.rawValue]
        }
        if !filter.paymentMethodNames.isEmpty {
            sql += " AND payment_methods.name IN \(sqlPlaceholders(filter.paymentMethodNames.count))"
            arguments += StatementArguments(filter.paymentMethodNames)
        }
        if !filter.paymentTypeNames.isEmpty {
            sql += " AND payment_types.name IN \(sqlPlaceholders(filter.paymentTypeNames.count))"
            arguments += StatementArguments(filter.paymentTypeNames)
        }
        if !filter.paymentDetailNames.isEmpty {
            sql += " AND payment_details.name IN \(sqlPlaceholders(filter.paymentDetailNames.count))"
            arguments += StatementArguments(filter.paymentDetailNames)
        }
        if let amountMin = filter.amountMin {
            sql += " AND journal_records.amount >= ?"
            arguments += [amountMin]
        }
        if let amountMax = filter.amountMax {
            sql += " AND journal_records.amount <= ?"
            arguments += [amountMax]
        }
        if let noteKeyword = filter.noteKeyword?.trimmingCharacters(in: .whitespacesAndNewlines), !noteKeyword.isEmpty {
            sql += " AND journal_records.note LIKE ?"
            arguments += ["%\(noteKeyword)%"]
        }
        if let keyword = filter.searchKeyword?.trimmingCharacters(in: .whitespacesAndNewlines), !keyword.isEmpty {
            let pattern = "%\(keyword)%"
            sql += """
             AND (
                journal_records.amount LIKE ?
                OR payment_methods.name LIKE ?
                OR payment_types.name LIKE ?
                OR payment_details.name LIKE ?
                OR journal_records.note LIKE ?
             )
            """
            arguments += [pattern, pattern, pattern, pattern, pattern]
        }

        sql += " ORDER BY journal_records.occurred_at ASC, journal_records.created_at ASC"
        return try Row.fetchAll(db, sql: sql, arguments: arguments).map(journalRecord(from:))
    }
}
```

**Step 6: Run tests to verify they pass**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P0LedgerFlowTests/testQueryJournalRecordsSupportsVisibleFieldFilters
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P0LedgerFlowTests/testQueryJournalRecordsSupportsKeywordSearch
```

Expected: PASS.

**Step 7: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore
git commit -m "feat: filter and search P0 journal records"
```

## Task 3: Store 账月状态与查询入口

**Files:**
- Modify: `ios/MingZhang/MingZhang/LedgerStore.swift`
- Build-check: `ios/MingZhang/MingZhang/RootView.swift`

**Step 1: Add store state**

In `LedgerStore`, add:

```swift
@Published private(set) var availableAccountMonths: [String] = ["2026-04"]
@Published private(set) var journalFilter = JournalRecordFilter(accountMonths: ["2026-04"])
```

**Step 2: Update refresh**

Make `refresh()` update account months, then query with `journalFilter` synced to the selected month:

```swift
func refresh() throws {
    guard let useCases else { return }
    methods = try useCases.queryPaymentMethods()
    types = try useCases.queryPaymentTypes()
    details = try useCases.queryPaymentDetails()
    let queriedMonths = try useCases.queryAccountMonths()
    availableAccountMonths = queriedMonths.isEmpty ? [accountMonth] : queriedMonths
    if !availableAccountMonths.contains(accountMonth), let first = availableAccountMonths.first {
        accountMonth = first
    }
    journalFilter.accountMonths = [accountMonth]
    records = try useCases.queryJournalRecords(filter: journalFilter)
    homeSummary = try useCases.queryHomeSummary(accountMonth: accountMonth)
    balanceSummary = try useCases.queryBalanceSummary(accountMonth: accountMonth)
    statisticsSummary = try useCases.queryStatisticsSummary(accountMonth: accountMonth)
    lastError = nil
}
```

**Step 3: Add account month selection**

```swift
func selectAccountMonth(_ month: String) -> Bool {
    do {
        accountMonth = month
        journalFilter.accountMonths = [month]
        try refresh()
        return true
    } catch {
        lastError = error.localizedDescription
        return false
    }
}
```

**Step 4: Add journal filter APIs**

```swift
func applyJournalFilter(_ filter: JournalRecordFilter) -> Bool {
    do {
        var scopedFilter = filter
        scopedFilter.accountMonths = [accountMonth]
        journalFilter = scopedFilter
        guard let useCases else { return false }
        records = try useCases.queryJournalRecords(filter: scopedFilter)
        lastError = nil
        return true
    } catch {
        lastError = error.localizedDescription
        return false
    }
}

func clearJournalFilter() -> Bool {
    applyJournalFilter(JournalRecordFilter(accountMonths: [accountMonth]))
}

func queryRecords(filter: JournalRecordFilter) throws -> [JournalRecord] {
    guard let useCases else { return [] }
    return try useCases.queryJournalRecords(filter: filter)
}
```

**Step 5: Keep create/update month behavior predictable**

After successful create/update, switch to the record's账月 before refresh:

```swift
let created = try useCases.createManualRecord(input: try input.toCreateInput())
accountMonth = created.accountMonth
try refresh()
```

For update:

```swift
let updated = try useCases.updateJournalRecord(id: id, changes: try input.toChanges())
accountMonth = updated.accountMonth
try refresh()
```

**Step 6: Build to verify compile**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/MingZhang/MingZhang.xcodeproj -scheme MingZhang -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath ios/MingZhang/SourcePackages build
```

Expected: BUILD SUCCEEDED.

**Step 7: Commit**

```bash
git add ios/MingZhang/MingZhang/LedgerStore.swift
git commit -m "feat: add P0 month and journal filter state"
```

## Task 4: G-01 账月选择器 UI

**Files:**
- Modify: `ios/MingZhang/MingZhang/RootView.swift`
- Modify if needed: `ios/MingZhang/MingZhang/LedgerStore.swift`

**Step 1: Add `MonthPickerView`**

Add a small sheet view in `RootView.swift`:

```swift
struct MonthPickerView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("账月") {
                    ForEach(store.availableAccountMonths, id: \.self) { month in
                        Button {
                            if store.selectAccountMonth(month) {
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Text(month)
                                Spacer()
                                if month == store.accountMonth {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择账月")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}
```

**Step 2: Add reusable toolbar helper**

Add a small wrapper or repeated toolbar button in `HomeView`、`JournalView`、`BalanceView`、`StatisticsView`:

```swift
@State private var isShowingMonthPicker = false
```

Then add a toolbar item:

```swift
ToolbarItem(placement: .principal) {
    Button {
        isShowingMonthPicker = true
    } label: {
        Label(store.accountMonth, systemImage: "calendar")
            .labelStyle(.titleAndIcon)
    }
}
```

And sheet:

```swift
.sheet(isPresented: $isShowingMonthPicker) {
    MonthPickerView()
}
```

**Step 3: Replace hard-coded home section title**

Change:

```swift
Section("2026-04 摘要") {
```

to:

```swift
Section("\(store.accountMonth) 摘要") {
```

**Step 4: Build to verify compile**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/MingZhang/MingZhang.xcodeproj -scheme MingZhang -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath ios/MingZhang/SourcePackages build
```

Expected: BUILD SUCCEEDED.

**Step 5: Manual acceptance**

- 新增 `2026-04 / 广发卡 / 100 / 午餐`。
- 新增 `2026-05 / 电子钱包余额 / 50 / 早餐`。
- 在首页、流水、资产负债、统计分别打开账月选择器。
- 选择 `2026-04`，四个页面都只显示 4 月结果。
- 选择 `2026-05`，四个页面都只显示 5 月结果。

**Step 6: Commit**

```bash
git add ios/MingZhang/MingZhang
git commit -m "feat: add P0 account month picker"
```

## Task 5: J-02 流水筛选 UI

**Files:**
- Modify: `ios/MingZhang/MingZhang/RootView.swift`
- Modify if needed: `ios/MingZhang/MingZhang/LedgerStore.swift`

**Step 1: Add UI filter state**

Add near `JournalView`:

```swift
struct JournalFilterInput: Equatable {
    var paymentMethodName = ""
    var paymentTypeName = ""
    var paymentDetailName = ""
    var amountMinText = ""
    var amountMaxText = ""
    var noteKeyword = ""

    func toFilter(accountMonth: String) throws -> JournalRecordFilter {
        JournalRecordFilter(
            accountMonths: [accountMonth],
            paymentMethodNames: paymentMethodName.isEmpty ? [] : [paymentMethodName],
            paymentTypeNames: paymentTypeName.isEmpty ? [] : [paymentTypeName],
            paymentDetailNames: paymentDetailName.isEmpty ? [] : [paymentDetailName],
            amountMin: try parseOptionalDecimal(amountMinText, fieldName: "最小金额"),
            amountMax: try parseOptionalDecimal(amountMaxText, fieldName: "最大金额"),
            noteKeyword: noteKeyword.isEmpty ? nil : noteKeyword
        )
    }

    private func parseOptionalDecimal(_ value: String, fieldName: String) throws -> Decimal? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let amount = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else {
            throw MingZhangError.validation("\(fieldName)必须是有效数字")
        }
        return amount
    }
}
```

**Step 2: Add `JournalFilterView`**

```swift
struct JournalFilterView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var input = JournalFilterInput()

    var body: some View {
        NavigationStack {
            Form {
                Section("条件") {
                    Picker("收付手段", selection: $input.paymentMethodName) {
                        Text("全部").tag("")
                        ForEach(store.methods) { method in
                            Text(method.name).tag(method.name)
                        }
                    }
                    Picker("收付类型", selection: $input.paymentTypeName) {
                        Text("全部").tag("")
                        ForEach(store.types) { type in
                            Text(type.name).tag(type.name)
                        }
                    }
                    Picker("类型明细", selection: $input.paymentDetailName) {
                        Text("全部").tag("")
                        ForEach(filteredDetails) { detail in
                            Text(detail.name).tag(detail.name)
                        }
                    }
                    TextField("最小金额", text: $input.amountMinText)
                        .keyboardType(.decimalPad)
                    TextField("最大金额", text: $input.amountMaxText)
                        .keyboardType(.decimalPad)
                    TextField("备注关键词", text: $input.noteKeyword)
                }

                Section {
                    Button("重置") {
                        input = JournalFilterInput()
                        if store.clearJournalFilter() {
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("筛选")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        do {
                            if store.applyJournalFilter(try input.toFilter(accountMonth: store.accountMonth)) {
                                dismiss()
                            }
                        } catch {
                            store.lastError = error.localizedDescription
                        }
                    }
                }
            }
            .onChange(of: input.paymentTypeName) {
                if !filteredDetails.contains(where: { $0.name == input.paymentDetailName }) {
                    input.paymentDetailName = ""
                }
            }
        }
    }

    private var filteredDetails: [PaymentDetail] {
        guard let typeId = store.types.first(where: { $0.name == input.paymentTypeName })?.id else {
            return store.details
        }
        return store.details.filter { $0.paymentTypeId == typeId }
    }
}
```

**Step 3: Add filter entry to `JournalView`**

Add state:

```swift
@State private var isShowingFilter = false
```

Add toolbar button:

```swift
ToolbarItem(placement: .topBarLeading) {
    Button {
        isShowingFilter = true
    } label: {
        Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
    }
}
```

Add sheet:

```swift
.sheet(isPresented: $isShowingFilter) {
    JournalFilterView()
}
```

**Step 4: Add filter chip row**

In `JournalView` list, before records:

```swift
if store.journalFilter != JournalRecordFilter(accountMonths: [store.accountMonth]) {
    Section("当前筛选") {
        Button {
            _ = store.clearJournalFilter()
        } label: {
            Label("清除筛选", systemImage: "xmark.circle")
        }
    }
}
```

**Step 5: Build to verify compile**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/MingZhang/MingZhang.xcodeproj -scheme MingZhang -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath ios/MingZhang/SourcePackages build
```

Expected: BUILD SUCCEEDED.

**Step 6: Manual acceptance**

- 新增 `广发卡 / 100 / 午餐`。
- 新增 `电子钱包余额 / 20 / 早餐`。
- 在流水页筛选 `收付手段 = 广发卡`，只看到午餐。
- 点击清除筛选后，两条都能看到。
- 输入非法金额筛选值 `abc`，页面不关闭并显示错误。

**Step 7: Commit**

```bash
git add ios/MingZhang/MingZhang
git commit -m "feat: add P0 journal filters"
```

## Task 6: J-03 流水搜索 UI

**Files:**
- Modify: `ios/MingZhang/MingZhang/RootView.swift`

**Step 1: Add `JournalSearchView`**

```swift
struct JournalSearchView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var keyword = ""
    @State private var results: [JournalRecord] = []

    var body: some View {
        List {
            if keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView("输入关键词", systemImage: "magnifyingglass")
            } else if results.isEmpty {
                ContentUnavailableView("没有找到流水", systemImage: "tray")
            } else {
                ForEach(results) { record in
                    NavigationLink {
                        JournalFormView(mode: .edit(record))
                    } label: {
                        JournalRecordRow(record: record)
                    }
                }
            }
        }
        .navigationTitle("搜索")
        .searchable(text: $keyword, prompt: "金额、账户、分类、备注")
        .onChange(of: keyword) {
            search()
        }
        .onAppear(perform: search)
    }

    private func search() {
        do {
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                results = []
                return
            }
            results = try store.queryRecords(
                filter: JournalRecordFilter(accountMonths: [store.accountMonth], searchKeyword: trimmed)
            )
        } catch {
            store.lastError = error.localizedDescription
        }
    }
}
```

**Step 2: Add search entry**

In `JournalView`, add toolbar item:

```swift
ToolbarItem(placement: .topBarTrailing) {
    NavigationLink {
        JournalSearchView()
    } label: {
        Label("搜索", systemImage: "magnifyingglass")
    }
}
```

Keep the existing `记一笔` button as the primary action. If toolbar crowding occurs, use a `Menu` with `搜索`、`筛选`、`记一笔` actions rather than adding text-heavy buttons.

**Step 3: Build to verify compile**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/MingZhang/MingZhang.xcodeproj -scheme MingZhang -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath ios/MingZhang/SourcePackages build
```

Expected: BUILD SUCCEEDED.

**Step 4: Manual acceptance**

- 搜索 `午餐`，能看到对应流水并进入详情。
- 搜索 `广发`，能看到对应流水。
- 搜索 `100`，能看到金额为 100 的流水。
- 搜索不存在关键词，显示空状态。
- 搜索结果不展示 engine 行。

**Step 5: Commit**

```bash
git add ios/MingZhang/MingZhang/RootView.swift
git commit -m "feat: add P0 journal search"
```

## Task 7: 来源标记与只读边界表达

**Files:**
- Modify: `ios/MingZhang/MingZhang/RootView.swift`

**Step 1: Add display labels**

Add private extensions:

```swift
private extension RecordSource {
    var displayName: String {
        switch self {
        case .manual:
            return "手工"
        case .import:
            return "导入"
        case .investmentFeed:
            return "投资回填"
        case .engine:
            return "引擎"
        }
    }
}
```

`import` 是 Swift 关键字，当前 Core 中的 case 写法是 `.import`。

**Step 2: Update `JournalRecordRow`**

Add a compact source badge under the second line:

```swift
Text(record.recordSource.displayName)
    .font(.caption2)
    .foregroundStyle(.secondary)
```

Keep it text-only and compact; do not introduce decorative cards.

**Step 3: Guard edit mode for non-editable records**

P0 normal queries exclude engine, but source queries may eventually include non-manual true sources. In `JournalFormView`, compute:

```swift
private var isEditableRecord: Bool {
    switch mode {
    case .create:
        return true
    case .edit(let record):
        return record.recordSource == .manual || record.recordSource == .import
    }
}
```

Disable save/delete for non-editable records:

```swift
Button("保存") {
    if save() { dismiss() }
}
.disabled(!isEditableRecord)
```

And only show delete section if editable.

**Step 4: Build to verify compile**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/MingZhang/MingZhang.xcodeproj -scheme MingZhang -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath ios/MingZhang/SourcePackages build
```

Expected: BUILD SUCCEEDED.

**Step 5: Manual acceptance**

- 流水列表每条记录显示来源标记。
- 手工记录仍可进入详情并保存/删除。
- engine 行默认不出现在普通流水、搜索和来源列表。

**Step 6: Commit**

```bash
git add ios/MingZhang/MingZhang/RootView.swift
git commit -m "feat: show P0 journal source markers"
```

## Task 8: 资产、负债、统计分类详情态

**Files:**
- Modify: `ios/MingZhang/MingZhang/RootView.swift`

**Step 1: Add `AssetDetailView`**

```swift
struct AssetDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    let title: String
    let amount: Decimal
    let sourceRecordIds: [UUID]

    var body: some View {
        List {
            Section("余额") {
                SummaryRow(title: title, value: amount)
            }

            Section("来源") {
                if sourceRecordIds.isEmpty {
                    ContentUnavailableView("暂无来源流水", systemImage: "tray")
                } else {
                    NavigationLink {
                        SourceRecordsView(
                            title: "\(title) 来源",
                            filterDescription: "\(store.accountMonth) / \(title)",
                            recordIds: sourceRecordIds
                        )
                    } label: {
                        Text("来源流水 \(sourceRecordIds.count) 条")
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}
```

**Step 2: Add `LiabilityDetailView`**

```swift
struct LiabilityDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    let item: BalanceItem

    var body: some View {
        List {
            Section("余额") {
                SummaryRow(title: "剩余负债", value: item.amount)
            }

            Section("来源") {
                NavigationLink {
                    SourceRecordsView(
                        title: "\(item.name) 来源",
                        filterDescription: "\(store.accountMonth) / \(item.name)",
                        recordIds: item.sourceRecordIds
                    )
                } label: {
                    Text("来源流水 \(item.sourceRecordIds.count) 条")
                }
            }
        }
        .navigationTitle(item.name)
    }
}
```

**Step 3: Add `ExpenseCategoryDetailView`**

```swift
struct ExpenseCategoryDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    let item: ExpenseTypeSummary

    var body: some View {
        List {
            Section("金额") {
                SummaryRow(title: item.typeName, value: item.amount)
            }

            Section("来源") {
                NavigationLink {
                    SourceRecordsView(
                        title: "\(item.typeName) 来源",
                        filterDescription: "\(store.accountMonth) / \(item.typeName)",
                        recordIds: item.sourceRecordIds
                    )
                } label: {
                    Text("来源流水 \(item.sourceRecordIds.count) 条")
                }
            }
        }
        .navigationTitle(item.typeName)
    }
}
```

**Step 4: Wire `BalanceView` to detail pages**

Change the cash asset row to navigate to `AssetDetailView` when source exists:

```swift
NavigationLink {
    AssetDetailView(
        title: "现金类资产",
        amount: store.balanceSummary.cashBalance,
        sourceRecordIds: store.balanceSummary.cashSourceRecordIds
    )
} label: {
    SummaryRow(title: "现金类资产", value: store.balanceSummary.cashBalance)
}
```

Change liability rows to navigate to `LiabilityDetailView(item: item)` instead of directly to `SourceRecordsView`.

**Step 5: Wire `StatisticsView` to detail page**

Change expense category rows to navigate to:

```swift
ExpenseCategoryDetailView(item: item)
```

**Step 6: Build to verify compile**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/MingZhang/MingZhang.xcodeproj -scheme MingZhang -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath ios/MingZhang/SourcePackages build
```

Expected: BUILD SUCCEEDED.

**Step 7: Manual acceptance**

- 信用卡消费后，资产负债页点击 `广发卡` 进入负债详情，再进入来源流水，再进入流水详情。
- 现金消费后，资产负债页点击 `现金类资产` 进入资产详情，再进入来源流水。
- 统计页点击 `生活必要开支` 进入分类详情，再进入来源流水，再进入流水详情。
- 详情页只解释当前 P0 金额和来源，不出现还款、利息、投资、导入入口。

**Step 8: Commit**

```bash
git add ios/MingZhang/MingZhang/RootView.swift
git commit -m "feat: add P0 result detail views"
```

## Task 9: Full verification and docs update

**Files:**
- Modify if needed: `docs/work-plans/2026-05-08-ios-product-to-development-roadmap.md`
- Verify: `ios/MingZhang/Packages/MingZhangCore`
- Verify: `ios/MingZhang/MingZhang.xcodeproj`

**Step 1: Run Core tests**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: all tests pass.

**Step 2: Run iOS build**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/MingZhang/MingZhang.xcodeproj -scheme MingZhang -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath ios/MingZhang/SourcePackages build
```

Expected: BUILD SUCCEEDED.

**Step 3: Manual UI script**

Use a clean simulator or clear app data.

1. 新增 `2026-04 / 广发卡 / 生活必要开支 / 伙食费 / 100 / 午餐`。
2. 新增 `2026-05 / 电子钱包余额 / 生活必要开支 / 伙食费 / 50 / 早餐`。
3. 在首页、流水、资产负债、统计切换账月，确认四页同步刷新。
4. 在流水页筛选 `广发卡`，只看到 4 月午餐；清除筛选后恢复。
5. 在流水搜索 `午餐`、`广发`、`100`，都能定位到午餐并进入详情。
6. 在资产负债页进入 `广发卡` 详情，再进入来源流水，再进入午餐详情。
7. 在统计页进入 `生活必要开支` 详情，再进入来源流水，再进入午餐详情。
8. 修改午餐金额为 `120`，确认首页、资产负债、统计、详情都同步为 `120`。
9. 删除午餐，确认二次确认后 4 月广发卡负债和统计分类归零。
10. 确认普通流水、搜索、来源列表都不展示 engine 行。

**Step 4: Update roadmap checkboxes**

If all verification passes, update `docs/work-plans/2026-05-08-ios-product-to-development-roadmap.md`:

- 将“账月列表和账月范围选择器尚未工程化”改为已完成 P0 单账月选择。
- 将“流水筛选、搜索、来源标记尚未完整补齐”改为已完成 P0 基础筛选/搜索/来源标记。
- 将“资产详情、负债详情、分类详情仍是后续页面任务”改为已完成 P0 最小详情态。
- 保留“设置维护能力仍未进入工程实现”未完成。

**Step 5: Check root old project was not re-added**

Run:

```bash
git status --short --untracked-files=all
```

Expected:

- Changes only under `ios/MingZhang` and `docs/work-plans/2026-05-08-ios-product-to-development-roadmap.md` if the roadmap was updated.
- Do not add or restore root `MingZhang/`.

**Step 6: Commit**

```bash
git add ios/MingZhang docs/work-plans/2026-05-08-ios-product-to-development-roadmap.md
git commit -m "docs: mark P0 phase D page completion"
```

## Final Acceptance Criteria

- `swift test` passes in `ios/MingZhang/Packages/MingZhangCore`.
- iOS build succeeds for scheme `MingZhang` on iPhone 17 simulator.
- 首页、流水、资产负债、统计都能切换单账月并同步刷新。
- 流水支持 P0 基础筛选和关键词搜索。
- 流水行有来源标记。
- 资产详情、负债详情、统计分类详情能解释当前金额并继续回溯来源流水。
- 新增、修改、删除仍保持 P0 纵向闭环，不回归来源回溯、表单校验、现金资产和 engine upsert。
- `git status` 不出现旧根目录 `MingZhang/` 被重新加入。
