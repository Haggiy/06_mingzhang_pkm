# P1 支付宝 / 微信导入整理 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让支付宝 / 微信账单先进入导入候选区，经逐条或批量整理后再确认入账，并让确认后的流水进入既有 P0 账务闭环且可回溯到导入批次和原始账单行。

**Architecture:** 继续以 `ios/MingZhang` 为正式工程入口，`MingZhangCore` 承接导入批次、候选记录、字段映射、确认入账和回溯查询；`LedgerStore.swift` 只包装页面状态和 Use Case 调用；`RootView.swift` 只实现导入入口、候选预览、批量整理和确认流程。P1 只做支付宝 / 微信导入整理主路径，不扩展成通用导入系统。

**Tech Stack:** Swift 6、SwiftUI、GRDB、XCTest、Xcode iOS Simulator、本地 SQLite。

---

## Context

`事实`

- `docs/prd/mvp-prd.md` 明确：流水日记账是唯一最终入账来源；支付宝导入和微信导入是 MVP 必做导入来源；银行 / 信用卡导入、用户自定义导入字段映射、AI、云同步不进入 MVP。
- `docs/prd/2026-05-09-v1-feature-acceptance-matrix.md` 中 `F-P1-01`、`F-P1-02`、`F-P1-03` 和 `A-03`、`A-04` 要求：读取支付宝 / 微信账单，生成候选流水，支持补分类、改账月、确认入账；确认后生成 `record_source = import` 的流水真源。
- `docs/specs/import-alipay-wechat-spec.md` 明确：导入原始时间保留到秒；原始记录只有日期时补 `00:00:00`；默认按实际时间预填账月；支持逐条和批量改账月；确认前只是候选，确认后才进入流水。
- `docs/specs/record-and-month-spec.md` 明确：账月是强容器，不等同于自然月；修改账月不修改实际时间；`manual` 和 `import` 是可直接编辑真源记录。
- `docs/specs/settings-and-semantics-spec.md` 明确：导入字段映射不做用户配置；账月规则不做复杂配置；`待补真实账户` 是 v1.0 对 `收付手段=0` 的过渡表达。
- `docs/specs/2026-05-09-ios-page-field-state-spec.md` 中 `J-05`、`J-07` 要求：支付宝 / 微信整理复用同一页面模板；候选可逐条修改；批量可改账月、收付手段、收付类型、类型明细；批量修改不直接入账。
- `docs/specs/2026-05-09-local-data-model-engine-interface-spec.md` 已定义 `ImportBatch`、`ImportCandidateRecord`、导入 Use Case 边界，并要求 `ConfirmImportCandidates` 触发引擎。
- `docs/work-plans/2026-05-08-ios-product-to-development-roadmap.md` 已更新下一步：导入候选、批量整理、确认入账、来源回溯；当前正式工程入口是 `ios/MingZhang`，Core 包入口是 `ios/MingZhang/Packages/MingZhangCore`。
- 当前工程中 P0 主要代码集中在 `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`、`ios/MingZhang/MingZhang/LedgerStore.swift`、`ios/MingZhang/MingZhang/RootView.swift`。

`推断`

- P1 导入应先建立候选记录边界，再做批量整理，最后做确认入账；这样能保证确认前不污染首页、资产负债和统计。
- 为满足”流水可回溯到导入批次和原始账单行”，`JournalRecord` 需要新增 `sourceImportBatchId` 和 `sourceImportCandidateId`；原始行号、原始 payload、交易号或指纹保留在 `ImportCandidateRecord`。
- 支付宝 / 微信页面可复用一个 SwiftUI 模板，只通过 `ImportSource` 改标题、字段映射和默认说明。
- 当前 Core 只有一个源码文件；本计划允许新增 `ImportModels.swift` 放公共导入模型，数据库与 Use Case 先继续放在 `MingZhangCore.swift`，避免在 P1 同时做大拆文件重构。
- 微信 XLSX 格式账单字段结构与 CSV 一致，纳入 P1 支持范围；使用 `CoreXLSX`（Swift）或运行时读取第一个 sheet 转换为 CSV 行处理。

`待确认`

- ~~支付宝、微信真实导出文件的最终字段名、编码、分隔符~~ **已确认**：见下方「真实账单格式」表。
- **已确认**：保留原始交易号作为去重与回溯字段。支付宝用 `交易订单号`，微信用 `交易单号`；缺失时用 `交易时间 + 金额 + 交易对方 + 商品说明` 组合生成 `rawFingerprint`。
- ~~`待补真实账户` 在确认入账前是否必须补齐~~ **已确认**：允许 `待补真实账户` 直接确认入账，后续用户在流水中修改为真实收付手段。确认入账只要求 `paymentTypeId` 和 `paymentDetailId` 非空，`paymentMethodId` 可以为 `待补真实账户`。
- ~~退款、转账、手续费、非收支类账单行如何映射~~ **已确认**：见 Task 7 边界规则。支付宝有 `不计收支`（基金申赎、余额宝、信用卡还款等），微信有 `中性交易`（充值/提现/理财通/零钱通/信用卡还款），这些行 **不生成候选**。微信 `转账` 类型按 `收/支` 字段区分方向。支付宝 `交易状态=退款成功` 的退款行也按 `收/支` 字段区分方向，不做自动冲销。

### 真实账单格式（基于 2020-2025 年样例验证）

