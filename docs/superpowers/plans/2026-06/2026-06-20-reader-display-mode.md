# Reader Display Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add a global reader display mode so users can choose between Feedivo's native SwiftUI reader and the original article in a WebView.

**Architecture:** Store the global mode in `@AppStorage("readerDisplayMode")` using a small `ReaderDisplayMode` enum. `ReaderView` stays the detail entry point and switches between the existing native reader body and a new `WebContentView` when the mode is `.web` and the article has a valid URL.

**Tech Stack:** SwiftUI, WebKit (`WKWebView` through `NSViewRepresentable`), `@AppStorage`, String Catalog localization, XCTest.

---

### Task 1: ReaderDisplayMode Model

**Files:**
- Create: `Feedivo/Views/Reader/ReaderDisplayMode.swift`
- Test: `FeedivoTests/ReaderDisplayModeTests.swift`

- [x] **Step 1: Write the failing tests**

Create `FeedivoTests/ReaderDisplayModeTests.swift`:

```swift
import XCTest
@testable import Feedivo

final class ReaderDisplayModeTests: XCTestCase {
    func testDefaultModeIsNative() {
        XCTAssertEqual(ReaderDisplayMode.defaultMode, .native)
    }

    func testResolvedFallsBackToNativeForUnknownRawValue() {
        XCTAssertEqual(ReaderDisplayMode.resolved(from: "unknown"), .native)
    }

    func testResolvedReturnsWebForWebRawValue() {
        XCTAssertEqual(ReaderDisplayMode.resolved(from: ReaderDisplayMode.web.rawValue), .web)
    }
}
```

- [x] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ReaderDisplayModeTests
```

Expected: compile fails because `ReaderDisplayMode` does not exist yet.

- [x] **Step 3: Implement the enum**

Create `Feedivo/Views/Reader/ReaderDisplayMode.swift`:

```swift
import SwiftUI

enum ReaderDisplayMode: String, CaseIterable, Identifiable {
    case native
    case web

    static let storageKey = "readerDisplayMode"
    static let defaultMode = ReaderDisplayMode.native

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .native:
            return L10n.readerDisplayModeNative
        case .web:
            return L10n.readerDisplayModeWeb
        }
    }

    static func resolved(from rawValue: String) -> ReaderDisplayMode {
        ReaderDisplayMode(rawValue: rawValue) ?? defaultMode
    }
}
```

- [x] **Step 4: Run tests to verify they pass**

Run:

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ReaderDisplayModeTests
```

Expected: tests pass.

### Task 2: Localization

**Files:**
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

- [x] **Step 1: Add L10n constants**

Add to `L10n` near the other reader constants:

```swift
static let readerDisplayModePicker = LocalizedStringKey("reader.displayMode.picker")
static let readerDisplayModeNative = LocalizedStringKey("reader.displayMode.native")
static let readerDisplayModeWeb = LocalizedStringKey("reader.displayMode.web")
static var readerDisplayModeToggleHelp: String { String(localized: "reader.displayMode.toggle.help") }
```

- [x] **Step 2: Add String Catalog entries**

Add `reader.displayMode.picker`, `reader.displayMode.native`, `reader.displayMode.web`, and
`reader.displayMode.toggle.help` to `Feedivo/Resources/Localizable.xcstrings` for German,
English, French, and Italian.

Use these meanings:

- German: `Reader-Modus`, `Nativer Reader`, `Originalansicht`, `Reader-Modus wechseln`
- English: `Reader mode`, `Native reader`, `Original view`, `Switch reader mode`
- French: `Mode de lecture`, `Lecteur natif`, `Vue originale`, `Changer le mode de lecture`
- Italian: `Modalita lettore`, `Lettore nativo`, `Vista originale`, `Cambia modalita lettore`

- [x] **Step 3: Build to verify the catalog compiles**

Run:

```bash
xcodebuild build -scheme Feedivo -destination 'platform=macOS'
```

Expected: build succeeds.

### Task 3: WebContentView and Reader Switching

**Files:**
- Create: `Feedivo/Views/Reader/WebContentView.swift`
- Modify: `Feedivo/Views/Reader/ReaderView.swift`

- [x] **Step 1: Create the WebView wrapper**

Create `Feedivo/Views/Reader/WebContentView.swift`:

```swift
import SwiftUI
import WebKit

struct WebContentView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}
```

