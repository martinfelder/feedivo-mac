# Reader Font Presets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add configurable title/body font presets plus body text size, separate title/body line spacing and configurable article width for the native Reader.

**Architecture:** Use `ReaderFontPreset` for preset resolution, bundled font filenames and SwiftUI font creation. Use `ReaderFontRegistry` to register bundled TTF files at app startup. Use `ReaderTypography` for defaults and clamped ranges. Store title/body choices, body text size, separate title/body line spacing and article width with `@AppStorage`, expose them in a Reader toolbar popover and in Settings.

**Tech Stack:** SwiftUI, AppStorage, Xcode String Catalog, Swift Testing.

---

### Task 1: Preset Model

**Files:**
- Create: `Feedivo/Views/Reader/ReaderFontPreset.swift`
- Create: `Feedivo/Views/Reader/ReaderFontRegistry.swift`
- Create: `Feedivo/Views/Reader/ReaderTypography.swift`
- Modify: `FeedivoTests/FeedivoTests.swift`

- [x] Add tests for raw-value fallback, required font list, PostScript candidates and typography clamping.
- [x] Add tests for article-width clamping.
- [x] Implement `ReaderFontPreset` with the screenshot font list.
- [x] Bundle Regular/Variable TTF files for the curated custom fonts.
- [x] Register bundled fonts at app startup.
- [x] Implement `ReaderTypography` defaults and clamped ranges.
- [x] Verify focused tests pass.

### Task 2: Reader UI

**Files:**
- Modify: `Feedivo/Views/Reader/ReaderView.swift`

- [x] Add `@AppStorage` values for title/body presets.
- [x] Apply title preset to title text and body preset to paragraph text.
- [x] Add toolbar `textformat` button with popover, two pickers, text-size slider and line-spacing slider.
- [x] Add separate title line-spacing storage, slider and title text rendering.
- [x] Add article-width storage, slider and Reader frame binding.
- [x] Apply the body font preset to the metadata line above the title.
- [x] Force font pickers to menu style so the long curated list is shown consistently.

### Task 3: Settings and Localization

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

- [x] Add Settings pickers under Reading.
- [x] Add Settings sliders for text size and line spacing under Reading.
- [x] Add Settings slider for title line spacing under Reading.
- [x] Add Settings slider for article width under Reading.
- [x] Add localized labels for de/en/fr/it.

### Task 4: Documentation and Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/FEATURES.md`

- [x] Update project memory and roadmap.
- [x] Run unit tests and build.