**支付宝 CSV：**

| 属性 | 值 |
|------|-----|
| 编码 | **GBK（GB2312）** |
| 分隔符 | 逗号为主，`交易订单号` 与 `商户订单号` 之间为 **Tab** |
| 元数据头部 | **24 行**（账号信息、时间范围、免责声明） |
| 数据起始行 | 第 25 行 |
| 金额格式 | 纯数字，如 `1.20` |
| 字段（共 12 列） | `交易时间`, `交易对方`, `交易对方`, `对方账号`, `商品说明`, `收/支`, `金额`, `收/付款方式`, `交易状态`, `交易订单号`, `商家订单号`, `备注`, |

**微信 CSV：**

| 属性 | 值 |
|------|-----|
| 编码 | **UTF-8 BOM** |
| 分隔符 | 逗号，新版用双引号包裹字段内容 |
| 元数据头部 | **16 行**（昵称、时间范围、注释） |
| 数据起始行 | 第 17 行 |
| 金额格式 | **带 ¥ 前缀**，如 `¥21.26` |
| 字段（共 11 列） | `交易时间`, `交易类型`, `交易对方`, `商品`, `收/支`, `金额(元)`, `支付方式`, `当前状态`, `交易单号`, `商户单号`, `备注` |

**微信 XLSX：**

- 汇总目录下存在大量 `.xlsx` 格式微信账单
- 字段结构与 CSV 完全一致（11 列），同样有 16 行元数据头部
- **纳入 P1 支持范围**，使用 `openpyxl`/`CoreXLSX` 等库读取

## Non-Goals

- 不做银行 / 信用卡账单导入。
- 不做通用导入系统、字段映射用户配置、复杂自动分类规则。
- 不做云同步、账号、多端冲突、备份恢复。
- 不做 AI / Agent。
- 不做投资明细、基金平均成本法、`investment_feed`。
- 不做复杂设置维护；P1 导入可以读取现有收付手段、收付类型、类型明细，但不在导入页维护配置。
- 不把候选记录放进首页、资产负债、统计或正式流水查询。
- **微信 XLSX 纳入 P1 支持范围**（汇总目录下有大量 XLSX 格式账单，字段结构与 CSV 一致）。

## Task 1: Core 导入模型、Schema 与回溯字段

**Files:**
- Create: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/ImportModels.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Create: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1ImportFlowTests.swift`

**Step 1: Write the failing test**

在 `P1ImportFlowTests.swift` 创建测试，验证导入批次查询、候选查询和正式流水回溯字段存在。

```swift
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
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1ImportFlowTests/testImportSchemaStartsEmptyAndSeedsPendingRealAccount
```

Expected: FAIL because `queryImportBatches()`、`queryImportCandidates(batchId:)`、`ImportBatch`、`ImportCandidateRecord` do not exist.

**Step 3: Write minimal implementation**

新增公共模型：

```swift
public enum ImportSource: String, Codable, Equatable, Sendable {
    case alipay
    case wechat
}

public enum ImportBatchStatus: String, Codable, Equatable, Sendable {
    case draft
    case confirmed
    case failed
}

public enum ImportCandidateStatus: String, Codable, Equatable, Sendable {
    case pending
    case ignored
    case confirmed
}

public struct ImportBatch: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var source: ImportSource
    public var fileName: String?
    public var importedAt: Date
    public var status: ImportBatchStatus
    public var confirmedRecordCount: Int
}

public struct ImportCandidateRecord: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var batchId: UUID
    public var status: ImportCandidateStatus
    public var accountMonth: String
    public var occurredAt: Date
    public var paymentMethodId: UUID?
    public var paymentMethodName: String?
    public var amount: Decimal
    public var paymentTypeId: UUID?
    public var paymentTypeName: String?
    public var paymentDetailId: UUID?
    public var paymentDetailName: String?
    public var note: String?
    public var rawLineNumber: Int
    public var rawPayload: String
    public var rawTransactionId: String?
    public var rawFingerprint: String
    public var createdJournalRecordId: UUID?
}
```

在 `MingZhangCore.swift` 中：

- `JournalRecord` 增加 `sourceImportBatchId: UUID?`、`sourceImportCandidateId: UUID?`。
- `v1_p0_ledger` 后追加迁移 `v2_p1_import`，新增 `import_batches`、`import_candidates` 表，并给 `journal_records` 增加 `source_import_batch_id`、`source_import_candidate_id`。
- `initializeLedgerSeed()` 新增 `待补真实账户`，类型为 `.pendingRealAccount`。
- 新增只读查询 `queryImportBatches()` 和 `queryImportCandidates(batchId:)`。

**Step 4: Run test to verify it passes**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1ImportFlowTests/testImportSchemaStartsEmptyAndSeedsPendingRealAccount
```

Expected: PASS.

**Step 5: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1ImportFlowTests.swift
git commit -m "feat: add import batch schema"
```

## Task 2: 支付宝 / 微信原始字段映射生成候选

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1ImportFlowTests.swift`
- Create: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/Fixtures/alipay-minimal.csv`
- Create: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/Fixtures/wechat-minimal.csv`

**Step 1: 准备真实字段 fixture 并写 failing test**

Fixture 使用与真实账单一致的字段名和格式（含元数据头、编码特征）：

`alipay-minimal.csv`（GBK 编码，24 行元数据头）：

