# Smart Filters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add fixed Smart Filters in the sidebar for all articles, unread articles, starred articles, and today.

**Architecture:** Introduce a small `SmartFilter` model with testable article matching and a `SidebarSelection` enum so the sidebar can select either a smart filter or a concrete feed. Update `ArticleListView` to render either a feed-local list or a smart-filtered list across all stored articles. Keep the first version fixed and simple; no custom smart folders yet.

**Tech Stack:** SwiftUI `NavigationSplitView`/`List(selection:)`, SwiftData `@Query`, Swift Testing, String Catalog localization.

---

### Task 1: Smart Filter Logic

**Files:**
- Create: `Feedivo/Views/Sidebar/SmartFilter.swift`
- Create: `FeedivoTests/SmartFilterTests.swift`

- [x] Add failing tests for all, unread, starred, and today filter matching.
- [x] Run focused SmartFilter tests and confirm they fail because `SmartFilter` does not exist.
- [x] Implement `SmartFilter` with title keys, symbols, and article matching.
- [x] Run focused SmartFilter tests and confirm they pass.

### Task 2: Sidebar Selection

**Files:**
- Create: `Feedivo/Views/Sidebar/SidebarSelection.swift`
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`
- Modify: `Feedivo/Views/ContentView.swift`

- [x] Add `SidebarSelection` so a list row can represent a smart filter or a feed.
- [x] Add a Smart Filter section above feeds in the sidebar.
- [x] Update `ContentView` selection handling and clear selected article when the sidebar selection changes.
- [x] Build the app.

### Task 3: Article List Scopes

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleListView.swift`

- [x] Add feed and smart-filter scopes to `ArticleListView`.
- [x] Use all stored articles for smart filters and feed relationship articles for feed rows.
- [x] Keep existing article row actions and auto-read behavior.
- [x] Build the app.

### Task 4: Localization, Documentation, Verification, Commit

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Modify: `AGENTS.md`
- Modify: `docs/FEATURES.md`
- Modify: `docs/superpowers/plans/2026-06-20-smart-filters.md`

- [x] Add localized strings for de/en/fr/it.
- [x] Mark Smart Filters as implemented in `AGENTS.md`.
- [x] Mark Smart Filters as implemented in `docs/FEATURES.md`.
- [x] Run `git diff --check`.
- [x] Run `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests`.
- [x] Run `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`.
- [x] Stage only project files, commit, and push to `main`.
