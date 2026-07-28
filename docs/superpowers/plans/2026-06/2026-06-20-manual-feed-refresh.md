# Manual Feed Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add manual refresh for the currently selected feed via the macOS `Feed` menu and `Cmd+R`.

**Architecture:** Keep refresh orchestration in `FeedViewModel`, using an injectable feed-fetch closure so tests can run without network access. Expose the refresh action through the existing `FeedCommandActions` focused-value bridge.

**Tech Stack:** SwiftUI Commands, SwiftData, Swift Testing, FeedKit-backed `FeedService`.

---

### Task 1: Refresh One Feed In FeedViewModel

**Files:**
- Modify: `Feedivo/ViewModels/FeedViewModel.swift`
- Test: `FeedivoTests/FeedViewModelTests.swift`

- [x] Write a failing Swift Testing test that creates an in-memory SwiftData feed with one existing article, refreshes with a fake `ParsedFeed`, expects one new article, no duplicate for the existing link, updated feed metadata, updated `lastRefreshed`, and no error.
- [x] Run the focused test and verify it fails because `FeedViewModel` has no injectable fetcher or `refreshFeed`.
- [x] Add `FeedViewModel.init(fetchFeed:)`, store the fetch closure, update `addFeed` to use it, and add `refreshFeed(_:context:)`.
- [x] Deduplicate by normalized article identity: `link` when present, otherwise `title` plus `publishedAt`.
- [x] Run focused tests and all `FeedivoTests`.

### Task 2: Add Feed Refresh Command

**Files:**
- Modify: `Feedivo/App/FeedCommandActions.swift`
- Modify: `Feedivo/App/FeedCommands.swift`
- Modify: `Feedivo/Views/ContentView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

- [x] Add localized menu label for `Feed aktualisieren`.
- [x] Add `refreshSelectedFeed` to `FeedCommandActions`.
- [x] Add `Feed > Feed aktualisieren` with `Cmd+R`, disabled without selection.
- [x] Wire `ContentView` so the command refreshes `selectedFeed` asynchronously.
- [x] Run build and unit tests.

### Task 3: Documentation And Commit

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/FEATURES.md`

- [x] Mark manual refresh for current feed as implemented basis.
- [x] Note that all-feeds refresh and `Cmd+N` feed-add command remain next.
- [x] Commit and push to `main`.