```csv
------------------------------------------------------------------------------------
账户信息：
支付宝账户：test@example.com
起始时间：[2026-04-01 00:00:00]    终止时间：[2026-04-30 23:59:59]
导出交易类型：[全部]
导出时间：[2026-05-11 10:00:00]
共2笔记录
收入：1笔 50.00元
支出：1笔 100.00元
不计收支：0笔 0.00元

重要提示：
1.本数据可供支付宝账户对应的收支查询，因系统原因或通讯等偶发因素致本清单与实际交易结果不一致时，以实际交易金额为准。
2.请勿将本清单作为收款方还款凭证使用，请确认账户实际到账情况后再进行发货等操作。
3.支付宝支付的退款会同时体现支付和退款两条记录，请勿重复核算。
4.本清单如经任何涂改、残缺，均即失去效力。
5.部分特殊账单如：充值到余额、账户提取、信用卡还款等不计入收入和支出，会归入不计收支类。

------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
2026-04-15 12:30:45,餐饮美食,便利店,/,午餐,支出,100.00,广发卡(4896),交易成功,ALIPAY-001	,ALIPAY-M001	,,
2026-04-16 08:05:06,转账,张三,zha***@example.com,收到转账,收入,50.00,余额,交易成功,ALIPAY-002	,	,,
```

`wechat-minimal.csv`（UTF-8 BOM 编码，16 行元数据头）：

```csv
微信支付账单明细,,,,,,,,
微信昵称：[test],,,,,,,,
起始时间：[2026-04-01 00:00:00] 终止时间：[2026-04-30 23:59:59],,,,,,,,
导出类型：[全部],,,,,,,,
导出时间：[2026-05-11 10:00:00],,,,,,,,
,,,,,,,,
共2笔记录,,,,,,,,
收入：0笔 0.00元,,,,,,,,
支出：1笔 20.50元,,,,,,,,
中性交易：1笔 500.00元,,,,,,,,
注：,,,,,,,,
1. 充值/提现/理财通购买/零钱通存取/信用卡还款等交易，将计入中性交易,,,,,,,,
2. 本明细仅展示当前账单中的交易，不包括已删除的记录,,,,,,,,
3. 本明细仅供个人对账使用,,,,,,,,
,,,,,,,,
----------------------微信支付账单明细列表--------------------,,,,,,,,
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
2026-04-16 08:05:06,商户消费,早餐店,早餐,支出,¥20.50,零钱,支付成功,WECHAT-001	,WX-M001	,/
```

新增测试：

```swift
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

    // 支付宝：元数据头被正确跳过，只解析数据行
    XCTAssertEqual(alipay.batch.source, .alipay)
    XCTAssertEqual(alipay.candidates.count, 2) // 支出1笔 + 收入1笔
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

    // 微信：元数据头被正确跳过，中性交易不生成候选
    XCTAssertEqual(wechat.batch.source, .wechat)
    XCTAssertEqual(wechat.candidates.count, 1) // 只有支出1笔，中性交易被跳过
    XCTAssertEqual(wechat.issues.count, 0)

    let wechatExpense = try XCTUnwrap(wechat.candidates.first)
    XCTAssertEqual(wechatExpense.amount, Decimal(-20.50))
    XCTAssertEqual(wechatExpense.paymentMethodName, "待补真实账户") // "零钱"无法匹配已有PaymentMethod
    XCTAssertEqual(wechatExpense.rawTransactionId, "WECHAT-001")
    XCTAssertEqual(wechatExpense.note, "[商户消费] 早餐店 - 早餐")
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1ImportFlowTests/testCreateImportBatchMapsAlipayAndWechatRowsToCandidates
```

Expected: FAIL because `createImportBatch(source:fileName:contents:)` and fixture helper do not exist.

**Step 3: Write minimal implementation**

实现：

- `CreateImportBatchResult(batch:candidates:issues:)`。
- 编码检测：读取文件头部字节，检测 GBK（支付宝）和 UTF-8 BOM（微信）；无法识别时抛 `MingZhangError.validation`。
- 元数据头跳过：按来源类型跳过固定行数（支付宝 24 行、微信 16 行），定位到字段头行。
- 字段头校验：按来源类型校验字段头中包含必须字段关键词（如 `交易时间`、`收/支`、`金额`）；缺少必须字段时抛 `MingZhangError.validation("无法识别支付宝账单字段")` 或 `"无法识别微信账单字段"`。校验用关键词匹配而非完全相等，兼容末尾逗号、列数变化。
- 支付宝字段别名表：`交易时间`、`交易对方`（第 2 列=分类，第 3 列=对方名）、`对方账号`、`商品说明`、`收/支`、`金额`、`收/付款方式`、`交易状态`、`交易订单号`、`商家订单号`、`备注`。
- 微信字段别名表：`交易时间`、`交易类型`、`交易对方`、`商品`、`收/支`、`金额(元)`、`支付方式`、`当前状态`、`交易单号`、`商户单号`、`备注`。
- 混合分隔符处理：先按逗号分列，再用 Tab 拆分尾列中的 `交易单号/交易订单号\t商户单号/商家订单号` 组合。
- 金额清洗：微信去除 `¥` 前缀；收入金额取正，支出金额取负。
- `accountMonth` 从 `occurredAt` 推导 `YYYY-MM`。
- 原始付款方式能匹配现有 `PaymentMethod` 时填对应收付手段；不能匹配时填 `待补真实账户`。
- `paymentTypeId`、`paymentDetailId` 先为空，由用户整理补齐。
- `note` 按规则合并：支付宝 `[交易对方(分类)] 交易对方 - 商品说明`；微信 `[交易类型] 交易对方 - 商品`。
- `rawLineNumber` 记录 CSV 文件中的实际行号（含元数据头，1-indexed），便于回溯定位。

