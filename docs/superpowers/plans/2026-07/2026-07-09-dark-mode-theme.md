# Echtes Dark Mode Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App-interne Darstellungs-Einstellung (System/Hell/Dunkel) einführen und die zwei Stellen fixen, die heute nicht dark-mode-tauglich sind (First-Run-Assistent, Artikel-Metadaten-Inspector).

**Architecture:** Neues `AppAppearance`-Enum nach `AppLanguage`-Vorbild, gesteuert über `@AppStorage` + `.preferredColorScheme(...)` auf allen 5 Scenes in `FeedivoApp.swift`. Neues `FirstRunTheme` (eigenes Farb-Token-Struct nach `RuleDialogTheme`-Vorbild) ersetzt jedes hartcodierte `Color.white`/hartcodierte RGB im First-Run-Assistenten. Der Metadaten-Inspector bekommt einen einzeiligen Fix auf eine Systemsemantikfarbe.

**Tech Stack:** SwiftUI, `@AppStorage`, `ColorScheme`, Swift Testing (`@Test`/`#expect`, kein XCTest).

## Global Constraints

- Kommentare im Code auf Deutsch (Projektkonvention, siehe CLAUDE.md).
- `Localizable.xcstrings`-Änderungen NIEMALS per `json.dump`/Neuserialisierung — nur präzise, minimale Text-Einfügungen via Edit-Tool an der exakten Stelle, die im jeweiligen Task angegeben ist (sonst massiver Diff, siehe CLAUDE.md-Gotcha).
- Jede neue Migration/jeder neue Store-Zugriff entfällt hier (reine UI-/Settings-Änderung, keine SQLite-Schema-Änderung).
- Bekannte, dauerhaft vorbestehende Testfehlschläge (5 Tests in `FeedivoAppSceneConfigurationTests.swift`, 2 in `FeedViewModelTests.swift`) sind bereits bekannt — nicht neu einführen, aber auch nicht als eigenen Bug behandeln, falls sie beim Testlauf auftauchen.
- Gezielt testen: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -parallel-testing-enabled NO` (kein unscoped `xcodebuild test`, das hängt bekanntermassen).
- SourceKit-Diagnosen ("Cannot find type X in scope", "No such module 'GRDB'") nach Edits sind bekanntermassen oft veraltete/falsche Zustände — verlässlich ist nur ein echter `xcodebuild build`-Lauf.

---

### Task 1: AppAppearance-Einstellung (System/Hell/Dunkel)

**Files:**
- Create: `Feedivo/Resources/AppAppearance.swift`
- Modify: `Feedivo/App/FeedivoApp.swift`
- Modify: `Feedivo/Views/Settings/SettingsView.swift:214-215` (L10n-Aufrufer), `:318-374` (`NewAppearanceSettingsView`)
- Modify: `Feedivo/Resources/L10n.swift:214-215`
- Modify: `Feedivo/Resources/Localizable.xcstrings` (nach Zeile 19434, vor `"settings.articleList.feedNamePosition.description"`)
- Test: `FeedivoTests/FeedivoTests.swift:46` (nach `appLanguageLiefertLocaleUndFallback`)

**Interfaces:**
- Produziert: `enum AppAppearance: String, CaseIterable, Identifiable` mit `storageKey: String` (statisch), `defaultMode: AppAppearance` (statisch, `.system`), `titleKey: LocalizedStringKey`, `colorScheme: ColorScheme?`, `resolved(from rawValue: String) -> AppAppearance` (statisch).
- Wird konsumiert von: `FeedivoApp.swift` (`.preferredColorScheme(...)` auf allen 5 Scenes), `SettingsView.swift` (`NewAppearanceSettingsView`, neuer Picker).

> **Reihenfolge-Fix (Selbstreview 2026-07-09 17:02):** Die ursprüngliche
> Step-Reihenfolge legte `AppAppearance.swift` (mit Verweisen auf
> `L10n.settingsAppearanceMode*`) VOR die L10n-/xcstrings-Steps — das hätte
> einen Build-Fehler produziert, weil `titleKey` beim Kompilieren von
> `AppAppearance.swift` bereits auf Symbole verweist, die erst zwei Steps
> später entstehen. Fix: L10n-Keys und xcstrings-Einträge kommen jetzt ZUERST
> (Steps 1–2), danach `AppAppearance.swift` (Step 3) — dann kompiliert alles
> beim ersten Versuch.

- [ ] **Step 1: L10n-Keys ergänzen**

In `Feedivo/Resources/L10n.swift`, Zeile 214 (`static let settingsAppearanceSection = LocalizedStringKey("settings.appearance.section")`) — direkt danach, vor Zeile 215 (`settingsInterfaceTextSizePicker`), folgende 4 Zeilen einfügen:

```swift
    static let settingsAppearanceModePicker = LocalizedStringKey("settings.appearanceMode.picker")
    static let settingsAppearanceModeSystem = LocalizedStringKey("settings.appearanceMode.system")
    static let settingsAppearanceModeLight = LocalizedStringKey("settings.appearanceMode.light")
    static let settingsAppearanceModeDark = LocalizedStringKey("settings.appearanceMode.dark")
