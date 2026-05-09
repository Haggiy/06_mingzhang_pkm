# 新明账 iOS 本地数据模型与引擎接口设计

> 文档分类：Spec / 本地数据与领域服务
> 状态：开发输入草案
> 日期：2026-05-09
> 范围：定义 v1.0 本地数据对象、字段、Use Case、引擎输入输出、读模型和 P0 纵向切片接口。
> 不展开：具体 SwiftData / SQLite 代码、云同步、账号系统、多端冲突、UI 页面实现。

## 0. 证据来源

`事实`

本文只承接当前 PRD、Spec 和已确认页面规格，不新增产品方向。

| 证据编号 | 来源 | 用途 |
| --- | --- | --- |
| `PRD` | `docs/prd/mvp-prd.md` | MVP 范围、五个一级入口、已确认边界口径 |
| `MATRIX` | `docs/prd/2026-05-09-v1-feature-acceptance-matrix.md` | 功能优先级、验收矩阵、P0 纵向切片 |
| `PAGE` | `docs/specs/2026-05-09-ios-page-field-state-spec.md` | 页面字段、状态、页面到验收场景映射 |
| `MONTH` | `docs/specs/record-and-month-spec.md` | 账月、时间、流水字段、来源、继承 |
| `ENGINE` | `docs/specs/stock-flow-engine-spec.md` | 存量-流量闭环、账户家族、引擎 key、重算边界 |
| `SETTINGS` | `docs/specs/settings-and-semantics-spec.md` | 收付手段、收付类型、类型明细、语义标签 |
| `IMPORT` | `docs/specs/import-alipay-wechat-spec.md` | 支付宝 / 微信导入候选和确认入账 |
| `INVEST` | `docs/specs/investment-ledger-spec.md` | 基金投资明细、平均成本法、回填流水 |

## 1. 设计原则

`事实`

- `流水日记账` 是唯一最终入账和计算真源。
- 首页、资产负债、结果视图都不是独立真源；页面图稿中的 `统计` 等同于 PRD 中的 `结果视图`。
- 投资明细账可以计算投资结果，但买入、卖出、收益、亏损最终必须回填流水。
- 当前不引入账月状态、结账状态、锁账状态。
- v1.0 投资资产先做 `总投资资产`。
- v1.0 递延资产对象先用 `备注` 识别。
- v1.0 现金池先合并。
- v1.0 负债对象先按收付手段聚合。
- v1.0 `收付手段=0` 先作为 `待补真实账户` 处理。

`推断`

本地数据模型应满足：

- 前端只通过 Use Case 写入，不直接拼账务规则。
- 引擎只从真源记录和必要配置解释结果，不承担 UI 状态。
- engine 记录参与计算，但不触发引擎。
- 所有结果读模型都能回溯到流水记录或投资明细记录。
- v1.0 默认纯本地 App，不预设云端 schema。

## 2. 本地存储选型口径

`推断`

v1.0 可优先按本地结构化存储设计，具体实现可在 SwiftData 和 SQLite 之间选择：

| 选项 | 优点 | 风险 | 适用判断 |
| --- | --- | --- | --- |
| SwiftData | 与 SwiftUI 集成顺，开发速度快 | 复杂迁移、批量重算、审计导出可控性需要验证 | 适合 P0 原型和轻量本地账本 |
| SQLite | 查询、迁移、导出、批量重算更可控 | 需要自行封装数据访问层 | 适合长期账本和可审计数据 |

`推断`

无论底层选型如何，领域对象和 Use Case 边界应保持一致。本文先定义领域模型，不绑定具体存储框架。

## 3. 核心枚举

`推断`

### 3.1 记录来源

| 字段值 | 含义 | 是否真源 | 是否触发引擎 | 编辑入口 |
| --- | --- | --- | --- | --- |
| `manual` | 手工新增或补录 | 是 | 是 | 流水详情 |
| `import` | 支付宝 / 微信导入确认 | 是 | 是 | 流水详情 |
| `investment_feed` | 投资明细账回填 | 是 | 是 | 投资明细账 |
| `engine` | 引擎生成骨架行 | 否 | 否 | 修改来源后重算 |

