# SQLite SmartFilter Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route the built-in SmartFilter article lists through SQLite/GRDB.

**Architecture:** Extend `TimelineScope` with `smartFilter(SmartFilter)`, map each
filter to SQL predicates in `TimelineStore`, expose a SmartFilter loader in
`SQLiteFeedArticleListState`, and route `ContentView` to `SQLiteFeedArticleListView`
for selected SmartFilters.

**Tech Stack:** Swift, SwiftUI, GRDB, Swift Testing, existing Feedivo SQLite stores.

---

### Task 1: SmartFilter SQL Scope

**Files:**
- Modify: `Feedivo/Stores/TimelineStore.swift`
- Test: `FeedivoTests/SQLiteTimelineStoreTests.swift`

- [ ] Add failing tests for `.smartFilter(.unread)`, `.smartFilter(.starred)`,
  `.smartFilter(.today)`, and `.smartFilter(.hidden)`.
- [ ] Run `xcodebuild test -quiet -parallel-testing-enabled NO -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteTimelineStoreTests`
  and confirm the tests fail because `TimelineScope.smartFilter` does not exist.
- [ ] Add `TimelineScope.smartFilter(SmartFilter)` and SQL predicates for the
  built-in filter states.
- [ ] Re-run the same test command and confirm it passes.

### Task 2: SQLite State And View Routing

**Files:**
- Modify: `Feedivo/ViewModels/SQLiteFeedArticleListState.swift`
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`
- Modify: `Feedivo/Views/ContentView.swift`
- Test: `FeedivoTests/SQLiteFeedArticleListStateTests.swift`
- Test: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

- [ ] Add a failing state test that loads `.unread` through
  `SQLiteFeedArticleListState.load(smartFilter:database:selectedArticleID:)`.
- [ ] Add a failing source test that `ContentView` routes `selectedSmartFilter` to
  `SQLiteFeedArticleListView(smartFilter:)` and no longer to
  `ArticleListView(smartFilter:)`.
- [ ] Run the two targeted test classes and confirm the new tests fail for the
  missing API/routing.
- [ ] Add the SmartFilter loader and view initializer, then change `ContentView`.
- [ ] Re-run targeted tests and confirm they pass.

### Task 3: Docs And Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `FEATURES.md`

- [ ] Document that built-in SmartFilter lists now use the SQLite timeline path.
- [ ] Run targeted tests for timeline/state/source coverage.
- [ ] Run `xcodebuild build -quiet -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`.
- [ ] Run `git diff --check`.
- [ ] Commit with `feat: route smart filters through sqlite`.