**Step 4: Run test to verify it passes**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1ImportFlowTests/testCreateImportBatchMapsAlipayAndWechatRowsToCandidates
```

Expected: PASS.

**Step 5: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore
git commit -m "feat: map alipay and wechat import candidates"
```

## Task 3: 候选记录不进入流水真源

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1ImportFlowTests.swift`

**Step 1: Write the failing test**

```swift
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
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1ImportFlowTests/testImportCandidatesDoNotAffectLedgerBeforeConfirmation
```

Expected: FAIL if batch creation inserts formal `journal_records` or if candidate months leak into `queryAccountMonths()`.

**Step 3: Write minimal implementation**

Ensure:

- `createImportBatch` only writes `import_batches` and `import_candidates`。
- `queryJournalRecords` only reads `journal_records`。
- `queryAccountMonths` remains based on non-engine `journal_records`，不读取 `import_candidates`。
- 首页、资产负债、统计仍只通过正式流水和 engine 记录计算。

**Step 4: Run test to verify it passes**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1ImportFlowTests/testImportCandidatesDoNotAffectLedgerBeforeConfirmation
```

Expected: PASS.

**Step 5: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore
git commit -m "test: keep import candidates outside ledger"
```

## Task 4: 单条候选整理与批量整理

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/ImportModels.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1ImportFlowTests.swift`

**Step 1: Write the failing test**

```swift
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
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1ImportFlowTests/testUpdateAndBatchUpdateImportCandidatesDoNotChangeOccurredAt
```

Expected: FAIL because `ImportCandidateChanges`、`updateImportCandidate`、`batchUpdateImportCandidates`、`ignoreImportCandidates` do not exist.

**Step 3: Write minimal implementation**

实现：

- `ImportCandidateChanges`，字段只包含 `accountMonth`、`paymentMethodName`、`paymentTypeName`、`paymentDetailName`、`note`。
- `updateImportCandidate(id:changes:)`。
- `batchUpdateImportCandidates(ids:changes:)`。
- `ignoreImportCandidates(ids:)`，只把 `pending` 候选改成 `.ignored`，不写入正式流水。
- 校验 `accountMonth` 为合法 `YYYY-MM`。
- 若传入 `paymentTypeName` 或 `paymentDetailName`，复用现有 `requirePaymentType`、`requirePaymentDetail`，保证类型明细归属于当前收付类型。
- 只允许修改 `pending` 候选；`confirmed` 和 `ignored` 候选抛 `MingZhangError.validation("只能整理待确认候选记录")`。

**Step 4: Run test to verify it passes**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1ImportFlowTests/testUpdateAndBatchUpdateImportCandidatesDoNotChangeOccurredAt
```

Expected: PASS.

**Step 5: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore
git commit -m "feat: edit import candidates"
```

