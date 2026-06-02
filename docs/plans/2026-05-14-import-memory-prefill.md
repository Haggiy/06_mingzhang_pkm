# Import Memory Prefill Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在支付宝 / 微信导入候选生成时，若历史确认导入记录存在同来源、同商户、同商品且分类完全一致，则自动预填 `收付类型` 和 `类型明细`。

**Architecture:** 不做 ML、不做训练、不做置信度。导入解析阶段生成临时 `ImportMemoryKey(source, counterparty, product)`；创建新导入批次时，从已确认且仍存在的 `record_source = import` 流水记录中构建只读记忆索引。只有同一 key 的历史分类集合唯一时才预填候选记录；有冲突、无历史、商户或商品为空时保持空值，继续由用户手工确认或修改。

**Tech Stack:** Swift、Swift Package Manager、XCTest、GRDB、`MingZhangCore`。

---

## Scope

本计划只实现保守记忆预填，属于 P1 支付宝 / 微信导入整理的轻量增强。

必须保持的边界：

- 候选记录确认前不进入流水，不触发引擎。
- 预填只写入 `ImportCandidateRecord.paymentTypeId/paymentTypeName/paymentDetailId/paymentDetailName`。
- 正式入账仍必须经过 `confirmImportCandidates`。
- 训练来源只允许使用已确认且仍存在的导入流水当前分类，不使用未确认候选、ignored 候选、manual 记录、engine 记录。
- 如果用户确认后又编辑了导入流水分类，后续记忆应使用当前 `JournalRecord` 分类，而不是旧候选值。
- 不新增数据库表，不引入 ML/AI/LLM，不修改收付手段、备注、账月的推断逻辑。

## Relevant Files

- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`
- Test: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1ImportFlowTests.swift`
- Optional docs: `docs/plans/2026-05-12-import-ml-classification-design.md`

## Task 1: Add Failing Test For Consistent Import Memory

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1ImportFlowTests.swift`

**Step 1: Write the failing test**

Add this test near the other P1 import behavior tests:

```swift
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
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
swift test --filter P1ImportFlowTests/testImportMemoryPrefillsClassificationWhenSameSourceMerchantAndProductHistoryIsConsistent
```

Expected: FAIL because `secondCandidate.paymentTypeName` and `paymentDetailName` are currently `nil`.

**Step 3: Commit only if the test was observed failing**

Do not commit yet unless the team wants red commits. If committing red tests is acceptable:

```bash
git add ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1ImportFlowTests.swift
git commit -m "test: cover import memory prefill"
```

## Task 2: Add Transient Import Memory Key Extraction

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`

**Step 1: Add key structs near `ParsedImportRow`**

Add near `private struct ParsedImportRow`:

```swift
private struct ImportMemoryKey: Hashable {
    var source: ImportSource
    var counterparty: String
    var product: String
}

private struct ImportMemoryClassification: Hashable {
    var paymentTypeId: UUID
    var paymentTypeName: String
    var paymentDetailId: UUID
    var paymentDetailName: String
}
```

Update `ParsedImportRow`:

```swift
private struct ParsedImportRow {
    var lineNumber: Int
    var rawPayload: String
    var accountMonth: String
    var occurredAt: Date
    var paymentMethodName: String?
    var amount: Decimal
    var note: String?
    var rawTransactionId: String?
    var rawFingerprint: String
    var memoryKey: ImportMemoryKey?
}
```

**Step 2: Add key helper**

Add near the import parsing helpers:

```swift
private func makeImportMemoryKey(source: ImportSource, counterparty: String, product: String) -> ImportMemoryKey? {
    let cleanedCounterparty = cleanImportField(counterparty)
    let cleanedProduct = cleanImportField(product)
    guard !cleanedCounterparty.isEmpty, cleanedCounterparty != "/" else { return nil }
    guard !cleanedProduct.isEmpty, cleanedProduct != "/" else { return nil }
    return ImportMemoryKey(source: source, counterparty: cleanedCounterparty, product: cleanedProduct)
}

private func importMemoryKey(source: ImportSource, rawPayload: String) -> ImportMemoryKey? {
    let fields = parseCSVLine(rawPayload)
    switch source {
    case .alipay:
        guard fields.count >= 5 else { return nil }
        return makeImportMemoryKey(
            source: source,
            counterparty: fields[2],
            product: fields[4]
        )
    case .wechat:
        guard fields.count >= 4 else { return nil }
        return makeImportMemoryKey(
            source: source,
            counterparty: fields[2],
            product: fields[3]
        )
    }
}
```

