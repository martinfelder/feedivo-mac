# SQLite Custom Smart Folders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route custom Smart Folder article lists through SQLite snapshots instead of SwiftData article materialization.

**Architecture:** Keep Smart Folder definitions in SwiftData for this slice, but convert them to sendable SQLite snapshots at the UI boundary. `TimelineStore` translates those snapshots into SQL predicates and returns `ArticleListSnapshot` rows. `ContentView` then uses the existing SQLite list and reader path for selected Smart Folders.

**Tech Stack:** Swift, SwiftUI, SwiftData definitions, GRDB, SQLite FTS5, Swift Testing.

---

## File Structure

- Create `Feedivo/Snapshots/SQLiteSmartFolderSnapshot.swift`: sendable snapshots for folder match mode and conditions.
- Modify `Feedivo/Stores/TimelineStore.swift`: add `TimelineScope.smartFolder`, SQL predicate building, date helpers and FTS joins.
- Modify `Feedivo/ViewModels/SQLiteFeedArticleListState.swift`: load custom Smart Folder scopes.
- Modify `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`: add Smart Folder initializer/title/reload branch.
- Modify `Feedivo/Views/ContentView.swift`: route `selectedSmartFolder` to the SQLite list path.
- Modify `FeedivoTests/SQLiteTimelineStoreTests.swift`: TDD coverage for Smart Folder SQL semantics.
- Modify `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`: assert custom Smart Folders use `SQLiteFeedArticleListView`.
- Modify `AGENTS.md` and `FEATURES.md`: record the implemented slice.

## Tasks

### Task 1: Timeline Tests

- [ ] Add failing tests in `FeedivoTests/SQLiteTimelineStoreTests.swift` for status, tags, feed title, feed folder, date, title/author/text, `all`/`any`, `isNot`, and hidden handling.
- [ ] Run:

```bash
xcodebuild test -quiet -parallel-testing-enabled NO -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteTimelineStoreTests
```

Expected: compile fails because `SQLiteSmartFolderSnapshot` and `TimelineScope.smartFolder` do not exist yet.

### Task 2: Snapshot And Store

- [ ] Add `SQLiteSmartFolderSnapshot` and `SQLiteSmartFolderConditionSnapshot`.
- [ ] Add `TimelineScope.smartFolder(SQLiteSmartFolderSnapshot)`.
- [ ] Implement SQL predicate generation for all supported Smart Folder fields/operators.
- [ ] Re-run the focused timeline tests.

Expected: timeline tests pass.

### Task 3: UI Routing

- [ ] Add failing source-configuration assertion that `ContentView` uses `SQLiteFeedArticleListView(smartFolder:)`.
- [ ] Add Smart Folder loading to `SQLiteFeedArticleListState`.
- [ ] Add Smart Folder initializer and reload/title handling to `SQLiteFeedArticleListView`.
- [ ] Replace the `ArticleListView(smartFolder:)` branch in `ContentView`.
- [ ] Re-run `FeedivoAppSceneConfigurationTests`.

Expected: configuration tests pass.

### Task 4: Verification And Docs

- [ ] Update `AGENTS.md` and `FEATURES.md`.
- [ ] Run focused SQLite timeline and app configuration tests.
- [ ] Run full tests:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
```

- [ ] Run `git diff --check`.
- [ ] Commit with:

```bash
git add AGENTS.md FEATURES.md Feedivo FeedivoTests docs/superpowers/specs/2026-07-03-sqlite-custom-smart-folders-design.md docs/superpowers/plans/2026-07-03-sqlite-custom-smart-folders.md
git commit -m "feat: route custom smart folders through sqlite"
```
