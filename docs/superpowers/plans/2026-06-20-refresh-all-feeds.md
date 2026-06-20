# Refresh All Feeds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a macOS command that refreshes all stored feeds and continues when one feed fails.

**Architecture:** Reuse `FeedViewModel.refreshFeed(_:context:)` for the per-feed import path so metadata updates, duplicate detection, and article insertion stay in one place. Add `refreshAllFeeds(_:context:)` as the orchestration method; it refreshes feeds sequentially, records per-feed failures, and leaves a summarized error message after the run. Wire the method through `FeedCommandActions`, `FeedCommands`, and `ContentView`.

**Tech Stack:** SwiftUI Commands, SwiftData, Swift Testing, String Catalog localization.

---

### Task 1: View Model Refresh All

**Files:**
- Modify: `FeedivoTests/FeedViewModelTests.swift`
- Modify: `Feedivo/ViewModels/FeedViewModel.swift`

- [x] Add a failing async test that creates two feeds, makes one refresh fail, and expects the other feed to still receive new articles.
- [x] Run the focused test and confirm it fails because `refreshAllFeeds` does not exist.
- [x] Implement `refreshAllFeeds(_:context:)` by looping through feeds and reusing the existing per-feed refresh logic.
- [x] Run the focused test and confirm it passes.

### Task 2: macOS Command Wiring

**Files:**
- Modify: `FeedivoTests/FeedCommandActionsTests.swift`
- Modify: `Feedivo/App/FeedCommandActions.swift`
- Modify: `Feedivo/App/FeedCommands.swift`
- Modify: `Feedivo/Views/ContentView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

- [x] Add a failing test that expects `FeedCommandActions` to expose `refreshAllFeeds` and keep it available without a selected feed.
- [x] Run the focused command-actions test and confirm it fails for the missing action.
- [x] Add `refreshAllFeeds` and `canRefreshAllFeeds` to `FeedCommandActions`.
- [x] Add localized `feed.refreshAll.command`.
- [x] Add `Alle Feeds aktualisieren` with `Cmd+Shift+R` to the `Feed` menu.
- [x] Wire `ContentView` so the command fetches all `Feed` models and calls `feedViewModel.refreshAllFeeds`.
- [x] Run focused tests and confirm they pass.

### Task 3: Documentation, Verification, Commit

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/FEATURES.md`
- Modify: `docs/superpowers/plans/2026-06-20-refresh-all-feeds.md`

- [x] Mark all-feeds refresh as implemented in `AGENTS.md`.
- [x] Mark the feature as implemented in `docs/FEATURES.md` and keep remaining M2 work current.
- [x] Run `git diff --check`.
- [x] Run `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests`.
- [x] Run `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`.
- [x] Stage only project files, commit, and push to `main`.
