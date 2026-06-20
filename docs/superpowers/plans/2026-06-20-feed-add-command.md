# Feed Add Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Feed > Feed hinzufügen...` with `Cmd+N` and make it open the same Add Feed sheet as the sidebar plus button.

**Architecture:** Lift the Add Feed sheet presentation state from `SidebarView` to `ContentView`, so both the sidebar button and the focused macOS command trigger the same sheet. Extend `FeedCommandActions` with an always-available add-feed action while keeping refresh/delete disabled without a selected feed.

**Tech Stack:** SwiftUI Commands, SwiftUI sheets, FocusedValues, Swift Testing.

---

### Task 1: Command Action Contract

**Files:**
- Test: `FeedivoTests/FeedCommandActionsTests.swift`
- Modify: `Feedivo/App/FeedCommandActions.swift`

- [x] Add a failing test that expects `FeedCommandActions` to expose an add-feed action that can run without a selected feed.
- [x] Add `requestAddFeed` and `canAddFeed` to `FeedCommandActions`.
- [x] Run the focused test and all unit tests.

### Task 2: UI Wiring

**Files:**
- Modify: `Feedivo/App/FeedCommands.swift`
- Modify: `Feedivo/Views/ContentView.swift`
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

- [x] Add localized `feed.add.command`.
- [x] Add `Feed hinzufügen...` with `Cmd+N` to the `Feed` menu.
- [x] Move sheet ownership to `ContentView`; sidebar plus and menu command both toggle the same state.
- [x] Run build and unit tests.

### Task 3: Documentation And Commit

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/FEATURES.md`

- [x] Mark `Cmd+N` feed add command as implemented.
- [x] Note remaining M2 work: all-feeds refresh, automatic refresh, favicons.
- [ ] Commit and push to `main`.
