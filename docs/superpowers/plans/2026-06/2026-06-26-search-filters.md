# Feature 9.2 Search Filters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add visible search filters for Feed, Tag, date range, and status to the existing article search.

**Architecture:** Extend the existing `ArticleSearchQuery` with a small filter value object, then keep filtering inside `ArticleListPreparedArticles`. The UI reads available feeds and tags via SwiftData queries and renders compact menu pickers in the existing search bar area.

**Tech Stack:** SwiftUI, SwiftData, existing Feedivo MVVM/query helpers, XCTest via `xcodebuild`.

---

### Task 1: Search Filter Model

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleListQuery.swift`
- Modify: `FeedivoTests/ArticleListQueryTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests for feed, tag, date, status, and combined filtering in `ArticleListQueryTests`.

- [ ] **Step 2: Verify RED**

Run:

```bash
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListQueryTests test
```

Expected: tests fail because `ArticleSearchFilters` and related filtering do not exist.

- [ ] **Step 3: Implement minimal model**

Add `ArticleSearchDateFilter`, `ArticleSearchStatusFilter`, and `ArticleSearchFilters`. Extend `ArticleSearchQuery` to apply the filters after the text match.

- [ ] **Step 4: Verify GREEN**

Run the same focused test command. Expected: `ArticleListQueryTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleListQuery.swift FeedivoTests/ArticleListQueryTests.swift
git commit -m "Add article search filters"
```

### Task 2: Search Filter UI

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleListView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

- [ ] **Step 1: Extend UI state**

Add state for selected feed, selected tag, date filter, and status filter.

- [ ] **Step 2: Render compact filter controls**

Add menu pickers below the search text row when the search UI is visible.

- [ ] **Step 3: Wire filters into query**

Pass the chosen filter values into `ArticleSearchQuery`.

- [ ] **Step 4: Verify build**

Run:

```bash
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleListView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Add search filter controls"
```

### Task 3: Roadmap And Final Verification

**Files:**
- Modify: `FEATURES.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Update project memory**

Document Feature 9.2 as implemented and describe the search filters in `AGENTS.md`.

- [ ] **Step 2: Verify final state**

Run:

```bash
git diff --check
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListQueryTests test
xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' build
```

Expected: no whitespace errors, tests pass, build succeeds.

- [ ] **Step 3: Commit**

```bash
git add FEATURES.md AGENTS.md
git commit -m "Update roadmap for search filters"
```