### 3.2 记录性质

| 字段值 | 含义 |
| --- | --- |
| `normal` | 普通记录 |
| `carry_forward` | 跨月继承行 |

### 3.3 继承用途

| 字段值 | 含义 |
| --- | --- |
| `accounting_skeleton` | 复式骨架 |
| `recurring_record` | 周期重复记录 |
| `none` | 非继承行 |

### 3.4 收付手段类型

| 字段值 | 含义 |
| --- | --- |
| `asset` | 资产型 |
| `liability` | 负债型 |
| `accounting` | 账务处理型 |
| `pending_real_account` | 待补真实账户 |

`事实`

`pending_real_account` 来自 2026-05-09 用户确认：v1.0 先将 `收付手段=0` 作为 `待补真实账户`。

### 3.5 引擎账户家族

| 字段值 | 含义 | v1.0 对象 key |
| --- | --- | --- |
| `cash` | 现金类资产 | `cash_pool:电子钱包余额` |
| `liability` | 负债 | `liability:{收付手段名称}` |
| `deferred` | 递延资产 | `deferred:{稳定备注}` |
| `investment` | 投资资产 | `investment:总投资资产` |

## 4. 核心数据对象

### 4.1 `JournalRecord` 流水记录

`事实`

用户可见最小字段为：`账月`、`时间`、`收付手段`、`金额`、`收付类型`、`类型明细`、`备注`。

`推断`

| 字段 | 类型 | 必填 | 用户可见 | 编辑规则 |
| --- | --- | --- | --- | --- |
| `id` | UUID | 是 | 否 | 创建后不变 |
| `accountMonth` | String `YYYY-MM` | 是 | 是 | 可编辑；决定账月归属 |
| `occurredAt` | DateTime | 是 | 是 | 精确到秒；不决定账月归属 |
| `paymentMethodId` | UUID | 是 | 是 | 指向 `PaymentMethod` |
| `amount` | Decimal | 是 | 是 | 当前科目的带符号发生额 |
| `paymentTypeId` | UUID | 是 | 是 | 指向 `PaymentType` |
| `paymentDetailId` | UUID | 是 | 是 | 指向 `PaymentDetail` |
| `note` | String | 否 | 是 | v1.0 递延对象可先用稳定备注识别 |
| `recordSource` | Enum | 是 | 只读展示 | `manual / import / investment_feed / engine` |
| `recordKind` | Enum | 是 | 轻量展示 | `normal / carry_forward` |
| `carryForwardRole` | Enum | 否 | 轻量展示 | 非继承行可为 `none` |
| `engineFamily` | Enum | 否 | 否 | engine 记录或相关骨架使用 |
| `engineKey` | String | 否 | 否 | engine 记录覆盖 key |
| `objectKey` | String | 否 | 否 | 资产、负债、递延、投资对象标识 |
| `sourceImportBatchId` | UUID | 否 | 否 | 导入追溯 |
| `sourceInvestmentEntryId` | UUID | 否 | 否 | 投资回填追溯 |
| `createdAt` | DateTime | 是 | 否 | 审计 |
| `updatedAt` | DateTime | 是 | 否 | 审计 |

编辑边界：

| 来源 | 流水中能否编辑 | 删除规则 |
| --- | --- | --- |
| `manual` | 可编辑 | 可删除，需确认 |
| `import` | 可编辑 | 可删除，需确认 |
| `investment_feed` | 只读 | 回投资明细修改 |
| `engine` | 只读 | 修改来源后重算 |

### 4.2 `PaymentMethod` 收付手段

`事实`

收付手段最小属性为：资产型、负债型、账务处理型。

`推断`

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | UUID | 是 | 主键 |
| `name` | String | 是 | 例如 `广发卡`、`电子钱包余额` |
| `methodType` | Enum | 是 | `asset / liability / accounting / pending_real_account` |
| `isActive` | Bool | 是 | 停用不破坏历史记录 |
| `semanticTags` | [String] | 否 | 例如 `负债型`、`资产型` |
| `createdAt` | DateTime | 是 | 审计 |
| `updatedAt` | DateTime | 是 | 审计 |