## Task 5: 确认入账生成正式流水并进入 P0 闭环

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1ImportFlowTests.swift`

**Step 1: Write the failing test**

```swift
func testConfirmImportCandidatesCreatesImportRecordsAndRecalculates() throws {
    let database = try LedgerDatabase.inMemory()
    let useCases = LedgerUseCases(database: database)
    try useCases.initializeLedgerSeed()
    let batch = try useCases.createImportBatch(
        source: .alipay,
        fileName: "alipay-minimal.csv",
        contents: fixture("alipay-minimal.csv")
    )
    let candidate = try XCTUnwrap(batch.candidates.first)
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

    let confirmedCandidate = try XCTUnwrap(try useCases.queryImportCandidates(batchId: batch.batch.id).first)
    XCTAssertEqual(confirmedCandidate.status, .confirmed)
    XCTAssertEqual(confirmedCandidate.createdJournalRecordId, records.first?.id)
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1ImportFlowTests/testConfirmImportCandidatesCreatesImportRecordsAndRecalculates
```

Expected: FAIL because `confirmImportCandidates(ids:)` does not exist.

**Step 3: Write minimal implementation**

实现 `confirmImportCandidates(ids:)`：

- 只允许确认 `pending` 候选。
- 确认前要求 `paymentTypeId`、`paymentDetailId` 均非空；`paymentMethodId` 可以为 `待补真实账户`，允许后续在流水中补齐。
- 每个候选生成一条 `JournalRecord(recordSource: .import, recordKind: .normal, carryForwardRole: .none)`。
- 写入 `sourceImportBatchId`、`sourceImportCandidateId`。
- 候选状态改为 `.confirmed`，写入 `createdJournalRecordId`。
- 批次 `confirmedRecordCount` 递增；全部候选完成后批次状态改为 `.confirmed`。
- 按受影响账月调用既有 `recalculateAccountMonth`，进入 P0 cash/liability/statistics 闭环。

**Step 4: Run test to verify it passes**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1ImportFlowTests/testConfirmImportCandidatesCreatesImportRecordsAndRecalculates
```

Expected: PASS.

**Step 5: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore
git commit -m "feat: confirm import candidates into ledger"
```

## Task 6: 导入来源回溯到批次和原始账单行

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/ImportModels.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1ImportFlowTests.swift`

**Step 1: Write the failing test**

```swift
func testImportRecordCanTraceBackToBatchAndRawCandidate() throws {
    let database = try LedgerDatabase.inMemory()
    let useCases = LedgerUseCases(database: database)
    try useCases.initializeLedgerSeed()
    let batch = try useCases.createImportBatch(
        source: .alipay,
        fileName: "alipay-minimal.csv",
        contents: fixture("alipay-minimal.csv")
    )
    let candidate = try XCTUnwrap(batch.candidates.first)
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
    XCTAssertEqual(trace?.candidate.rawLineNumber, 26) // CSV 文件行号（含24行元数据头），非数据行序号
    XCTAssertTrue(trace?.candidate.rawPayload.contains("ALIPAY-001") == true)
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1ImportFlowTests/testImportRecordCanTraceBackToBatchAndRawCandidate
```

Expected: FAIL because `ImportTrace` and `getImportTrace(recordId:)` do not exist.

**Step 3: Write minimal implementation**

新增：

```swift
public struct ImportTrace: Equatable, Sendable {
    public var batch: ImportBatch
    public var candidate: ImportCandidateRecord
}
```

实现 `getImportTrace(recordId:) -> ImportTrace?`：

- 只对 `recordSource == .import` 且 `sourceImportBatchId` / `sourceImportCandidateId` 非空的流水返回。
- 查询对应 `import_batches` 和 `import_candidates`。
- 若正式流水被删除，候选仍保留 `createdJournalRecordId`，但 trace 查询以正式流水为入口时返回 nil。

**Step 4: Run test to verify it passes**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1ImportFlowTests/testImportRecordCanTraceBackToBatchAndRawCandidate
```

Expected: PASS.

**Step 5: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore
git commit -m "feat: trace import records to raw rows"
```

## Task 7: 错误、重复导入、非法金额、无法识别字段边界

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/ImportModels.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1ImportFlowTests.swift`

**Step 1: Write the failing test**

```swift
func testImportReportsInvalidAmountUnknownFieldsAndDuplicates() throws {
    let database = try LedgerDatabase.inMemory()
    let useCases = LedgerUseCases(database: database)
    try useCases.initializeLedgerSeed()

    // 无法识别字段：字段头缺少必须关键词
    XCTAssertThrowsError(try useCases.createImportBatch(
        source: .alipay,
        fileName: "unknown.csv",
        contents: "时间,金额\n2026-04-15,100"
    )) { error in
        XCTAssertEqual(error as? MingZhangError, .validation("无法识别支付宝账单字段"))
    }

    // 非法金额不生成候选，返回 issue
    let invalid = try useCases.createImportBatch(
        source: .alipay,
        fileName: "invalid-amount.csv",
        contents: """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-15 12:30:45,餐饮美食,便利店,/,午餐,支出,abc,广发卡,交易成功,ALIPAY-BAD	,	,,
        """
    )
    XCTAssertTrue(invalid.candidates.isEmpty)
    XCTAssertEqual(invalid.issues.first?.code, .invalidAmount)

    // 重复导入按 source + rawTransactionId 去重
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

    // 支付宝"不计收支"行不生成候选
    let alipayNeutral = try useCases.createImportBatch(
        source: .alipay,
        fileName: "alipay-neutral.csv",
        contents: """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-15 10:00:00,投资理财,余额宝,hua***@example.com,余额宝-转入,不计收支,500.00,中国银行储蓄卡(6863),交易成功,ALIPAY-NEUTRAL-001	,	,,
        2026-04-15 12:00:00,信用卡还款,招商银行信用卡,/,信用卡还款,不计收支,1000.00,中国银行储蓄卡(6863),交易成功,ALIPAY-NEUTRAL-002	,	,,
        2026-04-15 14:00:00,餐饮美食,便利店,/,午餐,支出,30.00,广发卡,交易成功,ALIPAY-VALID-001	,	,,
        """
    )
    XCTAssertEqual(alipayNeutral.candidates.count, 1) // 只有支出那行
    XCTAssertEqual(alipayNeutral.issues.filter { $0.code == .unsupportedDirection }.count, 2)

    // 微信"中性交易"行不生成候选（通过交易类型判断）
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
        2026-04-15 10:00:00,零钱提现,零钱提现,零钱提现,支出,¥500.00,中国银行储蓄卡,支付成功,WX-NEUTRAL-001	,	,/
        2026-04-15 12:00:00,信用卡还款,信用卡还款,信用卡还款,支出,¥1000.00,中国银行储蓄卡,支付成功,WX-NEUTRAL-002	,	,/
        2026-04-15 14:00:00,商户消费,便利店,午餐,支出,¥30.00,零钱,支付成功,WX-VALID-001	,	,/
        """
    )
    XCTAssertEqual(wechatNeutral.candidates.count, 1) // 只有商户消费那行
    XCTAssertEqual(wechatNeutral.issues.filter { $0.code == .unsupportedDirection }.count, 2)

    // 微信"转账"类型按收/支字段区分方向，正常生成候选
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
        2026-04-01 10:00:00,转账,同事李四,转账备注:AA制聚餐,收入,¥70.00,/,已存入零钱,WX-TRANSFER-001	,	,/
        2026-04-01 12:00:00,转账,同事李四,转账备注:还款,支出,¥20.00,零钱,对方已收钱,WX-TRANSFER-002	,	,/
        """
    )
    XCTAssertEqual(wechatTransfer.candidates.count, 2)
    let transferIncome = try XCTUnwrap(wechatTransfer.candidates.first { $0.amount > 0 })
    let transferExpense = try XCTUnwrap(wechatTransfer.candidates.first { $0.amount < 0 })
    XCTAssertEqual(transferIncome.amount, Decimal(70))
    XCTAssertEqual(transferExpense.amount, Decimal(-20))
}

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1ImportFlowTests/testImportReportsInvalidAmountUnknownFieldsAndDuplicates
```

Expected: FAIL because issue reporting and duplicate detection do not exist.

**Step 3: Write minimal implementation**

新增：

```swift
public enum ImportIssueCode: String, Codable, Equatable, Sendable {
    case invalidAmount
    case invalidDate
    case unknownFields
    case duplicate
    case unsupportedDirection
}