- [x] **Step 2: Add display mode storage and helper to ReaderView**

In `ReaderView`, add:

```swift
@AppStorage(ReaderDisplayMode.storageKey)
private var readerDisplayModeRawValue = ReaderDisplayMode.defaultMode.rawValue
```

Add helpers:

```swift
private var readerDisplayMode: ReaderDisplayMode {
    ReaderDisplayMode.resolved(from: readerDisplayModeRawValue)
}

private var originalURL: URL? {
    viewModel.originalURL(for: article)
}

private var shouldShowWebView: Bool {
    readerDisplayMode == .web && originalURL != nil
}
```

- [x] **Step 3: Split the existing native body**

Move the current `ScrollView` content into:

```swift
private var nativeReader: some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            // existing native reader content
        }
        .frame(maxWidth: clampedContentWidth, alignment: .leading)
        .padding()
    }
}
```

- [x] **Step 4: Switch body between native and web**

Change `body` to:

```swift
var body: some View {
    Group {
        if shouldShowWebView, let originalURL {
            WebContentView(url: originalURL)
        } else {
            nativeReader
        }
    }
    .navigationTitle(article.title)
    .toolbar {
        // existing toolbar plus Task 4 mode picker
    }
}
```

- [x] **Step 5: Build**

Run:

```bash
xcodebuild build -scheme Feedivo -destination 'platform=macOS'
```

Expected: build succeeds.

### Task 4: Settings Picker and Reader Toolbar Toggle

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift`
- Modify: `Feedivo/Views/Reader/ReaderView.swift`

- [x] **Step 1: Add the Settings picker**

In `SettingsView`, add:

```swift
@AppStorage(ReaderDisplayMode.storageKey)
private var readerDisplayModeRawValue = ReaderDisplayMode.defaultMode.rawValue
```

Inside `Section(L10n.settingsReadingSection)`, before font pickers, add:

```swift
Picker(L10n.readerDisplayModePicker, selection: $readerDisplayModeRawValue) {
    ForEach(ReaderDisplayMode.allCases) { mode in
        Text(mode.titleKey)
            .tag(mode.rawValue)
    }
}
.pickerStyle(.segmented)
```

- [x] **Step 2: Add Reader toolbar toggle**

In `ReaderView.toolbar`, add a toolbar item before the appearance button:

```swift
ToolbarItem {
    Picker(L10n.readerDisplayModePicker, selection: $readerDisplayModeRawValue) {
        ForEach(ReaderDisplayMode.allCases) { mode in
            Text(mode.titleKey)
                .tag(mode.rawValue)
        }
    }
    .pickerStyle(.segmented)
    .help(L10n.readerDisplayModeToggleHelp)
    .disabled(originalURL == nil)
}
```

- [x] **Step 3: Build**

Run:

```bash
xcodebuild build -scheme Feedivo -destination 'platform=macOS'
```

Expected: build succeeds.

### Task 5: Documentation and Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/FEATURES.md`

- [x] **Step 1: Update feature docs**

In `docs/FEATURES.md`, update `1.1 Anzeigemodus` from `Entschieden` to `Fertig als Basis`.
Document that the native reader remains the default, the Originalansicht is backed by
`WKWebView`, and the setting is global.

- [x] **Step 2: Update project memory**

In `AGENTS.md`, add the new completed M2/backlog item and a dated entry under `Letzte Änderungen`.

- [x] **Step 3: Run full verification**

Run:

```bash
git diff --check
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests
xcodebuild build -scheme Feedivo -destination 'platform=macOS'
```

Expected: no whitespace errors, tests pass, build succeeds.

- [x] **Step 4: Commit and push**

Run:

```bash
git add AGENTS.md docs/FEATURES.md Feedivo/Views/Reader/ReaderDisplayMode.swift Feedivo/Views/Reader/WebContentView.swift Feedivo/Views/Reader/ReaderView.swift Feedivo/Views/Settings/SettingsView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings FeedivoTests/ReaderDisplayModeTests.swift docs/superpowers/plans/2026-06-20-reader-display-mode.md
git commit -m "Add reader display mode"
git push origin main
```

Do not stage `Feedivo.xcodeproj/project.xcworkspace/xcuserdata/martinfelder.xcuserdatad/UserInterfaceState.xcuserstate`.
