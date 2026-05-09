# AGENTS.md / CLAUDE.md

本文件用于约束 Claude Code / Codex 在本仓库中的协作方式。`AGENTS.md` 与 `CLAUDE.md` 应保持同步；修改其中一个时，必须同步检查另一个。

## 项目概述

`06_mingzhang_pkm` 是「明账（iOS App）」的产品与领域知识仓库。

明账是一款面向个人真实记账习惯的复式记账 iOS App。它的目标不是做通用财务软件，而是把用户已经在 Excel 中稳定运行的账月、流水、收付手段、资产负债、投资明细和结果汇总流程，复刻到手机端，并用更严格的内部语义保证每个结果都能追溯到来源流水或投资明细。

项目已经从真实 Excel 记账实践梳理，推进到 iOS MVP 产品设计与开发输入准备阶段。

当前核心任务是：以 Excel / CSV / XLSX 样例和已确认文档为事实源，沉淀复式记账领域规则、MVP 范围、关键页面结构、验收场景与后续 iOS 开发可消费的规格输入。不做脱离当前证据的产品扩展或技术架构预设。

## 仓库定位与阶段范围

当前主要做以下工作：

1. 梳理账月流程、字段语义、分类体系、固定行、摊销、结转、补记、汇总和导入整理规则。
2. 沉淀 `事实 / 推断 / 待确认` 三类结论。
3. 维护 MVP 产品范围、明确不做范围和关键验收场景。
4. 把关键页面低保真、页面职责、导航关系和主路径转成 iOS 开发可消费的规格。
5. 拆解 v1.0 开发输入，包括数据模型草案、领域服务边界、引擎规则清单、验收矩阵和待确认问题。

当前明确不做：不扩展成大而全财务产品，不抢先加入预算、预测、复杂看板、AI / Agent、多端协同、账号体系、云同步、App Store 上架运营等能力。除非后续有明确证据和用户确认，否则 v1.0 默认按本地优先的 iOS App 推进。

## 与 01_mingzhang 的关系

旧 `01_mingzhang` 只继承产品上层理念，不继承具体功能方案。可继承的仅有：`要理财，先明账`、资产/负债/收入/支出的财务视角，以及"用户操作贴近真实记账习惯，系统内部再整理严格语义"的方向。

以下内容默认不继承：`J0-J12` 路线图、旧 Web 架构、API/数据库设计、AI/Agent 方案，以及任何没有被当前 Excel 实践验证过的功能设想。若某个旧想法无法回答"它在当前 Excel 实践里对应什么"，则只能作为启发，不能进入当前阶段规范。

## 证据优先级与结论标注

讨论任何对象、流程、规则、页面或开发输入时，证据顺序固定为：

```text
Excel / CSV / XLSX 样例文件
> 用户口述说明
> 当前仓库内已确认 PRD / Spec
> 当前仓库内 work-plans / plans / design 派生产物
> docs/archive 历史材料
> 01_mingzhang 的产品理念
```

低保真 PNG、页面工作计划和开发路线图是重要输入，但不能压过 Excel 样例、用户确认和已确认 Spec。

**所有领域和产品结论都必须明确标注为：`事实`、`推断`、`待确认`。不要把猜测直接写成需求、规则或产品结论。**

## 文档规范

### 文件命名

新文档默认沿用命名格式：

```text
YYYY-MM-DD-topic.md
```

持续维护型入口文档可以保留稳定文件名，例如 `mvp-prd.md`、`key-screen-low-fidelity-design.md`、`open-questions.md`。

### 权威文档入口

以下文档是当前阶段的常用权威入口，讨论相关主题时优先引用：

