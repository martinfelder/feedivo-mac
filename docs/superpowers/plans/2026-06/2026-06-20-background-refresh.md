# Background Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add macOS-native automatic feed refresh with user settings for enablement and interval.

**Architecture:** Add a small testable settings/scheduling layer so interval clamping and earliest-run calculation are verified without relying on macOS background execution. Apple `BGTaskScheduler` is unavailable for native macOS targets in the current SDK, so use `NSBackgroundActivityScheduler` as the macOS-native scheduler while keeping the existing `FeedViewModel.refreshAllFeeds(_:context:)` path for actual refresh work. Wire scheduling through `FeedivoApp`, and expose enablement plus interval in `SettingsView`.

**Tech Stack:** SwiftUI `@AppStorage`, SwiftData `ModelContainer`, `NSBackgroundActivityScheduler`, Swift Testing, String Catalog localization.

---

### Task 1: Testable Background Refresh Configuration

**Files:**
- Create: `Feedivo/Services/BackgroundRefreshSettings.swift`
- Create: `FeedivoTests/BackgroundRefreshSettingsTests.swift`

- [x] Add failing tests for interval clamping and earliest begin date calculation.
- [x] Run focused settings tests and confirm they fail because `BackgroundRefreshSettings` does not exist.
- [x] Implement `BackgroundRefreshSettings` with shared storage keys, allowed intervals, default disabled state, interval clamping, and earliest begin date calculation.
- [x] Run focused settings tests and confirm they pass.

### Task 2: Background Refresh Service

**Files:**
- Create: `Feedivo/Services/BackgroundRefreshService.swift`
- Create: `FeedivoTests/BackgroundRefreshServiceTests.swift`
- Modify: `Feedivo/ViewModels/FeedViewModel.swift`

- [x] Add failing tests that verify a disabled refresh does not schedule and an enabled refresh schedules the task identifier with the expected earliest begin date.
- [x] Run focused service tests and confirm they fail because `BackgroundRefreshService` does not exist.
- [x] Implement a small scheduler protocol and `BackgroundRefreshService.scheduleNextRefresh(...)`.
- [x] Add the real `NSBackgroundActivityScheduler` adapter for macOS.
- [x] Run focused service tests and confirm they pass.

### Task 3: App And Settings Wiring

**Files:**
- Modify: `Feedivo/App/FeedivoApp.swift`
- Modify: `Feedivo/Views/Settings/SettingsView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

- [x] Wire `FeedivoApp` to create one shared SwiftData `ModelContainer`, schedule automatic refresh on app start, and reschedule when settings change.
- [x] Add settings controls for automatic refresh enablement and interval.
- [x] Add localized settings strings for de/en/fr/it.
- [x] Run focused tests and build.

### Task 4: Documentation, Verification, Commit

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/FEATURES.md`
- Modify: `docs/superpowers/plans/2026-06-20-background-refresh.md`

- [x] Mark automatic refresh as implemented in `AGENTS.md`.
- [x] Mark automatic refresh as implemented in `docs/FEATURES.md` and keep remaining M2 work current.
- [x] Run `git diff --check`.
- [x] Run `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests`.
- [x] Run `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`.
- [x] Stage only project files, commit, and push to `main`.