public struct ImportIssue: Equatable, Sendable {
    public var lineNumber: Int?
    public var code: ImportIssueCode
    public var message: String
}
```

边界规则：

- 缺少来源必需字段时，直接抛 `MingZhangError.validation("无法识别支付宝账单字段")` 或 `MingZhangError.validation("无法识别微信账单字段")`，不创建候选。检测方式：字段头中必须包含各来源的关键字段关键词（如支付宝必须含 `交易时间`、`收/支`、`金额`、`交易订单号`；微信必须含 `交易时间`、`收/支`、`金额(元)`、`交易单号`）。
- **非收支交易不生成候选**：
  - 支付宝 `收/支=不计收支`：不生成候选，返回 `.unsupportedDirection` issue。这包括但不限于：基金申购/赎回（投资理财类）、余额宝转入/转出、信用卡还款、账户提取、充值到余额。
  - 微信中性交易（通过 `交易类型` 判断）：**不**通过 `收/支` 字段判断，而是根据 `交易类型` 做前缀/通配符匹配。已知中性模式：`零钱提现`（精确匹配）、`信用卡还款`（精确匹配）、`转入零钱通-*`（前缀匹配，如"转入零钱通-来自零钱"、"转入零钱通-来自XX银行(XXXX)"）、`零钱通转出-*`（前缀匹配，如"零钱通转出-到零钱"、"零钱通转出-到XX银行(XXXX)"）。匹配成功时跳过该行，返回 `.unsupportedDirection` issue。
- **微信"转账"类型**：正常按 `收/支` 字段区分方向生成候选。转账可以是收入（收到转账）或支出（转出），与普通收支没有区别。
- **支付宝退款**：退款行（`交易状态=退款成功`）按 `收/支` 字段区分方向，不做自动冲销配对。
- 单行非法金额或非法时间不创建候选，返回 `ImportIssue`。
- 重复导入按 `source + rawTransactionId` 去重；没有交易号时按 `source + rawFingerprint` 去重。`rawFingerprint` 生成为 `SHA256(occurredAt + amount + counterparty + productDescription)` 的前 16 位十六进制。
- 重复行不创建候选，返回 `.duplicate` issue。

**Step 4: Run test to verify it passes**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1ImportFlowTests/testImportReportsInvalidAmountUnknownFieldsAndDuplicates
```

Expected: PASS.