### 4.3 `PaymentType` 收付类型

`事实`

收付类型是当前用户字段，属于三级科目中的 L2。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | UUID | 是 | 主键 |
| `name` | String | 是 | 例如 `生活必要开支` |
| `element` | Enum | 是 | `asset / liability / income / expense` |
| `isActive` | Bool | 是 | 停用不破坏历史记录 |
| `semanticTags` | [String] | 否 | 内部语义标签 |
| `description` | String | 否 | 自然语言语义描述 |

### 4.4 `PaymentDetail` 类型明细

`事实`

类型明细必须唯一归属于一个收付类型，不跨收付类型复用。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | UUID | 是 | 主键 |
| `name` | String | 是 | 例如 `伙食费` |
| `paymentTypeId` | UUID | 是 | 所属收付类型 |
| `isActive` | Bool | 是 | 停用不破坏历史记录 |
| `semanticTags` | [String] | 否 | 例如 `递延资产`、`已实现投资亏损` |
| `description` | String | 否 | 自然语言语义描述 |

### 4.5 `ImportBatch` 导入批次

`推断`

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | UUID | 是 | 主键 |
| `source` | Enum | 是 | `alipay / wechat` |
| `fileName` | String | 否 | 原始文件名 |
| `importedAt` | DateTime | 是 | 导入时间 |
| `status` | Enum | 是 | `draft / confirmed / failed` |
| `confirmedRecordCount` | Int | 是 | 已入账记录数 |

### 4.6 `ImportCandidateRecord` 导入候选记录

`推断`

候选记录不是正式流水；只有确认后才生成 `JournalRecord(recordSource = import)`。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | UUID | 是 | 主键 |
| `batchId` | UUID | 是 | 所属导入批次 |
| `status` | Enum | 是 | `pending / ignored / confirmed` |
| `accountMonth` | String | 是 | 默认按实际时间预填，可改 |
| `occurredAt` | DateTime | 是 | 原始时间，保留到秒 |
| `paymentMethodId` | UUID | 否 | 可先为待补真实账户 |
| `amount` | Decimal | 是 | 候选金额 |
| `paymentTypeId` | UUID | 否 | 用户补充 |
| `paymentDetailId` | UUID | 否 | 用户补充 |
| `note` | String | 否 | 原始说明整理而来 |
| `rawPayload` | String / JSON | 否 | 后续分析导入文件后确定 |
| `createdJournalRecordId` | UUID | 否 | 确认后关联流水 |

`待确认 / 后续分析`

支付宝、微信原始字段名和交易号保留规则后续根据导入文件样例细化。

### 4.7 `InvestmentEntry` 基金投资明细

`事实`

第一版投资能力只做基金；用户维护交易事实，计算字段由系统生成。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | UUID | 是 | 主键 |
| `occurredAt` | DateTime | 是 | 日期或时间 |
| `accountMonth` | String | 是 | 用于按账月回填 |
| `fundName` | String | 是 | 标的名称 |
| `entryType` | Enum | 是 | `buy / sell / nav` |
| `tradeAmount` | Decimal | 条件 | 买入 / 卖出的交易金额 |
| `tradeShare` | Decimal | 条件 | 买入 / 卖出的交易份额 |
| `nav` | Decimal | 条件 | 净值记录或可选展示 |
| `note` | String | 否 | 备注 |
| `bookAmount` | Decimal | 否 | 入账金额，系统计算 |
| `realizedGain` | Decimal | 否 | 已实现收益，系统计算 |
| `realizedLoss` | Decimal | 否 | 已实现亏损，系统计算 |
| `holdingShare` | Decimal | 否 | 持有份额，系统计算 |
| `bookValue` | Decimal | 否 | BV，系统计算 |
| `presentValue` | Decimal | 否 | PV，系统计算 |

### 4.8 `BackupManifest` 备份元数据

`推断`