```

- [ ] **Step 2: Localizable.xcstrings — präzise Einfügung (NICHT per json.dump!)**

In `Feedivo/Resources/Localizable.xcstrings` gibt es aktuell (Zeile 19407) den Eintrag `"settings.appearance.section"`, der bei Zeile 19434 mit `},` endet, gefolgt von `"settings.articleList.feedNamePosition.description"` (Zeile 19435). Mit dem Edit-Tool exakt diesen Übergang matchen und die 4 neuen Einträge dazwischen einfügen:

Alter Text (exakt wie in der Datei, Zeilen 19427-19435):
```
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aspetto"
          }
        }
      }
    },
    "settings.articleList.feedNamePosition.description" : {
```

Neuer Text:
```
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aspetto"
          }
        }
      }
    },
    "settings.appearanceMode.dark" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Dunkel"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Dark"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Sombre"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Scuro"
          }
        }
      }
    },
    "settings.appearanceMode.light" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Hell"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Light"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Clair"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Chiaro"
          }
        }
      }
    },
    "settings.appearanceMode.picker" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Darstellung"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Appearance"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Apparence"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aspetto"
          }
        }
      }
    },
    "settings.appearanceMode.system" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "System"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "System"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Système"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Sistema"
          }
        }
      }
    },
    "settings.articleList.feedNamePosition.description" : {
```

Nach dem Edit: `git diff --stat Feedivo/Resources/Localizable.xcstrings` prüfen — erwartet eine kleine, lokal begrenzte Diff (nur die neu eingefügten Zeilen), NICHT eine Reformatierung der gesamten Datei. Falls der Diff riesig ist (>500 Zeilen), sofort `git checkout -- Feedivo/Resources/Localizable.xcstrings` und den Edit erneut, präziser versuchen.

- [ ] **Step 3: Neue Datei `AppAppearance.swift` anlegen**

```swift
import Foundation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appAppearance"
    static let defaultMode = AppAppearance.system

    var id: String { rawValue }

    // nil lässt SwiftUI/macOS die Systemeinstellung entscheiden (folgt
    // automatisch, wenn der Nutzer zwischen Hell/Dunkel wechselt).
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system:
            L10n.settingsAppearanceModeSystem
        case .light:
            L10n.settingsAppearanceModeLight
        case .dark:
            L10n.settingsAppearanceModeDark
        }
    }

    static func resolved(from rawValue: String) -> AppAppearance {
        AppAppearance(rawValue: rawValue) ?? defaultMode
    }
}
```

Da die L10n-Symbole aus Step 1 bereits existieren, kompiliert diese Datei sofort sauber (kein Verweis auf noch nicht existierende Symbole mehr).

- [ ] **Step 4: Build (Zwischenstand)**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Test schreiben**

In `FeedivoTests/FeedivoTests.swift`, direkt nach der bestehenden Funktion `appLanguageLiefertLocaleUndFallback()` (endet bei Zeile 46 mit `}`), folgenden neuen Test einfügen:

```swift

    @Test func appAppearanceLiefertColorSchemeUndFallback() {
        #expect(AppAppearance.resolved(from: "system").colorScheme == nil)
        #expect(AppAppearance.resolved(from: "light").colorScheme == .light)
        #expect(AppAppearance.resolved(from: "dark").colorScheme == .dark)
        #expect(AppAppearance.resolved(from: "unbekannt") == .system)
        #expect(AppAppearance.allCases.count == 3)
        #expect(AppAppearance.defaultMode == .system)
    }
