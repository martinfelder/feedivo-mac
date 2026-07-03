# SQLite-Only Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the remaining Feedivo product paths from SwiftData-backed article/admin state to SQLite-first state.

**Architecture:** Keep the existing GRDB foundation and convert one product surface at a time. First remove visible article legacy routes, then make feeds, tags, rules, and smart-folder definitions available through SQLite records/stores before changing their views.

**Tech Stack:** SwiftUI, GRDB, existing `FeedivoDatabase`, existing `TimelineStore`/`ArticleStore`/`TagStore`, Swift Testing via `xcodebuild`.

---

### Task 1: Remove Article Legacy Routing From ContentView

**Files:**
- Modify: `Feedivo/Views/ContentView.swift`
- Modify: `Feedivo/App/ArticleCommandActions.swift`
- Test: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

- [x] Add source tests proving `ContentView` no longer stores `selectedArticle: Article?`, no longer routes to `ReaderView`, and Article commands are sourced from SQLite snapshots.
- [x] Run `xcodebuild test -quiet -parallel-testing-enabled NO -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests` and verify the new checks fail.
- [x] Remove `selectedArticle`, `articleNavigationState`, `ArticleViewModel`, and `OfflineDownloadService` from `ContentView`.
- [x] Remove the `ReaderView` branch from `ContentView` detail.
- [x] Remove SwiftData `Article?` command construction from `ContentView`; keep only the SQLite `ArticleReaderSnapshot` command path.
- [x] Run the same test command and verify it passes.

### Task 2: Isolate Legacy Article Views

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleListView.swift`
- Modify: `Feedivo/Views/Reader/ReaderView.swift`
- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

- [ ] Add source tests proving `ArticleListView` and `ReaderView` are not referenced from product routing files (`ContentView`, `ArticleWindowView`, `ArticleCommands`).
- [ ] Add clear `Legacy` comments to the old views or move references behind test-only/previews if needed.
- [ ] Run focused source tests and build.

### Task 3: Add SQLite Definition Tables For Admin State

**Files:**
- Modify: `Feedivo/Database/FeedivoDatabaseMigrator.swift`
- Create: `Feedivo/Database/Records/FeedFolderRecord.swift`
- Create: `Feedivo/Database/Records/RuleRecord.swift`
- Create: `Feedivo/Database/Records/RuleConditionRecord.swift`
- Create: `Feedivo/Database/Records/SmartFolderRecord.swift`
- Create: `Feedivo/Database/Records/SmartFolderConditionRecord.swift`
- Test: `FeedivoTests/SQLiteDatabaseMigrationTests.swift`

- [ ] Add failing migration tests for `feed_folders`, `rules`, `rule_conditions`, `smart_folders`, and `smart_folder_conditions`.
- [ ] Add v6 migration with indexes preserving sort order, default keys, and foreign-key cascades.
- [ ] Add record structs matching the new tables.
- [ ] Run database migration tests.

### Task 4: Add SQLite Admin Stores

**Files:**
- Create: `Feedivo/Stores/FeedFolderStore.swift`
- Create: `Feedivo/Stores/SQLiteRuleStore.swift`
- Create: `Feedivo/Stores/SQLiteSmartFolderStore.swift`
- Test: new focused store tests.

- [ ] Add failing tests for CRUD and ordering for feed folders, rules, and smart folders.
- [ ] Implement stores using GRDB transactions.
- [ ] Add SwiftData backfill helpers that mirror existing admin definitions into SQLite during app startup.
- [ ] Run focused store tests.

### Task 5: Convert Admin Views To SQLite Sources

**Files:**
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`
- Modify: `Feedivo/Views/Tags/TagManagerView.swift`
- Modify: `Feedivo/Views/Rules/RuleSettingsView.swift`
- Modify: `Feedivo/Views/Rules/RuleWizardView.swift`
- Modify: `Feedivo/Views/SmartFolders/SmartFolderSettingsView.swift`
- Modify: `Feedivo/Views/SmartFolders/SmartFolderEditorView.swift`
- Modify: `Feedivo/Views/Settings/SettingsView.swift`

- [ ] Add source tests proving these views no longer use SwiftData `@Query` for feeds/tags/rules/smart-folder definitions where SQLite stores exist.
- [ ] Convert each view to load snapshots from the matching SQLite store.
- [ ] Keep SwiftData model conversion only at boundaries where old data must be backfilled.
- [ ] Run focused source tests and build after each view group.

### Task 6: Reduce SwiftData Container Scope

**Files:**
- Modify: `Feedivo/App/FeedivoApp.swift`
- Modify: `AGENTS.md`
- Modify: `FEATURES.md`

- [ ] Add source tests documenting which SwiftData services remain and why.
- [ ] Remove product dependencies on SwiftData article/admin models once no UI path needs them.
- [ ] Update docs with the final SQLite-only status and any intentionally retained migration/backfill code.
- [ ] Run focused tests, `xcodebuild build`, and `git diff --check`.