`BackupManifest` 只描述备份文件元数据，不等同于完整备份恢复流程。具体文件格式后续细化，但 v1.0 需要先保证导出、备份、校验、恢复的 Use Case 边界。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `schemaVersion` | String | 是 | 备份格式版本 |
| `exportedAt` | DateTime | 是 | 导出时间 |
| `appVersion` | String | 否 | App 版本 |
| `recordCount` | Int | 是 | 主要记录数量 |
| `checksum` | String | 是 | 完整性校验 |

`待确认 / 后续细化`

备份文件格式、schema version、恢复策略在数据导出 / 备份 / 恢复规格中继续细化。

## 5. 最小读模型

`推断`

读模型可以由本地服务即时计算或缓存，但对前端暴露为只读查询结果。

| 读模型 | 用途 | 输入 |
| --- | --- | --- |
| `JournalListViewModel` | 流水列表、搜索、筛选 | `JournalRecord` + 配置对象 |
| `HomeSummaryViewModel` | 首页摘要 | 流水 + 引擎结果 |
| `BalanceSummaryViewModel` | 资产负债首页 | 流水 + 引擎结果 + 投资估值 |
| `LiabilityDetailViewModel` | 负债详情 | 负债对象相关流水 |
| `StatisticsSummaryViewModel` | 统计首页 | 流水 + 投资明细 |
| `CategoryDetailViewModel` | 分类详情 | 指定分类相关流水 |
| `InvestmentResultViewModel` | 投资结果详情 | 投资明细 + 回填流水 |

读模型统一要求：

- 能提供来源记录 id 列表。
- 不直接修改真源。
- 不把统计修正写回自身。

## 6. Use Case 清单

`推断`

### 6.1 流水 Use Case

| Use Case | 输入 | 输出 | 是否触发引擎 |
| --- | --- | --- | --- |
| `CreateManualRecord` | 用户填写的流水字段 | `JournalRecord` | 是 |
| `UpdateJournalRecord` | record id + 修改字段 | 更新后的 `JournalRecord` | 是，若真源 |
| `DeleteJournalRecord` | record id | 删除结果 | 是，若真源 |
| `QueryJournalRecords` | 账月范围 + 筛选条件 | 记录列表 | 否 |
| `GetJournalRecordDetail` | record id | 记录详情 | 否 |

### 6.2 导入 Use Case

| Use Case | 输入 | 输出 | 是否触发引擎 |
| --- | --- | --- | --- |
| `CreateImportBatch` | 来源 + 文件 | `ImportBatch` + 候选记录 | 否 |
| `UpdateImportCandidate` | candidate id + 修改字段 | 候选记录 | 否 |
| `BatchUpdateImportCandidates` | ids + 批量字段 | 候选记录列表 | 否 |
| `ConfirmImportCandidates` | candidate ids | 生成的 `JournalRecord` | 是 |
| `IgnoreImportCandidates` | candidate ids | 忽略结果 | 否 |

### 6.3 设置 Use Case

| Use Case | 输入 | 输出 | 是否触发引擎 |
| --- | --- | --- | --- |
| `CreatePaymentMethod` | 名称 + 类型 | `PaymentMethod` | 否 |
| `UpdatePaymentMethod` | id + 字段 | `PaymentMethod` | 可能触发受影响记录重算 |
| `DeactivatePaymentMethod` | id | 停用结果 | 否 |
| `CreatePaymentType` | 名称 + element | `PaymentType` | 否 |
| `UpdatePaymentType` | id + 字段 | `PaymentType` | 可能触发重算 |
| `CreatePaymentDetail` | 名称 + 所属类型 | `PaymentDetail` | 否 |
| `UpdatePaymentDetail` | id + 字段 | `PaymentDetail` | 可能触发重算 |
| `DeactivatePaymentDetail` | id | 停用结果 | 否 |

### 6.4 投资 Use Case

| Use Case | 输入 | 输出 | 是否触发引擎 |
| --- | --- | --- | --- |
| `CreateInvestmentEntry` | 交易事实或净值记录 | `InvestmentEntry` | 是，若产生回填 |
| `UpdateInvestmentEntry` | id + 字段 | `InvestmentEntry` | 是，若影响回填 |
| `DeleteInvestmentEntry` | id | 删除结果 | 是，若影响回填 |
| `RecalculateInvestmentLedger` | 标的 + 账月范围 | 投资计算结果 | 是，覆盖回填 |

