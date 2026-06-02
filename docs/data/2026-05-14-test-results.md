# MingZhangCore 测试运行结果

**运行日期**: 2026-05-14
**测试套件**: MingZhangCoreTests (Swift Package Manager)
**运行平台**: `swift test --package-path .../Packages/MingZhangCore` (macOS arm64, Xcode 26.5 / Swift 6.3.2)
**目标平台**: arm64e-apple-macos14.0

## 结果概览

| 测试套件 | 测试数量 | 通过 | 失败 | 耗时 |
|----------|---------|------|------|------|
| P0LedgerFlowTests | 13 | 13 | 0 | 0.311s |
| P1ImportFlowTests | 23 | 23 | 0 | 0.416s |
| **合计** | **36** | **36** | **0** | **0.730s** |

**结论**: 全部 36 个测试通过，零失败。

## P0LedgerFlowTests (13/13 通过)

核心账务流程测试 - 覆盖复式记账引擎、流水 CRUD、余额和统计汇总。

| 测试名称 | 状态 | 说明 |
|----------|------|------|
| testInitializeSeedIsIdempotent | 通过 | 种子数据初始化幂等 |
| testQueryAccountMonthsReturnsDistinctMonthsDescending | 通过 | 账月倒序查询 |
| testQueryJournalRecordsSupportsVisibleFieldFilters | 通过 | 多字段过滤 |
| testQueryJournalRecordsSupportsKeywordSearch | 通过 | 关键词搜索(收付手段/金额/备注) |
| testCreditCardExpenseCreatesLiabilityAndRecalculates | 通过 | 信用卡支出创建负债引擎记录 |
| testCashExpenseReducesCashAssetAndRecalculates | 通过 | 现金支出创建现金池引擎记录 |
| testEngineRecordDoesNotTriggerEngineAgain | 通过 | 引擎记录不触发二次计算 |
| testEngineRecalculationUpsertsExistingKeyWithoutDuplicates | 通过 | 重算 upsert 不产生重复 |
| testEngineRecalculationDeletesStaleKeyWhenFamilyChanges | 通过 | 收付手段变更时清理旧引擎记录 |
| testEngineRecalculationAggregatesMultipleSourcesAndDeletesEmptyKey | 通过 | 多源聚合与空键清理 |
| testValidationRejectsInvalidManualRecordInputs | 通过 | 非法输入校验(账月格式/类型明细归属) |
| testZeroAmountManualRecordsCanBeCreatedAndUpdated | 通过 | 零金额记录的创建和更新 |
| testEngineAndInvestmentFeedRecordsAreNotEditableOrDeletable | 通过 | 引擎和投资流水只读保护 |

## P1ImportFlowTests (23/23 通过)

导入流程测试 - 覆盖支付宝/微信 CSV/XLSX 导入、候选确认、分类记忆、重复检测。

| 测试名称 | 状态 | 说明 |
|----------|------|------|
| testImportSchemaStartsEmptyAndSeedsPendingRealAccount | 通过 | 导入 schema 初始为空且包含待补真实账户种子 |
| testCreateImportBatchMapsAlipayAndWechatRowsToCandidates | 通过 | 支付宝/微信 CSV 行映射为候选 |
| testCreateImportBatchMapsWechatXLSXRowsToCandidates | 通过 | 微信 XLSX 行映射 |
| testCreateImportBatchMapsAlipayXLSXRowsToCandidates | 通过 | 支付宝 XLSX 行映射 |
| testImportCandidatesDoNotAffectLedgerBeforeConfirmation | 通过 | 确认前候选不影响账本 |
| testUpdateAndBatchUpdateImportCandidatesDoNotChangeOccurredAt | 通过 | 更新候选不改变交易时间 |
| testConfirmImportCandidatesCreatesImportRecordsAndRecalculates | 通过 | 确认候选创建流水并重算 |
| testConfirmImportCandidatePreservesSignedAmountSemantics | 通过 | 带符号金额确认 |
| testImportMemoryPrefillsClassificationWhenSameSourceMerchantAndProductHistoryIsConsistent | 通过 | 商家-商品一致时预填分类 |
| testImportMemoryLeavesClassificationEmptyWhenSameSourceMerchantAndProductHistoryConflicts | 通过 | 历史分类冲突时留空 |
| testImportMemoryUsesCurrentImportedJournalClassificationAfterEdit | 通过 | 编辑后的分类用于后续记忆 |
| testImportMemoryLeavesClassificationEmpty当MerchantMatchesButProductDiffers | 通过 | 商品不同时不留记忆 |
| testImportMemoryLeavesClassificationEmpty当ProductMatchesButMerchantDiffers | 通过 | 商家不同时不留记忆 |
| testImportMemoryDoesNotPrefillAcrossAlipayAndWechatSources | 通过 | 支付宝和微信不跨源预填 |
| testImportMemoryLeavesClassificationEmpty当MerchantOrProductIsBlankOrSlash | 通过 | 空白/斜杠商家或商品不留记忆 |
| testImportMemoryDoesNotUseDeletedImportedJournalRecord | 通过 | 已删除流水不参与记忆 |
| testImportRecordCanTraceBackToBatchAndRawCandidate | 通过 | 流水可追溯到批次和原始候选 |
| testImportReportsInvalidAmountUnknownFieldsAndDuplicates | 通过 | 非法金额/未知字段/重复上报 |
| testRowsWithoutTransactionIdUseFullRawPayloadFingerprint | 通过 | 无交易号行用完整 payload 指纹 |
| testZeroAndNullAmountsStillCreateImportCandidates | 通过 | 零金额/null 金额仍创建候选 |
| testDeleteImportedRecordAllowsSameRawLineToBeImportedAgain | 通过 | 删除后同条原始行可再次导入 |
| testImportCreatesCandidatesForAllRevenueAndNeutralRows | 通过 | 收入和中性交易也创建候选 |
| testP1AlipayWechatImportEndToEnd | 通过 | 支付宝/微信导入端到端 |

## 备注

- 当前项目仅有 MingZhangCore Swift Package 中的单元测试，尚无独立的 UI 测试 target (XCUITest)
- 测试通过 macOS 目标运行（包声明支持 `.macOS(.v15)` 和 `.iOS(.v18)`）
- 测试运行依赖 Xcode.app (26.5, Swift 6.3.2)，而非 Command Line Tools (Swift 6.2.3)
- 构建依赖: GRDB.swift 7.10.0, CoreXLSX 0.14.2, XMLCoder 0.14.0, ZIPFoundation 0.9.20
