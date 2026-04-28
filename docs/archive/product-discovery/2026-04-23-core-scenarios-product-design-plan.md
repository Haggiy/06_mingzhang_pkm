# 核心场景到产品设计推进计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把已确认的核心场景清单继续压缩为可直接支撑产品设计的任务流、界面职责和待确认问题清单。

**Architecture:** 先基于 `2026-04-23-core-scenarios-design.md` 提炼跨账月主流程任务流，再定义每个阶段的产品职责边界，最后把尚未进入主流程的边界问题单独沉淀，避免它们污染主结构。整个推进只编辑 Markdown 文档，不进入页面方案或技术方案。

**Tech Stack:** Markdown、现有研究文档、CSV/XLSX 样例文件

---

### Task 1: 固化主流程任务流

**Files:**
- Review: `docs/plans/2026-04-23-core-scenarios-design.md`
- Create: `docs/plans/2026-04-23-task-flow-design.md`

**Step 1: 提炼六段主流程的入口与出口**

从核心场景清单中整理每一段流程的：
- 开始条件
- 结束条件
- 用户在该段完成的核心任务
- 该段向下一段交付的结果

**Step 2: 写成任务流文档**

文档至少包含：
- 六段流程总览
- 每段的入口/出口
- 每段的关键任务
- 哪些动作必须在账月内完成

**Step 3: 自检任务流是否仍然贴近 Excel 实践**

检查文档中是否出现以下问题：
- 提前引入页面结构
- 提前引入数据库/API 语言
- 用抽象产品话术替代当前 Excel 事实

### Task 2: 定义产品职责边界

**Files:**
- Review: `docs/plans/2026-04-23-core-scenarios-design.md`
- Create: `docs/plans/2026-04-23-product-responsibilities-design.md`

**Step 1: 为每段流程定义产品必须承担的职责**

按六段流程分别回答：
- 产品要帮助用户完成什么
- 产品绝不能简化掉什么
- 产品只需要承接、不需要自动化什么

**Step 2: 把职责压缩成产品骨架约束**

至少要形成以下内容：
- 账月工作区为什么必须存在
- 为什么主账本不是普通明细表
- 为什么补录账单外交易必须是一等公民
- 为什么月末结果视图是主流程的一部分

**Step 3: 自检是否越界到页面细节**

检查并删除：
- 具体页面布局
- 组件细节
- 技术实现猜测

### Task 3: 单列待确认与边界项

**Files:**
- Review: `2026-04-16-account-subject-semantics.md`
- Review: `2026-04-16-journal-bookkeeping-behavior-analysis.md`
- Create: `docs/plans/2026-04-23-product-open-questions.md`

**Step 1: 提取不会改变主流程但仍未收口的问题**

重点关注：
- 少数资产科目边界
- 口袋科目治理
- 历史残留命名
- 后续再讨论的边界场景

**Step 2: 按 `事实 / 推断 / 待确认` 分类记录**

每个问题至少写清：
- 当前已知事实
- 当前推断
- 缺什么证据才能确认
- 为什么它暂时不阻塞主流程产品设计

**Step 3: 自检主流程是否被边界问题污染**

确保待确认问题被单独隔离，而不是重新混回主流程文档里。

### Task 4: 做一轮收束校验

**Files:**
- Review: `docs/plans/2026-04-23-core-scenarios-design.md`
- Review: `docs/plans/2026-04-23-task-flow-design.md`
- Review: `docs/plans/2026-04-23-product-responsibilities-design.md`
- Review: `docs/plans/2026-04-23-product-open-questions.md`

**Step 1: 检查文档之间是否各司其职**

预期分工：
- `core-scenarios-design`：主流程场景清单
- `task-flow-design`：按账月推进的任务流
- `product-responsibilities-design`：产品必须承接的职责边界
- `product-open-questions`：不阻塞主流程的边界问题

**Step 2: 检查是否满足进入下一阶段的条件**

至少回答：
- 主流程是否足够稳定
- 产品骨架是否已经可讨论
- 哪些问题仍然必须先补证据

**Step 3: 记录执行限制**

在最终说明里写明：
- 当前目录不是 Git 仓库
- 因此本轮只能落文档与计划，不能在此目录执行 git commit