### 6.5 资产负债操作 Use Case

| Use Case | 输入 | 输出 | 是否触发引擎 |
| --- | --- | --- | --- |
| `AdjustAssetBalance` | 账户 + 当前余额 + 时间 | 生成的调整流水 | 是 |
| `CreateLiabilityRepayment` | 负债对象 + 金额 + 支付手段 + 时间 | 还款流水 | 是 |
| `CreateLiabilityCost` | 负债对象 + 金额 + 时间 + 备注 | 利息 / 费用流水 | 是 |

`事实`

调整余额、还款、补利息最终都必须生成流水记录，不直接改资产或负债余额。

### 6.6 数据管理 Use Case

`推断`

| Use Case | 输入 | 输出 | 是否触发引擎 |
| --- | --- | --- | --- |
| `ExportAuditData` | 导出范围 + 格式选项 | 可人工审计的导出文件 | 否 |
| `CreateBackupPackage` | 当前本地账本 | 备份文件 + `BackupManifest` | 否 |
| `ValidateBackupPackage` | 备份文件 | 校验结果 + `BackupManifest` | 否 |
| `RestoreBackupPackage` | 已校验备份文件 + 用户确认 | 恢复结果 | 否，恢复完成后按需重建读模型 |

恢复规则：

- 恢复前必须校验 `schemaVersion`、记录数量和 `checksum`。
- 校验失败时禁止恢复。
- 恢复过程应先在临时区解析和校验，成功后再替换当前账本数据。
- 恢复失败不得污染当前本机账本。
- 这里的恢复只指新明账自己的备份文件，不指支付宝 / 微信账单导入。

## 7. 引擎接口

### 7.1 触发入口

`推断`

```text
recalculateAfterMutation(mutation)
```

输入：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `mutationType` | Enum | `create / update / delete / investment_reflow / config_change` |
| `affectedRecordIds` | [UUID] | 受影响流水 |
| `affectedInvestmentEntryIds` | [UUID] | 受影响投资明细 |
| `startingAccountMonth` | String | 重算起点账月 |
| `affectedFamilies` | [EngineFamily] | 可为空；为空时由系统识别 |

输出：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `recalculatedMonths` | [String] | 已重算账月 |
| `createdEngineRecordIds` | [UUID] | 新建 engine 记录 |
| `updatedEngineRecordIds` | [UUID] | 覆盖更新 engine 记录 |
| `deletedEngineRecordIds` | [UUID] | 被清理 engine 记录 |
| `warnings` | [String] | 非阻塞警告 |

### 7.2 账月重算接口

`推断`

```text
recalculateAccountMonth(accountMonth, families)
```

规则：

- 每次按 `账月 + 账户家族` 重算。
- 人工真源记录不动。
- 导入确认后的真源记录不动。
- 投资回填记录由投资回填规则覆盖。
- 同账户家族旧 engine 记录按 key 覆盖或删除后重建。
- 输入归零且不存在未完对象时，删除对应 engine 记录。
- engine 记录参与计算，但不再次触发引擎。

### 7.3 跨月传播接口

`推断`

```text
propagateFrom(startingAccountMonth, families)
```

传播继续条件：

- 后续账月存在期初存量。
- 后续账月存在本月发生。
- 存在未释放递延对象。
- 存在未清负债。
- 存在投资承接或待回填。

传播停止条件：

- 后续账月无期初存量。
- 无本月发生。
- 无待释放、待偿还、待回填对象。

### 7.4 engine key

`事实`

engine 骨架行必须可覆盖重算，不能每次触发都追加。

`推断`

最小 key：

```text
accountMonth + engineFamily + skeletonType + objectKey
```

示例：

