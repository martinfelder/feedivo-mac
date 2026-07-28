# Language Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add a macOS Settings picker that lets users choose system language, German, English, French, or Italian.

**Architecture:** Add a small `AppLanguage` enum that maps persisted raw values to SwiftUI locales and localized picker labels. `FeedivoApp` applies the selected locale through the SwiftUI environment, while `SettingsView` stores the selection via `@AppStorage`.

**Tech Stack:** SwiftUI, `@AppStorage`, String Catalog, Swift Testing.

---

### Task 1: Language Selection Model

**Files:**
- Create: `Feedivo/Resources/AppLanguage.swift`
- Modify: `FeedivoTests/FeedivoTests.swift`

- [x] **Step 1: Write the failing test**

```swift
@Test func appLanguageLiefertLocaleUndFallback() {
    #expect(AppLanguage(rawValue: "de")?.localeIdentifier == "de")
    #expect(AppLanguage(rawValue: "en")?.localeIdentifier == "en")
    #expect(AppLanguage(rawValue: "fr")?.localeIdentifier == "fr")
    #expect(AppLanguage(rawValue: "it")?.localeIdentifier == "it")
    #expect(AppLanguage(rawValue: "system")?.localeIdentifier == nil)
    #expect(AppLanguage.resolved(from: "unbekannt") == .system)
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests/appLanguageLiefertLocaleUndFallback`

Expected: FAIL because `AppLanguage` does not exist.

- [x] **Step 3: Implement the model**

Create `AppLanguage` with cases `system`, `de`, `en`, `fr`, `it`, localized title keys, `localeIdentifier`, `locale`, and `resolved(from:)`.

- [x] **Step 4: Run test to verify it passes**

Run the same focused test. Expected: PASS.

### Task 2: Settings Picker And App Locale

**Files:**
- Modify: `Feedivo/App/FeedivoApp.swift`
- Modify: `Feedivo/Views/Settings/SettingsView.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

- [x] **Step 1: Add localized keys**

Add keys for the settings language section, picker label, and language names in all four supported languages.

- [x] **Step 2: Apply selected locale**

Read `@AppStorage("appLanguage")` in `FeedivoApp` and apply `AppLanguage.resolved(from: appLanguageRawValue).locale` to `ContentView()` and `SettingsView()`.

- [x] **Step 3: Add picker**

Add a `Picker` to `SettingsView` bound to `appLanguageRawValue`.

- [x] **Step 4: Verify**

Run `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'` and focused unit tests.

### Task 3: Documentation

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/FEATURES.md`

- [x] **Step 1: Document status**

Record that language selection is implemented and `Nach System` remains default.

- [x] **Step 2: Verify git status**

Run `git status --short --branch` and keep unrelated Xcode user-state changes out of commits.