**Step 3: Populate memory key in parsed rows**

In `parseAlipayLine`, include:

```swift
memoryKey: makeImportMemoryKey(source: .alipay, counterparty: counterparty, product: product)
```

In `parseWechatLine`, include:

```swift
memoryKey: makeImportMemoryKey(source: .wechat, counterparty: counterparty, product: product)
```

**Step 4: Run compile to catch initializer misses**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
swift test --filter P1ImportFlowTests/testImportMemoryPrefillsClassificationWhenSameSourceMerchantAndProductHistoryIsConsistent
```

Expected: still FAIL on assertion, not compile error.

## Task 3: Implement Memory Index And Candidate Prefill

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift`

**Step 1: Add memory index loader**

Add near other private database helpers:

```swift
private func loadImportMemoryIndex(_ db: Database, source: ImportSource) throws -> [ImportMemoryKey: ImportMemoryClassification] {
    let rows = try Row.fetchAll(db, sql: """
        SELECT
            import_candidates.raw_payload,
            journal_records.payment_type_id,
            payment_types.name AS payment_type_name,
            journal_records.payment_detail_id,
            payment_details.name AS payment_detail_name
        FROM import_candidates
        JOIN import_batches ON import_batches.id = import_candidates.batch_id
        JOIN journal_records ON journal_records.source_import_candidate_id = import_candidates.id
        JOIN payment_types ON payment_types.id = journal_records.payment_type_id
        JOIN payment_details ON payment_details.id = journal_records.payment_detail_id
        WHERE import_batches.source = ?
          AND import_candidates.status = ?
          AND journal_records.record_source = ?
        """, arguments: [
            source.rawValue,
            ImportCandidateStatus.confirmed.rawValue,
            RecordSource.import.rawValue
        ])

    var classificationsByKey: [ImportMemoryKey: Set<ImportMemoryClassification>] = [:]
    for row in rows {
        let rawPayload: String = row["raw_payload"]
        guard let key = importMemoryKey(source: source, rawPayload: rawPayload) else { continue }
        let classification = ImportMemoryClassification(
            paymentTypeId: try requireUUID(row["payment_type_id"]),
            paymentTypeName: row["payment_type_name"],
            paymentDetailId: try requireUUID(row["payment_detail_id"]),
            paymentDetailName: row["payment_detail_name"]
        )
        classificationsByKey[key, default: []].insert(classification)
    }

    return classificationsByKey.compactMapValues { classifications in
        classifications.count == 1 ? classifications.first : nil
    }
}
```

**Step 2: Load index once per batch**

Inside private `createImportBatch(source:fileName:parseResult:)`, after inserting `batch` and before looping rows:

```swift
let memoryIndex = try loadImportMemoryIndex(db, source: source)
```

**Step 3: Apply prefill while creating candidate**

Before creating `ImportCandidateRecord`:

```swift
let memory = row.memoryKey.flatMap { memoryIndex[$0] }
```

Then set candidate classification fields:

```swift
paymentTypeId: memory?.paymentTypeId,
paymentTypeName: memory?.paymentTypeName,
paymentDetailId: memory?.paymentDetailId,
paymentDetailName: memory?.paymentDetailName,
```

Keep all other fields unchanged.

**Step 4: Run the focused test**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
swift test --filter P1ImportFlowTests/testImportMemoryPrefillsClassificationWhenSameSourceMerchantAndProductHistoryIsConsistent
```

Expected: PASS.

**Step 5: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1ImportFlowTests.swift
git commit -m "feat: prefill import classification from memory"
```

