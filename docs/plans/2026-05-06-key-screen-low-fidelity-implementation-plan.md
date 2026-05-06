# 关键页面低保真设计执行计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 基于已确认的信息架构，产出可供后续视觉稿或 iOS 原型使用的关键页面低保真线框与主路径检查材料。

**Architecture:** 以 `docs/work-plans/key-screen-low-fidelity-design.md` 为单一设计输入，按全局规则、五个一级入口、跨入口主路径三层推进。所有页面仍然只做结构和入口，不进入高保真视觉、SwiftUI、数据库或 API 设计。

**Tech Stack:** Markdown 文档；必要时使用 Mermaid 或纯文字线框；验证方式为文档结构检查、关键词检查和 MVP 验收场景人工串联。

---

### Task 1: 固化设计输入与全局规则

**Files:**

- Read: `docs/work-plans/key-screen-low-fidelity-design.md`
- Modify: `docs/work-plans/key-screen-low-fidelity-design.md`

**Step 1: 复核全局规则**

检查文档中是否明确包含：

- 统一账月范围。
- 统一流水回溯。
- 各入口保留自身职责。
- 浮动操作条只在首页和流水出现。
- 账单导入和数据导入术语区分。

**Step 2: 运行结构检查**

Run:

```bash
grep -n "^## " docs/work-plans/key-screen-low-fidelity-design.md
```

Expected: 输出 `0. 设计边界` 到 `5. 设置` 六个二级标题。

**Step 3: 如有遗漏，补齐全局规则**

只编辑 `docs/work-plans/key-screen-low-fidelity-design.md` 的 `0. 设计边界` 部分，不新增范围。

**Step 4: 提交**

Run:

```bash
git add docs/work-plans/key-screen-low-fidelity-design.md
git commit -m "Refine key screen global rules"
```

---

### Task 2: 细化五个入口的低保真线框

**Files:**

- Modify: `docs/work-plans/key-screen-low-fidelity-design.md`

**Step 1: 首页线框检查**

确认首页线框包含：

- 账月范围。
- 收支摘要。
- 收支结构。
- 最近账目。
- 轻量 `+` 快捷入口。

**Step 2: 流水线框检查**

确认流水线框包含：

- 顶部账月范围。
- 记录两行结构。
- 跨账月账月分组。
- 固定行视觉。
- 底部浮动操作条。

**Step 3: 资产负债线框检查**

确认资产负债线框包含：

- 资产合计、负债合计、净资产。
- 资产块。
- 负债块。
- 投资块。

**Step 4: 统计线框检查**

确认统计线框包含：

- 结果总览。
- 收支结构。
- 资产负债变化。
- 投资结果。

**Step 5: 设置线框检查**

确认设置线框包含：

- 账户。
- 科目。
- 数据导出 / 数据导入 / 数据清空。
- 外观 / 隐私 / 安全 / 关于。

**Step 6: 提交**

Run:

```bash
git add docs/work-plans/key-screen-low-fidelity-design.md
git commit -m "Refine low fidelity wireframes"
```

---

### Task 3: 增加主路径流转表

**Files:**

- Modify: `docs/work-plans/key-screen-low-fidelity-design.md`

**Step 1: 新增 `6. 主路径串联检查`**

在文档末尾新增章节，覆盖 MVP 12 条验收场景。

**Step 2: 为每条场景写页面路径**

格式：

```markdown
| 场景 | 页面路径 | 真源落点 | 是否覆盖 |
| --- | --- | --- | --- |
| 首页查看收支并记账 | 首页 -> 记一笔 -> 记录编辑页 -> 流水 | 流水记录 | 是 |
```

**Step 3: 标记缺口**

如果某条路径不清楚，标记为 `待确认`，并补充所需证据或决策。

**Step 4: 提交**

Run:

```bash
git add docs/work-plans/key-screen-low-fidelity-design.md
git commit -m "Add key screen scenario walkthrough"
```

---

### Task 4: 整理跨入口复用对象

**Files:**

- Modify: `docs/work-plans/key-screen-low-fidelity-design.md`

**Step 1: 新增复用对象小节**

在全局规则或文档末尾列出：

- 账月范围选择器。
- 流水列表页。
- 记录详情 / 编辑页。
- 分类详情页。
- 筛选面板。
- 导入来源选择。

**Step 2: 为每个复用对象写使用入口**

示例：

```markdown
| 复用对象 | 使用入口 | 规则 |
| --- | --- | --- |
| 流水列表页 | 首页、流水、资产负债、统计 | 可带预设筛选和返回入口 |
```

**Step 3: 提交**

Run:

```bash
git add docs/work-plans/key-screen-low-fidelity-design.md
git commit -m "Document reusable key screen objects"
```

---

### Task 5: 收口待确认问题

**Files:**

- Modify: `docs/work-plans/key-screen-low-fidelity-design.md`
- Modify: `docs/research/open-questions.md`

**Step 1: 汇总待确认问题**

从五个入口章节收集所有 `待确认` 项。

**Step 2: 区分页面细化问题和领域问题**

- 页面细化问题保留在 `key-screen-low-fidelity-design.md`。
- 领域规则问题追加到 `docs/research/open-questions.md`。

**Step 3: 验证没有重复问题**

Run:

```bash
grep -n "待确认" docs/work-plans/key-screen-low-fidelity-design.md docs/research/open-questions.md
```

Expected: 能看到问题集中在设计文档和开放问题文档，不分散到其他文件。

**Step 4: 提交**

Run:

```bash
git add docs/work-plans/key-screen-low-fidelity-design.md docs/research/open-questions.md
git commit -m "Organize key screen open questions"
```