**Step 5: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore
git commit -m "feat: handle import errors and duplicates"
```

## Task 8: LedgerStore 导入状态与 Use Case 封装

**Files:**
- Modify: `ios/MingZhang/MingZhang/LedgerStore.swift`
- Modify: `ios/MingZhang/MingZhang/RootView.swift`

**Step 1: Write the failing compile test**

先在 `RootView.swift` 的 `JournalView` toolbar 增加一个临时入口，引用尚未存在的 store API：

```swift
Button {
    store.prepareImport(source: .alipay)
} label: {
    Label("导入账单", systemImage: "square.and.arrow.down")
}
```

**Step 2: Run build to verify it fails**

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

Expected: FAIL with `Value of type 'LedgerStore' has no member 'prepareImport'` or missing `ImportSource` import surface.

**Step 3: Write minimal implementation**

在 `LedgerStore.swift` 新增页面状态：

- `@Published private(set) var activeImportSource: ImportSource?`
- `@Published private(set) var activeImportBatch: ImportBatch?`
- `@Published private(set) var importCandidates: [ImportCandidateRecord] = []`
- `@Published private(set) var importIssues: [ImportIssue] = []`
- `@Published var selectedImportCandidateIds: Set<UUID> = []`

新增方法：

- `prepareImport(source:)`
- `createImportBatch(source:fileName:contents:)`
- `updateImportCandidate(id:changes:)`
- `batchUpdateImportCandidates(ids:changes:)`
- `confirmSelectedImportCandidates()`
- `ignoreSelectedImportCandidates()`
- `loadImportTrace(recordId:)`

刷新规则：

- 创建批次、编辑候选、批量整理只刷新导入候选，不调用 `refresh()`。
- 确认入账成功后调用 `refresh()`，让首页、资产负债、统计进入 P0 闭环。

**Step 4: Run build to verify it passes**

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

Expected: PASS.

**Step 5: Commit**

```bash
git add ios/MingZhang/MingZhang/LedgerStore.swift ios/MingZhang/MingZhang/RootView.swift
git commit -m "feat: add import state to ledger store"
```

## Task 9: SwiftUI 导入入口、来源选择和候选预览

**Files:**
- Modify: `ios/MingZhang/MingZhang/RootView.swift`
- Modify: `ios/MingZhang/MingZhang/LedgerStore.swift`

**Step 1: Write the failing compile test**

在 `JournalView` 的 toolbar 引用尚未存在的视图：

```swift
.sheet(isPresented: $isShowingImport) {
    ImportSourcePickerView()
}
```

并在来源选择后进入：

```swift
ImportCandidateListView(source: source)
```

**Step 2: Run build to verify it fails**

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

Expected: FAIL because `ImportSourcePickerView` and `ImportCandidateListView` do not exist.

**Step 3: Write minimal implementation**

在 `RootView.swift` 新增：

- `ImportSourcePickerView`：只提供 `支付宝账单`、`微信账单` 两个入口。
- `ImportCandidateListView`：展示待确认数量、已忽略数量、issues、候选列表。
- 文件选择使用 SwiftUI `fileImporter`，只接收可读文本文件；读取为 String 后调用 `store.createImportBatch`。
- 候选行展示 `账月`、`时间`、`金额`、`收付手段`、`收付类型 / 类型明细`、`备注`、原始行号。
- 单条候选点击进入 `ImportCandidateEditView`，可修改账月、收付手段、收付类型、类型明细、备注。

不要在本 Task 中做批量面板和确认按钮，先只跑通来源选择、文件导入、候选预览、单条编辑。

**Step 4: Run build to verify it passes**

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

Expected: PASS.

**Step 5: Commit**

```bash
git add ios/MingZhang/MingZhang/RootView.swift ios/MingZhang/MingZhang/LedgerStore.swift
git commit -m "feat: preview import candidates"
```

## Task 10: SwiftUI 批量整理、确认入账和导入来源展示

**Files:**
- Modify: `ios/MingZhang/MingZhang/RootView.swift`
- Modify: `ios/MingZhang/MingZhang/LedgerStore.swift`

**Step 1: Write the failing compile test**

在 `ImportCandidateListView` 引用尚未存在的批量修改面板和导入 trace 展示：

```swift
.sheet(isPresented: $isShowingBatchEdit) {
    ImportBatchEditView(selectedIds: store.selectedImportCandidateIds)
}
```

在 `JournalFormView` 编辑 `recordSource == .import` 的流水时引用：

```swift
ImportTraceSection(record: record)
```

**Step 2: Run build to verify it fails**

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

Expected: FAIL because `ImportBatchEditView` and `ImportTraceSection` do not exist.

**Step 3: Write minimal implementation**

实现：

- 候选多选、全选、取消选择。
- `ImportBatchEditView`：批量修改账月、收付手段、收付类型、类型明细；点击应用后只写候选，不入账。
- `确认进入流水`：只对已选 pending 候选调用 `store.confirmSelectedImportCandidates()`。
- 确认成功后回到流水列表，并显示 `recordSource = import` 的正式流水。
- `ImportTraceSection`：在导入流水详情里展示导入来源、文件名、原始行号、原始交易号；不显示完整 rawPayload，避免详情页过载。

**Step 4: Run build to verify it passes**

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

Expected: PASS.

**Step 5: Commit**

```bash
git add ios/MingZhang/MingZhang/RootView.swift ios/MingZhang/MingZhang/LedgerStore.swift
git commit -m "feat: batch confirm imported bills"
```

## Task 11: 全量自动化验证与 P1 手动验收

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1ImportFlowTests.swift`
- Modify: `ios/MingZhang/MingZhang/RootView.swift`
- Modify: `ios/MingZhang/MingZhang/LedgerStore.swift`

**Step 1: Write the failing integration test**

新增一个端到端 Core 测试，串起支付宝和微信各一条候选、批量整理、确认入账、来源回溯。

```swift
func testP1AlipayWechatImportEndToEnd() throws {
    let database = try LedgerDatabase.inMemory()
    let useCases = LedgerUseCases(database: database)
    try useCases.initializeLedgerSeed()

    let alipay = try useCases.createImportBatch(source: .alipay, fileName: "alipay-minimal.csv", contents: fixture("alipay-minimal.csv"))
    let wechat = try useCases.createImportBatch(source: .wechat, fileName: "wechat-minimal.csv", contents: fixture("wechat-minimal.csv"))
    let ids = (alipay.candidates + wechat.candidates).map(\.id)

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
        try XCTUnwrap(Decimal(string: "120.50"))
    )
    XCTAssertEqual(try useCases.queryStatisticsSummary(accountMonth: "2026-04").sourceRecordIds.count, 2)
    XCTAssertNotNil(try useCases.getImportTrace(recordId: try XCTUnwrap(records.first?.id)))
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter P1ImportFlowTests/testP1AlipayWechatImportEndToEnd
```

Expected: FAIL until all preceding tasks are complete and decimal aggregation handles fixture values correctly.

**Step 3: Write minimal implementation**

Fix only integration gaps found by the test:

- Ensure result ordering is deterministic by `occurredAt ASC, createdAt ASC`。
- Ensure Decimal aggregation keeps `120.50` as Decimal value。
- Ensure trace query handles both sources。
- Ensure UI build compiles after final RootView and Store integration。