## Task 4: Add Conflict Test

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1ImportFlowTests.swift`

**Step 1: Add GRDB import if the helper uses raw SQL**

At the top:

```swift
import GRDB
```

**Step 2: Add test-only seed helper**

Add near the existing test helpers:

```swift
private func insertPaymentTypeAndDetailForTest(
    database: LedgerDatabase,
    typeName: String,
    detailName: String
) throws {
    try database.writer.write { db in
        let now = ISO8601DateFormatter().string(from: Date())
        let typeId = UUID().uuidString
        let detailId = UUID().uuidString
        try db.execute(sql: """
            INSERT INTO payment_types (id, name, element, is_active, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: [typeId, typeName, AccountingElement.expense.rawValue, true, now, now])
        try db.execute(sql: """
            INSERT INTO payment_details (id, name, payment_type_id, is_active, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: [detailId, detailName, typeId, true, now, now])
    }
}
```

**Step 3: Write failing conflict test**

```swift
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
```

**Step 4: Run test to verify it passes**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
swift test --filter P1ImportFlowTests/testImportMemoryLeavesClassificationEmptyWhenSameSourceMerchantAndProductHistoryConflicts
```

Expected: PASS. If it fails by pre-filling, fix `loadImportMemoryIndex` so conflicting key buckets are omitted.

**Step 5: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1ImportFlowTests.swift ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift
git commit -m "test: keep conflicting import memory empty"
```

## Task 5: Add Current-Record Classification Test

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1ImportFlowTests.swift`

**Step 1: Write failing test for edited import record**

Use the test helper from Task 4. Add:

```swift
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
```

**Step 2: Run focused test**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
swift test --filter P1ImportFlowTests/testImportMemoryUsesCurrentImportedJournalClassificationAfterEdit
```

Expected: PASS. If it fails by returning the original candidate classification, ensure the memory SQL reads from `journal_records`, not `import_candidates`.

**Step 3: Commit**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1ImportFlowTests.swift ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift
git commit -m "test: import memory follows edited journal classification"
```

## Task 6: Document The MVP Scope Decision

**Files:**
- Modify: `docs/plans/2026-05-12-import-ml-classification-design.md`

**Step 1: Inspect current user edits**

Run:

```bash
git diff -- docs/plans/2026-05-12-import-ml-classification-design.md
```

Do not overwrite unrelated edits.

**Step 2: Add a short execution decision section near the top**

Add below the document metadata:

```markdown
> 执行裁剪（2026-05-14）：v1.0 / MVP 不执行完整 ML 分类。当前只实现保守记忆预填：同来源、同商户、同商品且历史确认分类完全一致时，预填 `收付类型` 和 `类型明细`；冲突或无历史时留空。逻辑回归、实时训练、置信度阈值和 LLM 链路保留为后续实验方案，不作为 MVP 验收条件。
```

**Step 3: Commit docs**

```bash
git add docs/plans/2026-05-12-import-ml-classification-design.md
git commit -m "docs: scope import intelligence to memory prefill"
```

## Task 7: Final Verification

**Files:**
- Verify only.

**Step 1: Run focused P1 import tests**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
swift test --filter P1ImportFlowTests
```

Expected: all `P1ImportFlowTests` pass.

**Step 2: Run full core test suite**

Run:

```bash
cd ios/MingZhang/Packages/MingZhangCore
swift test
```

Expected: full package test suite passes.

**Step 3: Review diff**

Run:

```bash
git diff --stat
git diff -- ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1ImportFlowTests.swift docs/plans/2026-05-12-import-ml-classification-design.md
```

Expected:

- No ML model, training, confidence, LLM, or new settings UI.
- No new database table.
- Candidate prefill only happens when memory key maps to exactly one classification.
- Existing import confirmation and trace behavior remains unchanged.

**Step 4: Final commit if earlier tasks were not committed**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P1ImportFlowTests.swift docs/plans/2026-05-12-import-ml-classification-design.md
git commit -m "feat: add conservative import memory prefill"
```
