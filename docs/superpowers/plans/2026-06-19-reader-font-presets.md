# Reader Font Presets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add configurable title and body font presets for the native Reader.

**Architecture:** Create a small `ReaderFontPreset` enum for preset resolution and SwiftUI font design mapping. Store title/body choices with `@AppStorage`, expose them in a Reader toolbar popover and in Settings.

**Tech Stack:** SwiftUI, AppStorage, Xcode String Catalog, Swift Testing.

---

### Task 1: Preset Model

**Files:**
- Create: `Feedivo/Views/Reader/ReaderFontPreset.swift`
- Modify: `FeedivoTests/FeedivoTests.swift`

- [x] Add tests for raw-value fallback and labels.
- [x] Implement `ReaderFontPreset`.
- [x] Verify focused tests pass.

### Task 2: Reader UI

**Files:**
- Modify: `Feedivo/Views/Reader/ReaderView.swift`

- [x] Add `@AppStorage` values for title/body presets.
- [x] Apply title preset to title text and body preset to paragraph text.
- [x] Add toolbar `textformat` button with popover and two pickers.

### Task 3: Settings and Localization

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

- [x] Add Settings pickers under Reading.
- [x] Add localized labels for de/en/fr/it.

### Task 4: Documentation and Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/FEATURES.md`

- [x] Update project memory and roadmap.
- [x] Run unit tests and build.
