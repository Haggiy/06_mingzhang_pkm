# AGENTS.md Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite `AGENTS.md` so it defines this repository as the new MingZhang source-of-truth research vault for reconstructing the Excel bookkeeping practice into a future iOS app.

**Architecture:** Preserve a single top-level `AGENTS.md`, but change its role from generic contributor guide to repository-direction guardrail. Add one design record under `docs/plans/` so future edits can trace the agreed intent.

**Tech Stack:** Markdown, Obsidian vault structure, local sample data files

---

### Task 1: Save the approved design context

**Files:**
- Create: `docs/plans/2026-04-17-agents-refactor-design.md`

**Step 1: Create the design note**

Write a short Markdown design record that captures:

- repository定位
- 当前阶段边界
- 与 `01_mingzhang` 的继承关系
- 证据优先级
- 新 `AGENTS.md` 的目标结构

**Step 2: Verify the design note**

Run: `sed -n '1,220p' docs/plans/2026-04-17-agents-refactor-design.md`
Expected: sections are present and aligned with the approved conversation.

### Task 2: Rewrite the repository guidance

**Files:**
- Modify: `AGENTS.md`

**Step 1: Replace the generic guide with repository-specific guidance**

Rewrite `AGENTS.md` to include:

- 仓库定位
- 当前阶段范围
- 与 `01_mingzhang` 的关系
- 证据优先级与结论标注
- 有效产出与协作方式

**Step 2: Keep the file concise**

The final file should stay short, direct, and avoid roadmap, architecture, or feature-detail speculation.

**Step 3: Verify the rewritten file**

Run: `sed -n '1,220p' AGENTS.md`
Expected: title is `Repository Guidelines`, body is Chinese, and the content reflects “先复刻，再抽象，再优化”.

### Task 3: Run repository reality checks

**Files:**
- Review: `2026-04-16-excel-practice-design.md`
- Review: `2026-04-16-account-subject-semantics.md`
- Review: `2026-04-16-journal-bookkeeping-behavior-analysis.md`

**Step 1: Confirm wording does not overstate current maturity**

Check that the guide describes the repository as:

- Excel 实践分析阶段
- 面向未来 iOS App
- 不继承旧项目复杂功能方案

**Step 2: Note execution limits**

Record that this directory is not currently a Git repository, so the design doc cannot be committed from here.