| 场景 | engine key |
| --- | --- |
| 2026-04 广发卡负债余额 | `2026-04:liability:ending_balance:liability:广发卡` |
| 2026-04 电子钱包余额 | `2026-04:cash:ending_balance:cash_pool:电子钱包余额` |
| 2026-04 健身房递延释放 | `2026-04:deferred:release:deferred:12个月健身房费用(202601-202612)` |
| 2026-04 总投资资产 | `2026-04:investment:ending_balance:investment:总投资资产` |

## 8. P0 纵向切片数据流

`事实 / 样例`

输入：

```text
账月：2026-04
时间：2026-04-15 12:30:00
收付手段：广发卡
金额：100
收付类型：生活必要开支
类型明细：伙食费
备注：午餐
record_source：manual
```

`推断`

处理链路：

```text
CreateManualRecord
-> 保存 JournalRecord
-> recalculateAfterMutation(startingAccountMonth = 2026-04, affectedFamilies = [liability])
-> 负债家族识别 广发卡 为 liability object
-> 生成或更新广发卡负债结果
-> 更新首页 / 资产负债 / 统计读模型
```

验收输出：

| 位置 | 预期 |
| --- | --- |
| 流水 | 出现该手工记录 |
| 首页 | 支出增加 100 |
| 资产负债 | 广发卡负债增加 100 |
| 统计 | 生活必要开支增加 100 |
| 现金类资产 | 不减少 |
| 回溯 | 首页、资产负债、统计结果可回到该流水 |

修改金额为 `120` 后，以上结果同步变为 `120`。删除记录后，以上影响消失。

## 9. 验收场景覆盖

`推断`

| 验收场景 | 主要对象 / Use Case |
| --- | --- |
| `A-01` 首页查看 | `HomeSummaryViewModel`、`QueryJournalRecords` |
| `A-02` 手工新增 | `CreateManualRecord`、`JournalRecord` |
| `A-03` 支付宝导入 | `ImportBatch`、`ImportCandidateRecord`、`ConfirmImportCandidates` |
| `A-04` 微信导入 | 同支付宝导入 |
| `A-05` 信用消费形成负债 | `JournalRecord`、`recalculateAfterMutation`、`liability` 家族 |
| `A-06` 信用卡还款 | `CreateLiabilityRepayment` 或手工流水 + `liability / cash` 家族 |
| `A-07` 负债总览 | `BalanceSummaryViewModel`、`LiabilityDetailViewModel` |
| `A-08` 基金卖出回填 | `InvestmentEntry`、`RecalculateInvestmentLedger`、`investment_feed` |
| `A-09` 预付费用递延 | `JournalRecord`、`deferred` 家族、`objectKey = deferred:{备注}` |
| `A-10` 结果回溯 | 各读模型返回来源记录 id |
| `A-11` 设置维护 | `PaymentMethod`、`PaymentType`、`PaymentDetail` |
| `A-12` 导出备份恢复 | `BackupManifest`、`ExportAuditData`、`CreateBackupPackage`、`ValidateBackupPackage`、`RestoreBackupPackage` |

## 10. 不进入 v1.0 数据模型的对象

`事实`

以下能力不进入 v1.0，不应提前建模：

- 账月状态、结账、锁账。
- 账号系统、云同步、多端冲突。
- 预算、预测。
- 通用借贷分录。
- 银行 / 信用卡导入。
- 用户自定义导入字段映射。
- 非基金投资品类。
- 实时行情。
- AI / Agent 自动操作配置。

## 11. 后续细化项

`待确认 / 后续细化`

| 编号 | 问题 | 后续处理位置 |
| --- | --- | --- |
| `D-01` | SwiftData 还是 SQLite | iOS 工程基础阶段做技术选型说明 |
| `D-02` | 支付宝 / 微信原始字段与交易号保留规则 | 导入文件样例分析 |
| `D-03` | 备份文件格式、schema version、恢复策略 | 数据导出 / 备份 / 恢复规格 |
| `D-04` | `待补真实账户` 的入账校验和补齐入口 | 导入整理与页面交互细化 |
| `D-05` | 哪些配置修改需要触发历史重算 | 引擎测试样例与配置迁移规则 |
| `D-06` | engine 记录的骨架类型枚举 | 引擎规则清单 |