```

- [ ] **Step 6: Test ausführen (erwartet: PASS)**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -parallel-testing-enabled NO 2>&1 | tail -30`
Expected: `appAppearanceLiefertColorSchemeUndFallback()` passed, `** TEST SUCCEEDED **`. Dank der korrigierten Reihenfolge (L10n/xcstrings vor `AppAppearance.swift`) gibt es hier keine Build-Fehler durch fehlende Symbole.

- [ ] **Step 7: `FeedivoApp.swift` verdrahten**

In `Feedivo/App/FeedivoApp.swift`, Zeile 6-7 (`@AppStorage("appLanguage") ...`) — direkt danach folgende neue Property einfügen:

```swift
    @AppStorage(AppAppearance.storageKey)
    private var appAppearanceRawValue = AppAppearance.defaultMode.rawValue
```

Dann in `var body: some Scene`, Zeile 54-56 (`let appLanguage = ...` / `let interfaceTextSize = ...`) — direkt danach eine dritte lokale Konstante ergänzen:

Alter Text:
```swift
    var body: some Scene {
        let appLanguage = AppLanguage.resolved(from: appLanguageRawValue)
        let interfaceTextSize = InterfaceTextSize.resolved(from: interfaceTextSizeRawValue)

        WindowGroup {
```

Neuer Text:
```swift
    var body: some Scene {
        let appLanguage = AppLanguage.resolved(from: appLanguageRawValue)
        let interfaceTextSize = InterfaceTextSize.resolved(from: interfaceTextSizeRawValue)
        let appAppearance = AppAppearance.resolved(from: appAppearanceRawValue)

        WindowGroup {
```

Dann auf allen 5 Scenes `.preferredColorScheme(appAppearance.colorScheme)` ergänzen (jeweils direkt nach `.dynamicTypeSize(interfaceTextSize.dynamicTypeSize)`):

1. Haupt-`WindowGroup` (Zeile 65 `.dynamicTypeSize(interfaceTextSize.dynamicTypeSize)`, danach `.toolbarBackground(...)`):

Alter Text:
```swift
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
```
Neuer Text:
```swift
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
                .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
```

2. Artikelsuchfenster (Zeile 106):

Alter Text:
```swift
                .environment(\.feedivoDatabase, feedivoDatabase)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
        }
        .defaultSize(width: 760, height: 560)
```
Neuer Text:
```swift
                .environment(\.feedivoDatabase, feedivoDatabase)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .defaultSize(width: 760, height: 560)
```

3. Organizer-Fenster (Zeile 115):

Alter Text:
```swift
                .environment(\.feedivoDatabase, feedivoDatabase)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
        }
        .defaultSize(width: 920, height: 620)
```
Neuer Text:
```swift
                .environment(\.feedivoDatabase, feedivoDatabase)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .defaultSize(width: 920, height: 620)
```

4. `WindowGroup(for: ArticleWindowRequest.self)` (Zeile 125):

Alter Text:
```swift
                    .environment(\.feedivoDatabase, feedivoDatabase)
                    .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
            } else {
```
Neuer Text:
```swift
                    .environment(\.feedivoDatabase, feedivoDatabase)
                    .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                    .preferredColorScheme(appAppearance.colorScheme)
            } else {
```

5. Settings (Zeile 142):

Alter Text:
```swift
                .environment(databaseLoadState)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
        }
        .windowResizability(.contentSize)
```
Neuer Text:
```swift
                .environment(databaseLoadState)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .windowResizability(.contentSize)
```

- [ ] **Step 8: Settings-UI ergänzen**

In `Feedivo/Views/Settings/SettingsView.swift`, in `NewAppearanceSettingsView` (Zeile 318) — neue `@AppStorage`-Property direkt nach Zeile 320 (`private var interfaceTextSizeRawValue = ...`) einfügen:

```swift
    @AppStorage(AppAppearance.storageKey)
    private var appAppearanceRawValue = AppAppearance.defaultMode.rawValue
```

