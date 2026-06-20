# Favicon Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show discovered feed favicons in the sidebar using HTML icon discovery with a safe fallback.

**Architecture:** Add a focused `FaviconService` that derives a site URL, fetches the site HTML, parses `<link rel="...icon...">` tags, ranks candidates, and falls back to `/favicon.ico`. Extend `ParsedFeed` with an optional `siteURL` from feed metadata so the view model can discover and persist `Feed.faviconURL` when adding or refreshing feeds. Add a real `FeedRowView` for sidebar display.

**Tech Stack:** Swift, URLSession async/await, Swift Testing, SwiftUI `AsyncImage`, SwiftData.

---

### Task 1: Favicon URL Parsing And Ranking

**Files:**
- Create: `Feedivo/Services/FaviconService.swift`
- Create: `FeedivoTests/FaviconServiceTests.swift`

- [x] Add failing tests for HTML icon discovery, relative URL normalization, candidate ranking, and `/favicon.ico` fallback.
- [x] Run focused favicon tests and confirm they fail because `FaviconService` does not exist.
- [x] Implement `FaviconService` parsing and ranking.
- [x] Run focused favicon tests and confirm they pass.

### Task 2: Feed Metadata And Persistence

**Files:**
- Modify: `Feedivo/Services/FeedService.swift`
- Modify: `Feedivo/ViewModels/FeedViewModel.swift`
- Modify: `FeedivoTests/FeedivoTests.swift`
- Modify: `FeedivoTests/FeedViewModelTests.swift`

- [x] Add tests for parsed feed site URLs and persisted favicon URLs on add/refresh.
- [x] Run focused tests and confirm they fail.
- [x] Extend `ParsedFeed` with `siteURL` and inject favicon discovery into `FeedViewModel`.
- [x] Run focused tests and confirm they pass.

### Task 3: Sidebar Display

**Files:**
- Create: `Feedivo/Views/Sidebar/FeedRowView.swift`
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`

- [x] Replace the inline sidebar `Label` with `FeedRowView`.
- [x] Show `AsyncImage` favicons with RSS-symbol fallback.
- [x] Build the app.

### Task 4: Documentation, Verification, Commit

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/FEATURES.md`
- Modify: `docs/superpowers/plans/2026-06-20-favicon-discovery.md`

- [x] Mark favicons as implemented in `AGENTS.md`.
- [x] Mark favicons as implemented in `docs/FEATURES.md`.
- [x] Run `git diff --check`.
- [x] Run `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests`.
- [x] Run `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`.
- [x] Stage only project files, commit, and push to `main`.
