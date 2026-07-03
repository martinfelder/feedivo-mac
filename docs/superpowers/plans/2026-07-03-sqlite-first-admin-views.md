# SQLite-First Admin Views Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the partially migrated Feedivo admin views to SQLite-first data sources while keeping SwiftData only for remaining transition/backfill paths.

**Architecture:** Reuse the existing GRDB foundation and admin stores. Convert one admin surface at a time from SwiftData model lists to SQLite records/snapshots, with source tests documenting the boundary. Keep feed object actions that still require SwiftData isolated and documented.

**Tech Stack:** SwiftUI, GRDB, Swift Testing, `xcodebuild`, existing `FeedivoDatabase` environment.

---

### Task 1: TagManager SQLite-First

**Files:**
- Modify: `Feedivo/Views/Tags/TagManagerView.swift`
- Modify: `Feedivo/Stores/TagStore.swift`
- Test: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`
- Test: `FeedivoTests/SQLiteAdminStoreTests.swift`

- [x] Add failing source test proving `TagManagerView` has no `@Query(sort: \Tag.name)` and uses `TagRecord`.
- [x] Add failing store test for tag rename/color/delete through `TagStore`.
- [x] Add `TagStore.renameTag`, `TagStore.updateColor`, and duplicate-name checks.
- [x] Convert `TagManagerView` rows to `TagRecord` and reload after create/update/delete.
- [x] Run focused tests and build.
- [x] Commit.

### Task 2: Sidebar Feed-Folder And Smart-Folder Sources

**Files:**
- Modify: `Feedivo/ViewModels/SQLiteSidebarState.swift`
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`
- Modify: `Feedivo/Stores/FeedFolderStore.swift`
- Modify: `Feedivo/Stores/SQLiteSmartFolderStore.swift`
- Test: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

- [ ] Add failing source test proving `SidebarView` has no `@Query(sort: \FeedFolder.name)` and no `@Query(sort: \SmartFolder.sortOrder)`.
- [ ] Extend `SQLiteSidebarState` to load `FeedFolderRecord`s and sidebar `SQLiteSmartFolderSnapshot`s.
- [ ] Convert sidebar folder grouping to use SQLite folder names.
- [ ] Convert smart-folder rows to use SQLite snapshots/string IDs for selection.
- [ ] Keep SwiftData `Feed` query only for feed object actions that still require `Feed`.
- [ ] Run focused tests and build.
- [ ] Commit.

### Task 3: SmartFolder Settings And Editor SQLite-First

**Files:**
- Modify: `Feedivo/Views/SmartFolders/SmartFolderSettingsView.swift`
- Modify: `Feedivo/Views/SmartFolders/SmartFolderEditorView.swift`
- Modify: `Feedivo/Stores/SQLiteSmartFolderStore.swift`
- Test: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`
- Test: `FeedivoTests/SQLiteAdminStoreTests.swift`

- [ ] Add failing source test proving smart-folder settings/editor do not use `@Query(sort: \SmartFolder.sortOrder)` or `SmartFolder` as sheet payload.
- [ ] Add store helpers for duplicate, delete, reorder, restore defaults.
- [ ] Convert settings rows to `SmartFolderRecord` plus condition records.
- [ ] Convert editor save/update to `SQLiteSmartFolderStore`.
- [ ] Run focused tests and build.
- [ ] Commit.

### Task 4: Rule Settings And Wizard SQLite-First

**Files:**
- Modify: `Feedivo/Views/Rules/RuleSettingsView.swift`
- Modify: `Feedivo/Views/Rules/RuleWizardView.swift`
- Modify: `Feedivo/Stores/SQLiteRuleStore.swift`
- Test: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`
- Test: `FeedivoTests/SQLiteAdminStoreTests.swift`

- [ ] Add failing source test proving rule settings/wizard do not use `@Query(sort: \Rule.sortOrder)` or SwiftData `Rule` as sheet payload.
- [ ] Add store helpers for duplicate, delete, reorder, enable toggle, and save rule conditions.
- [ ] Convert rule settings list and matching counts to SQLite rule snapshots.
- [ ] Convert wizard create/update to `SQLiteRuleStore` and tag picker to `TagRecord`.
- [ ] Run focused tests and build.
- [ ] Commit.

### Task 5: Documentation And Final Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `FEATURES.md`
- Modify: `docs/superpowers/plans/2026-07-03-sqlite-only-management.md`

- [ ] Update project memory so admin views are recorded as SQLite-first.
- [ ] Run `xcodebuild test` for focused source/store tests.
- [ ] Run `xcodebuild build -quiet -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`.
- [ ] Run `git diff --check`.
- [ ] Commit.