Dann im `body`, im `NewSettingsBlock(eyebrow: "Oberfläche")` (Zeile 360) — als NEUE ERSTE `NewSettingRow` vor der bestehenden `settingsInterfaceTextSizePicker`-Zeile einfügen:

Alter Text:
```swift
            NewSettingsBlock(eyebrow: "Oberfläche") {
                NewSettingRow(
                    title: L10n.settingsInterfaceTextSizePicker,
```
Neuer Text:
```swift
            NewSettingsBlock(eyebrow: "Oberfläche") {
                NewSettingRow(
                    title: L10n.settingsAppearanceModePicker,
                    description: "Legt fest, ob Feedivo unabhängig von der macOS-Systemeinstellung immer hell oder immer dunkel dargestellt wird."
                ) {
                    Picker("", selection: $appAppearanceRawValue) {
                        ForEach(AppAppearance.allCases) { mode in
                            Text(mode.titleKey)
                                .tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                }

                NewSettingRow(
                    title: L10n.settingsInterfaceTextSizePicker,
```

- [ ] **Step 9: Build**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 10: Test erneut ausführen (PASS, inkl. neuem Test)**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -parallel-testing-enabled NO 2>&1 | tail -30`
Expected: `** TEST SUCCEEDED **`, `appAppearanceLiefertColorSchemeUndFallback()` unter den passed Tests.

- [ ] **Step 11: Commit**

```bash
git add Feedivo/Resources/AppAppearance.swift Feedivo/App/FeedivoApp.swift Feedivo/Views/Settings/SettingsView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings FeedivoTests/FeedivoTests.swift
git commit -m "Dark Mode: App-interne Darstellungs-Einstellung (System/Hell/Dunkel)"
```

---

### Task 2: FirstRunTheme — Dark-Palette für den First-Run-Assistenten

**Files:**
- Create: `Feedivo/Views/FirstRun/FirstRunTheme.swift`
- Modify: `Feedivo/Views/FirstRun/FirstRunWizardView.swift` (5 Structs: `FirstRunWizardView`, `FirstRunChoiceCard`, `FirstRunStepRow`, `FirstRunSettingsLine`, `FirstRunSegmentButtonStyle`)

**Interfaces:**
- Konsumiert: `Color(hex: UInt32)`-Extension aus `Feedivo/Views/Rules/RuleDialogTheme.swift:73-81` (bereits vorhanden, projektweit sichtbar, kein Import nötig).
- Produziert: `struct FirstRunTheme` mit `init(colorScheme: ColorScheme)`, Properties `card: Color`, `dropZoneBackground: Color`, `accentStroke: Color`. Jede der 5 betroffenen Structs in `FirstRunWizardView.swift` bekommt eine eigene `@Environment(\.colorScheme) private var colorScheme` + `private var theme: FirstRunTheme { FirstRunTheme(colorScheme: colorScheme) }`.

- [ ] **Step 1: `FirstRunTheme.swift` anlegen**

```swift
import SwiftUI

// Eigenes Dark-Mode-Farbschema für den First-Run-Assistenten, analog zu
// RuleDialogTheme (Verwaltung-Dialoge). Der Assistent hat einen bewusst
// hellen "Frosted-Glass"-Look (transluzente helle Karten auf einem
// Verlauf) — reines Color.white funktioniert dafür nur im Light Mode. Im
// Dark Mode braucht dieselbe Kartenoptik einen dunklen, leicht
// aufgehellten Ton statt striktem Weiss, sonst bleiben die Karten
// hell-verwaschene Fremdkörper auf dunklem Grund.
struct FirstRunTheme {
    let card: Color
    let dropZoneBackground: Color
    let accentStroke: Color

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            // Startwerte für die visuelle Abstimmung in Step 12 — die Spec
            // hat die exakten Dark-Töne bewusst offengelassen ("passt so",
            // Wahl erfolgt beim Umsetzen per Screenshot-Vergleich). Diese
            // Werte sind ein plausibler Ausgangspunkt, kein Endergebnis.
            card = Color(hex: 0x3A3A3D)
            dropZoneBackground = Color(hex: 0x223244)
            accentStroke = Color(hex: 0x6AB0FF)
        } else {
            card = Color.white
            dropZoneBackground = Color(red: 0.94, green: 0.97, blue: 1.0)
            accentStroke = Color(red: 0.18, green: 0.44, blue: 0.78)
        }
    }
}
```

- [ ] **Step 2: Build (Kompiliert bereits, kein Verhalten geändert)**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: `FirstRunWizardView` (Hauptstruct) verdrahten**

In `Feedivo/Views/FirstRun/FirstRunWizardView.swift`, Zeile 14 (`@Environment(\.feedivoDatabase) private var feedivoDatabase`) — direkt danach einfügen:

```swift
    @Environment(\.colorScheme) private var colorScheme
