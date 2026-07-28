# Feed Management SQLite-First Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert feed-management views and mutations from SwiftData-first to SQLite-first.

**Architecture:** Extend `FeedStore` with focused feed-admin mutations and make feed-management UI load/mutate `FeedRecord` or SQLite snapshots. Keep SwiftData `Feed` only at transition boundaries that are not part of this slice.

**Tech Stack:** SwiftUI, GRDB, Swift Testing, `xcodebuild`, existing `FeedivoDatabase` environment.

---

### Task 1: FeedStore Admin Mutations

**Files:**
- Modify: `Feedivo/Stores/FeedStore.swift`
- Modify: `Feedivo/Database/Records/FeedRecord.swift`
- Test: `FeedivoTests/SQLiteAdminStoreTests.swift`

- [x] Add failing store tests for rename, refresh interval, folder assignment, notification flag, retention settings, delete, feed-tag assign/remove.
- [x] Add `FeedRecord: Identifiable`.
- [x] Add focused `FeedStore` methods for feed-management mutations.
- [x] Add or reuse `TagStore` helpers for feed-tag assignment/removal where needed.
- [x] Run focused store tests and confirm green.
- [x] Commit.

### Task 2: FeedRenameView SQLite-First

**Files:**
- Modify: `Feedivo/Views/Sidebar/FeedRenameView.swift`
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`
- Test: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

- [x] Add failing source test proving `FeedRenameView` does not use `FeedViewModel.renameFeed` or `ModelContext`.
- [x] Convert `FeedRenameView` to load and save through `FeedStore`.
- [x] Keep the visible UI behavior unchanged: display title edit, original title display, restore original button.
- [x] Make `SidebarView` refresh its SQLite sidebar state after rename dismissal.
- [x] Run focused source/store tests and build.
- [x] Commit.

### Task 3: FeedPropertiesView SQLite-First

**Files:**
- Modify: `Feedivo/Views/Sidebar/FeedPropertiesView.swift`
- Modify: `Feedivo/Stores/FeedStore.swift`
- Test: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`
- Test: `FeedivoTests/SQLiteAdminStoreTests.swift`

- [x] Add failing source test proving feed properties management writes use `FeedStore`/`TagStore`, not `modelContext.save()` or `TagViewModel`.
- [x] Convert refresh interval, folder assignment, notification flag, retention settings to `FeedStore`.
- [x] Convert assigned/available feed tags to `TagRecord`s from `TagStore`.
- [x] Convert add/remove feed tag actions to SQLite `feed_tags`.
- [x] Keep existing SQLite log and metric loading.
- [x] Run focused source/store tests and build.
- [x] Commit.

### Task 4: Feed Management Settings Rows SQLite-First

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift`
- Modify: `Feedivo/Views/Settings/FeedManagementSettingsState.swift`
- Test: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

- [x] Add failing source test proving feed-management rows prefer SQLite snapshots/records for display and metrics.
- [x] Convert displayed feed-management metadata to SQLite records where possible.
- [x] Keep SwiftData `Feed` only where an existing command still requires it, and document that boundary.
- [x] Run focused tests and build.
- [x] Commit.

### Task 5: Documentation And Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `FEATURES.md`
- Modify: `docs/superpowers/plans/2026-07-03-feed-management-sqlite-first.md`

- [x] Update project memory to record feed management as SQLite-first.
- [x] Run focused source/store tests.
- [x] Run `xcodebuild build -quiet -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`.
- [x] Run `git diff --check`.
- [x] Commit.