| 主题 | 权威文档 |
|------|----------|
| MVP 产品范围与验收场景 | `docs/prd/mvp-prd.md` |
| iOS 产品设计到开发路线图 | `docs/work-plans/2026-05-08-ios-product-to-development-roadmap.md` |
| 关键页面低保真结构设计 | `docs/work-plans/key-screen-low-fidelity-design.md` |
| 关键页面低保真工作安排 | `docs/work-plans/key-screen-low-fidelity-work-plan.md` |
| 关键页面执行计划与图像稿要求 | `docs/plans/2026-05-06-key-screen-low-fidelity-implementation-plan.md` |
| 账月、时间、金额、记录来源与继承规则 | `docs/specs/record-and-month-spec.md` |
| 实时存量-流量闭环引擎 | `docs/specs/stock-flow-engine-spec.md` |
| 收付手段、类型、语义标签与设置边界 | `docs/specs/settings-and-semantics-spec.md` |
| 支付宝/微信导入整理 | `docs/specs/import-alipay-wechat-spec.md` |
| 基金投资明细账与平均成本法 | `docs/specs/investment-ledger-spec.md` |
| 开放问题追踪 | `docs/research/open-questions.md` |

研究类文档可以作为背景输入，但引用时要注意其状态和证据等级：

- `docs/research/excel-practice-analysis.md`
- `docs/research/journal-behavior-analysis.md`
- `docs/research/account-subject-semantics.md`

### 待确认问题追踪

未决问题应记录在 `docs/research/open-questions.md`，不要分散到各处或隐含在讨论中。把问题写清楚时，应同时记录需要什么证据才能关闭。

### 样例数据文件

`evidence/raw/` 中的 Excel/CSV/XLSX 样例是最高优先级证据。保留原始版本，不随意覆盖。Excel 临时锁文件（如 `~$` 开头）不属于正式产物。

### 入口同步

`AGENTS.md` 与 `CLAUDE.md` 是同一套项目指令的两个入口。修改项目工作原则、文档入口、阶段范围或证据规则时，必须保持两者内容一致。

## 仓库结构

```text
06_mingzhang_pkm/
├── AGENTS.md              # Codex / Agent 项目指令入口
├── CLAUDE.md              # Claude Code 项目指令入口，应与 AGENTS.md 同步
├── docs/
│   ├── prd/               # 产品需求文档（MVP 权威入口）
│   ├── specs/             # 领域与规则规格（引擎、导入、投资、设置等）
│   ├── research/          # 研究分析与开放问题
│   ├── work-plans/        # 工作安排、页面设计、开发路线图
│   ├── plans/             # 可执行计划与阶段实施方案
│   └── archive/           # 历史归档（按日期组织的早期探索）
├── evidence/
│   └── raw/               # 原始样例数据（Excel、CSV、XLSX）
├── design/
│   ├── key-screen-low-fidelity/ # iOS 关键页面低保真与图像稿
│   └── archive/           # 设计稿归档
└── .obsidian/             # Obsidian 工作区配置（仅在需要同步工作区行为时修改）
```

## 工作原则

- **先复刻已存在实践，再抽象，再优化**。凡是在当前 Excel 中没有稳定对应物的能力，默认不进入当前阶段范围。
- 当前阶段的产品与设计推进，必须能追溯到 Excel 实践、MVP PRD、Spec 或已确认低保真设计。
- 第一版所谓"后端"默认指 App 内领域服务层 / 本地数据服务 / 账务计算服务，不默认指云服务器。
- 协作时优先编辑已有文档，而非创建新文档。
- 当前阶段真正推进项目的产出包括：澄清一个真实字段或账月流程、确认一条稳定规则、界定一个边界条件、记录一个未解问题及所需证据、把页面设计转成可开发规格、把规则转成可验收场景。
- 不做"通用最佳实践"建议，不引入与当前 Excel 实践无关的记账方法论。
- 讨论前确认：你的建议在当前 Excel 实践、MVP PRD、Spec 或低保真设计中有对应物吗？能指出具体样例、文档或页面依据吗？
- 工作区可能存在用户未提交改动。只修改本任务相关文件，不回滚、不清理、不覆盖无关改动。

## 协作流程

- 简单文档更新可以直接执行；涉及 3 个及以上文件、架构决策、新功能设计或大范围重构时，先建议进入 Plan 模式。
- 修改文档前先确认当前权威入口和证据等级，避免把旧归档材料写成当前规范。
- 如果发现现有文档冲突，先标注冲突来源和待确认问题，不直接择一覆盖。
- 完成修改后，至少检查 `AGENTS.md` 与 `CLAUDE.md` 是否同步；涉及新入口时，同步更新仓库结构和权威文档入口。