```

Und als computed property, z. B. direkt vor `private var tableBodyHeight` (Zeile 38), einfügen:

```swift
    private var theme: FirstRunTheme {
        FirstRunTheme(colorScheme: colorScheme)
    }

```

- [ ] **Step 4: Hauptstruct — alle 6 Stellen ersetzen**

Alle folgenden Ersetzungen sind innerhalb der Hauptstruct `FirstRunWizardView` (vor Zeile 1025):

a) Zeile 72 (Hintergrund-Gradient):
Alt: `                    Color.white.opacity(0.70),`
Neu: `                    theme.card.opacity(0.70),`

b) Zeile 82 (äusserer Rand):
Alt: `                .stroke(Color.white.opacity(0.72))`
Neu: `                .stroke(theme.card.opacity(0.72))`

Hinweis: Diese beiden Zeilen befinden sich im selben `LinearGradient`/`overlay`-Block (Zeilen ~69-84), zusammen mit klarem umliegendem Kontext eindeutig identifizierbar.

c) Zeile 377 (Feed-Eingabezeile-Karte):
Alt: `            .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 9))`
Neu: `            .background(theme.card.opacity(0.64), in: RoundedRectangle(cornerRadius: 9))`

d) Zeilen 401+404 (OPML-Drop-Zone, `opmlDropZone`):
Alt:
```swift
        .background(Color(red: 0.94, green: 0.97, blue: 1.0).opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.18, green: 0.44, blue: 0.78).opacity(0.42), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
