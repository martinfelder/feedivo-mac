# Feed Properties Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a feed context-menu action that opens a localized feed-properties sheet with metadata, editable refresh interval, next-fetch calculation, and the latest feed log entries.

**Architecture:** `Feed` stores the new metadata and owns `FeedLogEntry` records through a cascade relationship. `FeedViewModel` writes feed metadata and log entries during add/refresh flows. `FeedPropertiesView` renders the sheet and uses small formatter helpers so date, next-refresh, latest-article, and log limiting behavior can be unit-tested without UI.

**Tech Stack:** SwiftUI, SwiftData, Observation, Swift Testing, String Catalog localization.

---

### Task 1: Data Model and Formatter

**Files:**
- Modify: `Feedivo/Models/Feed.swift`
- Create: `Feedivo/Models/FeedLogEntry.swift`
- Create: `Feedivo/Views/Sidebar/FeedPropertiesFormatter.swift`
- Modify: `Feedivo/App/FeedivoApp.swift`
- Test: `FeedivoTests/FeedPropertiesFormatterTests.swift`
- Modify: `FeedivoTests/FeedViewModelTests.swift`

- [x] **Step 1: Write failing formatter tests**

Create tests for `nextRefreshDate(lastRefreshed:intervalMinutes:)`, latest article selection by `publishedAt`, and limiting log entries to the newest 20.

- [x] **Step 2: Run tests to verify failure**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedPropertiesFormatterTests`

Expected: FAIL because `FeedPropertiesFormatter` and `FeedLogEntry` do not exist.

- [x] **Step 3: Add model and formatter**

Add optional/default-backed fields to `Feed`: `siteURL`, `followedAt`, `folderName`, and `logEntries`. Create `FeedLogEntry` with `id`, `createdAt`, `kind`, `message`, and optional `feed`.

- [x] **Step 4: Register model containers**

Add `FeedLogEntry.self` to the app `ModelContainer` and in-memory test containers.

- [x] **Step 5: Run formatter tests**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedPropertiesFormatterTests`

Expected: PASS.

### Task 2: FeedViewModel Metadata and Logs

**Files:**
- Modify: `Feedivo/ViewModels/FeedViewModel.swift`
- Modify: `FeedivoTests/FeedViewModelTests.swift`

- [x] **Step 1: Write failing view-model assertions**

Extend existing tests to assert that adding a feed stores `siteURL`, sets `followedAt`, and creates a log entry. Extend refresh tests to assert success and failure log entries.

- [x] **Step 2: Run tests to verify failure**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedViewModelTests`

Expected: FAIL until `FeedViewModel` writes the new fields and log entries.

- [x] **Step 3: Implement metadata and log writes**

On add, set `siteURL`, `followedAt`, and append an info log. On refresh success, update `siteURL`, `lastRefreshed`, and append an info log with new-article count. On refresh failure, append an error log. Prune stored logs to the newest 20 entries per feed.

- [x] **Step 4: Run view-model tests**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedViewModelTests`

Expected: PASS.

### Task 3: Context Menu and Properties Sheet

**Files:**
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`
- Create: `Feedivo/Views/Sidebar/FeedPropertiesView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

- [x] **Step 1: Add localized keys**

Add labels and placeholders for the sheet in German, English, French, and Italian.

- [x] **Step 2: Add context menu entry**

Add `Feed Eigenschaften...` above delete in each feed row context menu and present `FeedPropertiesView` as a sheet.

- [x] **Step 3: Build the properties sheet**

Render original title, website, XML address, followed-at date, folder placeholder, latest article, editable refresh interval, next fetch, last refreshed, and newest 20 log entries.

- [x] **Step 4: Persist refresh interval changes**

Use a local selected interval state and save `feed.refreshIntervalMinutes` through the SwiftData context when the user changes the picker.

### Task 4: Documentation and Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/FEATURES.md`
- Modify: `docs/superpowers/plans/2026-06-20-feed-properties.md`

- [x] **Step 1: Update documentation**

Mark feed properties as implemented as a basis, document the new model and current work pointer.

- [x] **Step 2: Run final verification**

Run:
- `git diff --check`
- `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedPropertiesFormatterTests`
- `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedViewModelTests`
- `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`

Expected: all pass.

- [x] **Step 3: Commit and push**

Stage source, tests, localization, docs, and this plan. Do not stage Xcode `UserInterfaceState.xcuserstate`.

Commit message: `Add feed properties sheet`
