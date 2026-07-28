# Article Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add previous/next article navigation for the currently visible feed or smart-filter article list.

**Architecture:** `ContentView` owns the selected article and computes the same visible article scope that the middle list shows. `ArticleViewModel` exposes small, testable helpers for sorting and finding the previous or next article. `ReaderView` and `ArticleCommands` receive closures and enabled states from `ContentView`.

**Tech Stack:** SwiftUI, SwiftData, Observation, Swift Testing, localized String Catalog.

---

### Task 1: Navigation Logic

**Files:**
- Modify: `Feedivo/ViewModels/ArticleViewModel.swift`
- Test: `FeedivoTests/ArticleViewModelTests.swift`

- [x] **Step 1: Write failing tests**

Add tests that create three articles with different dates, sort them newest-first, and verify that previous/next navigation stops at the list edges.

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleViewModelTests`

Expected: FAIL because the navigation helper methods do not exist yet.

- [x] **Step 3: Implement minimal helper methods**

Add methods to `ArticleViewModel`:
- `sortedForList(_:)`
- `previousArticle(before:in:)`
- `nextArticle(after:in:)`

The methods use `Article.id` to find the selected article and return `nil` at the beginning/end.

- [x] **Step 4: Run tests**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleViewModelTests`

Expected: PASS.

### Task 2: UI and Commands

**Files:**
- Modify: `Feedivo/Views/ContentView.swift`
- Modify: `Feedivo/Views/Reader/ReaderView.swift`
- Modify: `Feedivo/App/ArticleCommandActions.swift`
- Modify: `Feedivo/App/ArticleCommands.swift`
- Modify: `Feedivo/Views/ArticleList/ArticleListView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

- [x] **Step 1: Wire visible scope in ContentView**

Add a query for all articles, compute `visibleArticles`, and add `selectPreviousArticle()` / `selectNextArticle()` methods.

- [x] **Step 2: Pass navigation to ReaderView**

Extend `ReaderView` with closures and enabled states. Add toolbar buttons with `chevron.up` and `chevron.down`.

- [x] **Step 3: Extend article commands**

Add previous/next actions to `ArticleCommandActions` and `ArticleCommands`, with `Cmd+Up` and `Cmd+Down` shortcuts.

- [x] **Step 4: Localize visible strings**

Add German, English, French, and Italian strings for previous/next article labels.

- [x] **Step 5: Verify build**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED.

### Task 3: Documentation and Final Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/FEATURES.md`

- [x] **Step 1: Update documentation**

Mark `1.2 Navigation Vor/Zurueck` as implemented as a basis. Move the current work pointer to the next backlog item.

- [x] **Step 2: Run final checks**

Run:
- `git diff --check`
- `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleViewModelTests`
- `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`

Expected: all pass.

- [ ] **Step 3: Commit and push**

Stage only source, test, docs, and localization changes. Do not stage Xcode `UserInterfaceState.xcuserstate`.

Commit message: `Add article previous next navigation`