```
Neu:
```swift
        .background(theme.dropZoneBackground.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.accentStroke.opacity(0.42), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
```

e) Zeilen 555 UND 639 (reviewSummaryCard + zweite identische Kartenfläche) — beide Stellen sind exakt derselbe Text `.background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 10))`. Mit dem Edit-Tool `replace_all: true` für genau diese Zeichenkette in dieser Datei verwenden (beide Stellen bekommen dieselbe Ersetzung):
Alt: `.background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 10))`
Neu: `.background(theme.card.opacity(0.68), in: RoundedRectangle(cornerRadius: 10))`

**Wichtig:** `replace_all: true` ersetzt in der GESAMTEN Datei jede exakte Übereinstimmung dieser Zeichenkette. Vor dem Ausführen per `grep -n "Color.white.opacity(0.68)" Feedivo/Views/FirstRun/FirstRunWizardView.swift` verifizieren, dass es GENAU 2 Treffer sind (Zeilen 555 und 639) und keine weiteren — falls mehr, Vorgehen stoppen und Kontext für Einzel-Edits verwenden.

f) Zeile 906 (Auswahlkarte im `defaultsStep`/Choice-Bereich):
Alt: `        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 10))`
Neu: `        .background(theme.card.opacity(0.62), in: RoundedRectangle(cornerRadius: 10))`

- [ ] **Step 5: Build**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: `FirstRunChoiceCard` verdrahten**

Zeile 1025-1026:
Alt:
```swift
private struct FirstRunChoiceCard: View {
    let iconName: String
```
Neu:
```swift
private struct FirstRunChoiceCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let iconName: String
```

Zeile 1062:
Alt: `            .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 10))`
Neu: `            .background(theme.card.opacity(0.64), in: RoundedRectangle(cornerRadius: 10))`

Computed property ergänzen, direkt vor `var body: some View` (Zeile 1031):
Alt:
```swift
    let action: () -> Void

    var body: some View {
```
Neu:
```swift
    let action: () -> Void

    private var theme: FirstRunTheme {
        FirstRunTheme(colorScheme: colorScheme)
    }

    var body: some View {
```

- [ ] **Step 7: `FirstRunStepRow` verdrahten**

Zeile 1128-1129:
Alt:
```swift
private struct FirstRunStepRow: View {
    let index: Int
```
Neu:
```swift
private struct FirstRunStepRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let index: Int
```

Computed property ergänzen, direkt vor `var body: some View` (Zeile 1134):
Alt:
```swift
    let isActive: Bool

    var body: some View {
```
Neu:
```swift
    let isActive: Bool

    private var theme: FirstRunTheme {
        FirstRunTheme(colorScheme: colorScheme)
    }

    var body: some View {
```

Zeile 1140:
Alt: `                .background(isActive ? Color.accentColor : Color.white.opacity(0.72), in: Circle())`
Neu: `                .background(isActive ? Color.accentColor : theme.card.opacity(0.72), in: Circle())`

- [ ] **Step 8: `FirstRunSettingsLine` verdrahten**

Zeile 1162-1163:
Alt:
```swift
private struct FirstRunSettingsLine<Accessory: View>: View {
    let title: String
```
Neu:
```swift
private struct FirstRunSettingsLine<Accessory: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
```

Computed property ergänzen, direkt vor `var body: some View` (Zeile 1167):
Alt:
```swift
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
```
Neu:
```swift
    @ViewBuilder let accessory: () -> Accessory

    private var theme: FirstRunTheme {
        FirstRunTheme(colorScheme: colorScheme)
    }

    var body: some View {
```

Zeile 1185:
Alt: `        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))`
Neu: `        .background(theme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))`

- [ ] **Step 9: `FirstRunSegmentButtonStyle` verdrahten**

Zeile 1193-1194:
Alt:
```swift
private struct FirstRunSegmentButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
```
Neu:
```swift
private struct FirstRunSegmentButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    let isActive: Bool

    private var theme: FirstRunTheme {
        FirstRunTheme(colorScheme: colorScheme)
    }

    func makeBody(configuration: Configuration) -> some View {
```

Zeilen 1202-1210:
Alt:
```swift
            .background(
                isActive
                    ? Color(red: 0.18, green: 0.44, blue: 0.78).opacity(configuration.isPressed ? 0.82 : 1)
                    : Color.white.opacity(configuration.isPressed ? 0.55 : 0.72),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isActive ? Color(red: 0.18, green: 0.44, blue: 0.78) : Color.secondary.opacity(0.14))
            )
```
Neu:
```swift
            .background(
                isActive
                    ? theme.accentStroke.opacity(configuration.isPressed ? 0.82 : 1)
                    : theme.card.opacity(configuration.isPressed ? 0.55 : 0.72),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isActive ? theme.accentStroke : Color.secondary.opacity(0.14))
            )
```

- [ ] **Step 10: Verifizieren, dass keine hartcodierten Stellen übrig sind**

Run: `grep -n "Color.white\|Color(red: 0.94, green: 0.97\|Color(red: 0.18, green: 0.44" Feedivo/Views/FirstRun/FirstRunWizardView.swift`
Expected: keine Treffer mehr (die `FirstRunTrafficDot`-Farben bei Zeile 119-121 und `Color.black.opacity(0.08)` bei Zeile 1123 sind bewusst NICHT Teil dieses Fixes — feste dekorative Ampel-Punkte bzw. Schatten-Rand, siehe Spec "Out of Scope" / Bestandsaufnahme).

- [ ] **Step 11: Build**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 12: Manuelle visuelle Verifikation (First-Run-Assistent erneut anzeigen)**

Der First-Run-Assistent erscheint nur, wenn `hasCompletedFirstRunWizard` (UserDefaults-Key aus `FirstRunWizardState.completionStorageKey` in `ContentView.swift`) `false` ist. Für den Test:

```bash
defaults write ch.martin.Feedivo hasCompletedFirstRunWizard -bool false
pkill -x Feedivo 2>/dev/null; sleep 1
open /Users/martinfelder/Library/Developer/Xcode/DerivedData/Feedivo-*/Build/Products/Debug/Feedivo.app
```

Per computer-use: App-Fenster screenshotten (Light Mode, macOS-Systemeinstellung), dann in Einstellungen → Anzeige die neue Darstellungs-Einstellung auf "Dunkel" stellen, App neu starten (`hasCompletedFirstRunWizard` erneut auf `false` setzen falls der Assistent beim ersten Test bereits durchlaufen/geschlossen wurde), erneut screenshotten. Prüfen: keine strahlend-weissen Kartenflächen mehr auf dunklem Grund, Text bleibt lesbar (Kontrast), Drop-Zone und aktiver Auswahl-Button zeigen die Dark-Varianten.

**Farbwahl ist hier bewusst noch nicht final (Spec-Entscheidung):** Falls die Startwerte aus Task 2 Step 1 (`0x3A3A3D`/`0x223244`/`0x6AB0FF`) optisch nicht überzeugen (zu dunkel/zu hell/zu wenig Kontrast zum Hintergrund-Verlauf) — direkt in `FirstRunTheme.swift` anpassen, `xcodebuild build` erneut laufen lassen und neu screenshotten, bis das Ergebnis passt. Das ist kein Abweichen vom Plan, sondern genau der von der Spec vorgesehene Auswahlprozess.

Nach dem Test: `defaults write ch.martin.Feedivo hasCompletedFirstRunWizard -bool true` (oder den Assistenten einmal reell durchklicken), damit der Nutzer beim nächsten normalen Start nicht ungewollt wieder im Onboarding landet.

- [ ] **Step 13: Commit**

```bash
git add Feedivo/Views/FirstRun/FirstRunTheme.swift Feedivo/Views/FirstRun/FirstRunWizardView.swift
git commit -m "Dark Mode: First-Run-Assistent bekommt eigenes Dark-Palette (FirstRunTheme)"
```

---

### Task 3: Metadaten-Inspector-Fix, FEATURES.md, finale Verifikation

**Files:**
- Modify: `Feedivo/Views/Reader/ArticleMetadataInspectorView.swift:4-6`
- Modify: `FEATURES.md`

**Interfaces:**
- Keine neuen Interfaces — reiner Farbwert-Austausch.

- [ ] **Step 1: Hintergrundfarbe austauschen**

Alt:
```swift
private enum SQLiteArticleInspectorStyle {
    static let background = Color(red: 0.94, green: 0.95, blue: 0.96)
}
```
Neu (Startwert — Spec hat die Wahl zwischen `.controlBackgroundColor` und
`.underPageBackgroundColor` bewusst offengelassen, endgültige Entscheidung
per visuellem Vergleich in Step 3):
```swift
private enum SQLiteArticleInspectorStyle {
    static let background = Color(nsColor: .controlBackgroundColor)
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manuelle visuelle Verifikation**

Per computer-use: Reader öffnen, Metadaten-Inspector einblenden (Toolbar-Button oder Cmd+I je nach Shortcut), einmal in Hell, einmal nach Umschalten der neuen Darstellungs-Einstellung auf Dunkel — Inspector-Panel darf kein helles Fremdkörper-Feld mehr sein, soll sich ins übrige (dunkle) Reader-Fenster einfügen.

**Farbwahl ist hier bewusst noch nicht final (Spec-Entscheidung):** Falls `.controlBackgroundColor` sich optisch nicht ausreichend vom Reader-Haupthintergrund absetzt (Spec-Kalkül: der Inspector soll leicht abgesetzt wirken, wie der bisherige fast-weisse Ton es in Light Mode tat), probeweise auf `Color(nsColor: .underPageBackgroundColor)` wechseln — die zweite von der Spec explizit vorgeschlagene Option —, neu bauen (`xcodebuild build`) und erneut vergleichen. Die überzeugendere Variante behalten. Danach Darstellungs-Einstellung zurück auf "System" stellen (Standardzustand für den Nutzer).

- [ ] **Step 4: Gezielter Testlauf (Regressionscheck)**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -parallel-testing-enabled NO 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: FEATURES.md aktualisieren**

In `FEATURES.md` einen neuen Abschnitt (an geeigneter Stelle im Phase-7/Einstellungen-Bereich, analog zu bestehenden Feature-19.x-Einträgen) ergänzen, der dokumentiert:
- Neue App-interne Darstellungs-Einstellung (System/Hell/Dunkel), `AppAppearance`, `.preferredColorScheme(...)` auf allen 5 Scenes.
- First-Run-Assistent bekam eigenes `FirstRunTheme` (analog `RuleDialogTheme`) für Dark Mode.
- Metadaten-Inspector-Hintergrund auf Systemsemantikfarbe umgestellt.
- Datum 2026-07-09, Verweis auf diesen Plan/die Spec (`docs/superpowers/specs/2026-07-09-dark-mode-theme-design.md`).

Exakte Formulierung und Platzierung im Datei-Kontext beim Umsetzen wählen (Datei vorher lesen, an bestehende Nummerierung/Konvention anschliessen).

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Reader/ArticleMetadataInspectorView.swift FEATURES.md
git commit -m "Dark Mode: Metadaten-Inspector-Hintergrund korrigiert, FEATURES.md aktualisiert"
```

---

## Self-Review (durchgeführt beim Schreiben dieses Plans)

- **Spec-Abdeckung:** Alle 3 Abschnitte aus der Spec (Architektur-Einstellung, First-Run-Dark-Palette, Inspector-Fix) sind auf je einen Task gemappt. ✅
- **Platzhalter-Scan:** Keine TBD/TODO. Die einzige bewusst offene Stelle (exakte Formulierung/Platzierung des FEATURES.md-Eintrags in Task 3 Step 5) ist kein Platzhalter im verbotenen Sinn, sondern eine Redaktions-Entscheidung, die von der Datei-Konvention vor Ort abhängt — analog zu früheren, bereits erfolgreich umgesetzten FEATURES.md-Updates in diesem Projekt.
- **Typkonsistenz:** `AppAppearance.storageKey`/`.defaultMode`/`.resolved(from:)`/`.titleKey`/`.colorScheme` konsistent über Task 1 hinweg verwendet. `FirstRunTheme.card`/`.dropZoneBackground`/`.accentStroke` konsistent über Task 2 hinweg verwendet, keine abweichenden Property-Namen zwischen den Steps.

## Zweite Review-Runde (2026-07-09, vor Freigabe an den Nutzer) — 3 Befunde, alle behoben

Ein zweiter Selbstreview-Durchlauf fand 3 Probleme, die in dieser Version des Plans bereits korrigiert sind:

1. **BESTÄTIGT — Build-Reihenfolge-Bug in Task 1:** `AppAppearance.swift` referenzierte `L10n.settingsAppearanceMode*`-Symbole, die erst zwei Steps später angelegt wurden — der als PASS erwartete Testlauf hätte stattdessen einen Build-Fehler produziert. **Fix:** Task 1 umsortiert — L10n-Keys (Step 1) und xcstrings (Step 2) kommen jetzt vor `AppAppearance.swift` (Step 3); Test schreiben/laufen lassen sind Steps 5–6, danach folgt Verdrahtung wie zuvor (Steps 7–11).
2. **PLAUSIBEL — Spec-Abweichung in Task 2:** Die hartcodierten Dark-Hex-Werte (`0x3A3A3D`/`0x223244`/`0x6AB0FF`) für `FirstRunTheme` widersprachen der expliziten Spec-Entscheidung, die exakten Farbwerte für die visuelle Abstimmung beim Umsetzen offenzulassen. **Fix:** Werte sind jetzt explizit als Startwerte kommentiert, Step 12 (visuelle Verifikation) enthält eine explizite Anweisung zur iterativen Anpassung per Screenshot-Vergleich.
3. **PLAUSIBEL — Spec-Abweichung in Task 3:** Die feste Wahl von `.controlBackgroundColor` für den Inspector-Hintergrund ignorierte, dass die Spec explizit zwischen dieser und `.underPageBackgroundColor` per visuellem Vergleich entscheiden wollte. **Fix:** `.controlBackgroundColor` ist jetzt als Startwert markiert, Step 3 (visuelle Verifikation) enthält eine explizite Anweisung, bei Bedarf auf `.underPageBackgroundColor` zu wechseln und zu vergleichen.

Dieser Plan ist damit bereit zur Ausführung (empfohlen: `superpowers:subagent-driven-development`, siehe Kopfzeile).
