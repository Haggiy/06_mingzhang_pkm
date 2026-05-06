# 关键页面低保真设计执行计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 基于已确认的信息架构，产出可供后续 iOS 原型继续推进的关键页面结构文档、主路径检查材料和 image2 生成的 App 感页面图像稿。

**Architecture:** 以 `docs/work-plans/key-screen-low-fidelity-design.md` 为单一设计输入，按全局规则、五个一级入口、跨入口主路径三层推进。页面图像稿使用 image2 直接生成，作为低保真到视觉方向之间的结构化 App 截图草案；不进入 SwiftUI、数据库或 API 设计。

**Tech Stack:** Markdown 文档；image2 图像生成；参考图像位于 `design/archive/homepage-20260427/`；验证方式为文档结构检查、关键词检查、MVP 验收场景人工串联和生成图像人工审查。

---

## 图像生成硬性要求

执行本计划时，Codex 必须直接使用 image2 的图像生成能力生成页面图像稿。

要求：

- 不允许只写图像提示词让用户自行生成。
- 不允许只停留在文字线框。
- 生成图像必须看起来像真实 iOS App 页面，而不是流程图、白板图、PPT 或低保真灰框草图。
- 整体画风参考 `design/archive/homepage-20260427/主页设计-v20260427-v1.png` 到 `v4.png`。
- 风格关键词：白色背景、轻玻璃质感、柔和阴影、8-16px 圆角卡片、清晰 iOS 状态栏、底部 Tab、克制图标、金融数据表格感、中文界面、真实 App 截图感。
- 页面内容必须来自 `docs/work-plans/key-screen-low-fidelity-design.md`，不能凭空增加预算、AI、预测、复杂看板等已排除能力。
- 生成图像保存到 `design/key-screen-low-fidelity/`，文件名使用 `YYYY-MM-DD-入口-页面.png`。

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
- Read: `design/archive/homepage-20260427/主页设计-v20260427-v1.png`
- Read: `design/archive/homepage-20260427/主页设计-v20260427-v2.png`
- Read: `design/archive/homepage-20260427/主页设计-v20260427-v3.png`
- Read: `design/archive/homepage-20260427/主页设计-v20260427-v4.png`

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

### Task 3: 使用 image2 生成关键页面图像稿

**Files:**

- Read: `docs/work-plans/key-screen-low-fidelity-design.md`
- Read: `design/archive/homepage-20260427/主页设计-v20260427-v1.png`
- Read: `design/archive/homepage-20260427/主页设计-v20260427-v2.png`
- Read: `design/archive/homepage-20260427/主页设计-v20260427-v3.png`
- Read: `design/archive/homepage-20260427/主页设计-v20260427-v4.png`
- Create: `design/key-screen-low-fidelity/2026-05-06-首页.png`
- Create: `design/key-screen-low-fidelity/2026-05-06-流水.png`
- Create: `design/key-screen-low-fidelity/2026-05-06-资产负债.png`
- Create: `design/key-screen-low-fidelity/2026-05-06-统计.png`
- Create: `design/key-screen-low-fidelity/2026-05-06-设置.png`

**Step 1: 创建输出目录**

Run:

```bash
mkdir -p design/key-screen-low-fidelity
```

**Step 2: 生成首页图像稿**

直接调用 image2 生成 `首页` 页面图像。

图像必须包含：

- 顶部账月范围。
- 收支摘要。
- 收支结构。
- 最近账目。
- 轻量 `+` 快捷入口。
- 底部 Tab。

风格必须参考 `design/archive/homepage-20260427/` 中的既有稿子。

Expected: 保存为 `design/key-screen-low-fidelity/2026-05-06-首页.png`。

**Step 3: 生成流水图像稿**

直接调用 image2 生成 `流水` 页面图像。

图像必须包含：

- 顶部账月范围。
- 记录列表两行结构。
- 固定行浅底色和左侧细竖线。
- 底部浮动操作条：搜索 / 点击这里记一笔 / 筛选。
- 底部 Tab。

Expected: 保存为 `design/key-screen-low-fidelity/2026-05-06-流水.png`。

**Step 4: 生成资产负债图像稿**

直接调用 image2 生成 `资产负债` 页面图像。

图像必须包含：

- 资产合计、负债合计、净资产。
- 资产块。
- 负债块。
- 投资块。
- 底部 Tab。

Expected: 保存为 `design/key-screen-low-fidelity/2026-05-06-资产负债.png`。

**Step 5: 生成统计图像稿**

直接调用 image2 生成 `统计` 页面图像。

图像必须包含：

- 结果总览。
- 收支结构。
- 资产负债变化。
- 投资结果。
- 底部 Tab。

Expected: 保存为 `design/key-screen-low-fidelity/2026-05-06-统计.png`。

**Step 6: 生成设置图像稿**

直接调用 image2 生成 `设置` 页面图像。

图像必须包含：

- 记账配置：账户、科目。
- 数据管理：数据导出、数据导入、数据清空。
- App 设置：外观、隐私、安全、关于。
- 底部 Tab。

Expected: 保存为 `design/key-screen-low-fidelity/2026-05-06-设置.png`。

**Step 7: 人工审查生成结果**

逐张检查：

- 是否像真实 App 截图。
- 是否与 `design/archive/homepage-20260427/` 画风一致。
- 是否没有加入已排除功能。
- 是否中文文案清晰。
- 是否没有明显错字、重叠、变形或乱码。

不合格的图像必须重新用 image2 生成。

**Step 8: 提交**

Run:

```bash
git add design/key-screen-low-fidelity
git commit -m "Generate key screen low fidelity app images"
```

---

### Task 4: 增加主路径流转表

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

### Task 5: 整理跨入口复用对象

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

### Task 6: 收口待确认问题

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