**Step 4: Run test suite and iOS build**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: PASS.

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

Expected: PASS.

**Step 5: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore ios/MingZhang/MingZhang/LedgerStore.swift ios/MingZhang/MingZhang/RootView.swift
git commit -m "test: verify p1 import flow"
```

## Suggested Automated Tests

- `P1ImportFlowTests/testImportSchemaStartsEmptyAndSeedsPendingRealAccount`
- `P1ImportFlowTests/testCreateImportBatchMapsAlipayAndWechatRowsToCandidates`
- `P1ImportFlowTests/testImportCandidatesDoNotAffectLedgerBeforeConfirmation`
- `P1ImportFlowTests/testUpdateAndBatchUpdateImportCandidatesDoNotChangeOccurredAt`
- `P1ImportFlowTests/testConfirmImportCandidatesCreatesImportRecordsAndRecalculates`
- `P1ImportFlowTests/testImportRecordCanTraceBackToBatchAndRawCandidate`
- `P1ImportFlowTests/testImportReportsInvalidAmountUnknownFieldsAndDuplicates`
- `P1ImportFlowTests/testImportSkipsNonRevenueExpenseTransactions`
- `P1ImportFlowTests/testP1AlipayWechatImportEndToEnd`
- Existing `P0LedgerFlowTests` full suite, to guard manual records, source filtering, engine upsert and stale cleanup.
- iOS simulator build with the existing `xcodebuild` command.

## Suggested Manual Acceptance Checklist

- 在流水页点击 `导入账单`，只看到 `支付宝账单`、`微信账单` 两个来源。
- 导入支付宝 CSV（GBK 编码）后正确跳过元数据头，出现候选列表；首页、资产负债、统计仍为导入前结果。
- 导入微信 CSV（UTF-8 BOM）后正确跳过元数据头、清洗 ¥ 前缀、跳过中性交易（零钱充值/信用卡还款等）。
- 导入微信 XLSX 后候选列表与同数据 CSV 导入结果一致。
- 单条候选可以修改账月、收付手段、收付类型、类型明细、备注；修改账月不改变实际时间。
- 多选候选后可以批量修改账月、收付手段、收付类型、类型明细；点击应用后候选仍未入账。
- 未补齐收付类型或类型明细时确认入账失败；收付手段可为 `待补真实账户`，允许确认后继续编辑。
- 确认入账后，流水列表出现 `导入` 来源记录；首页、资产负债、统计同步刷新。
- 从统计或资产负债来源回溯到导入流水后，流水详情能看到导入来源、文件名、原始 CSV 行号和交易单号。
- 重复导入同一账单时不重复生成候选或正式流水，并显示重复 issue。
- 非法金额、无法识别字段、不计收支/中性交易方向均不污染正式流水。

## Open Questions To Carry Forward

- `已确认`：支付宝 12 列真实字段：`交易时间`, `交易对方`(分类), `交易对方`(对方), `对方账号`, `商品说明`, `收/支`, `金额`, `收/付款方式`, `交易状态`, `交易订单号`, `商家订单号`, `备注`。编码 GBK，含 24 行元数据头，交易订单号与商户订单号间为 Tab 分隔。
- `已确认`：微信 11 列真实字段：`交易时间`, `交易类型`, `交易对方`, `商品`, `收/支`, `金额(元)`, `支付方式`, `当前状态`, `交易单号`, `商户单号`, `备注`。编码 UTF-8 BOM，含 16 行元数据头，金额带 ¥ 前缀。
- `已确认`：微信 XLSX 纳入 P1 支持范围，字段结构与 CSV 一致。
- `已确认`：去重主键为 `source + rawTransactionId`（支付宝=交易订单号，微信=交易单号）。无交易号时用 `source + rawFingerprint`，其中 `rawFingerprint = SHA256(occurredAt + amount + counterparty + productDescription).prefix(16)`。
- `已确认`：不计收支/中性交易不生成候选，按来源特定规则判断（支付宝判断 `收/支=不计收支`，微信判断 `交易类型` 匹配中性列表）。
- `已确认`：`待补真实账户` 允许直接确认入账，后续在流水中修改为真实收付手段。确认入账仅要求 `paymentTypeId`、`paymentDetailId` 非空。
- `已确认`：支付方式匹配需用模糊规则。真实数据中有 147 种不同支付方式表述，同一张卡可能以 `广发银行信用卡(4896)`、`广发银行信用卡(4896)&红包`、`广发银行信用卡(4896)&优惠` 等形式出现，且支付宝和微信对同一张卡的命名不同（如 支付宝`广发银行信用卡(4896)` vs 微信`广发银行(4896)`）。匹配策略：按银行名关键词（如”广发”）+ 卡号后四位（如”4896”）做模糊匹配，清理 `&红包`、`&优惠`、`&积分抵扣` 等后缀，清理 `信用卡`/`储蓄卡` 等类型词差异。
- `已确认`：微信中性交易类型通过前缀匹配。经汇总目录下所有微信 CSV 分析（49 种交易类型），实际中性类型为：`零钱提现`、`信用卡还款`、`转入零钱通-*`、`零钱通转出-*`。Plan 之前列出的 `零钱充值`、`理财通购买`、`理财通赎回` 在实际账单中不存在。
