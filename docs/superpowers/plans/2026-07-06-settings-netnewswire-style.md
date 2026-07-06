# Einstellungen im NetNewsWire-Stil Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Feedivos Einstellungsfenster wird optisch an NetNewsWires Preferences-Fenster angeglichen: schmaler, ohne Karten/Eyebrow-Großschrift, mit automatischer Fensterhöhenanpassung statt Scrollen.

**Architecture:** Da alle 7 Einstellungs-Reiter ausschließlich über die zwei gemeinsamen Bausteine `NewSettingsBlock` und `NewSettingRow` gerendert werden (42 Verwendungsstellen insgesamt in `Feedivo/Views/Settings/SettingsView.swift`), reicht es, diese zwei Bausteine plus die Fenster-/Scene-Ebene umzubauen — keine der 7 einzelnen Reiter-Dateien muss inhaltlich angefasst werden. Reine SwiftUI-Layout-Änderung, keine neue Business-Logik.

**Tech Stack:** SwiftUI (macOS 14+), `.windowResizability(.contentSize)` (verfügbar ab macOS 13) als SwiftUI-native Entsprechung zu NetNewsWires manuellem `NSWindow`-Resizing.

## Global Constraints

- Referenz ist der tatsächliche NetNewsWire-Quellcode (`Mac/Preferences/PreferencesWindowController.swift`, `Mac/Preferences/General/GeneralPreferencesViewController.swift`).
- Die bestehenden 7 Reiter (Allgemein/Darstellung/Mitteilungen/Refresh/Cleanup/Sync/Info) bleiben inhaltlich unverändert — keine Umsortierung.
- Fensterbreite sinkt von 680 auf 512pt; Höhe passt sich automatisch pro Reiter an (kein Scrollen mehr).
- Zeilen-Layout: rechtsbündiges Label + linksbündiges Steuerelement; Beschreibungstext bleibt erhalten, wird aber kleiner/dezenter unter dem Control platziert (nicht entfernt).
- Große Eyebrow-Überschriften (Uppercase/Bold/Tracking) und Karten-Trennlinien entfallen; Gruppierung nur noch über Abstand.
- `NewInfoRow` (Info-Seite) wird in diesem Zug nicht angepasst.

---

### Task 1: Gemeinsame Bausteine `NewSettingsBlock` und `NewSettingRow` umbauen

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift:122-145` (`NewSettingsBlock`)
- Modify: `Feedivo/Views/Settings/SettingsView.swift:147-173` (`NewSettingRow`)
- Modify: `Feedivo/Views/Settings/SettingsView.swift:402` (Aufruf `NewSettingsBlock(eyebrow: L10n.settingsReadingSection, showsBottomDivider: false)`)
- Modify: `Feedivo/Views/Settings/SettingsView.swift:478` (Aufruf `NewSettingsBlock(eyebrow: L10n.settingsCacheSection, showsBottomDivider: false)`)
- Modify: `Feedivo/Views/Settings/SettingsView.swift:844` (Aufruf `NewSettingsBlock(eyebrow: "Alte Artikel", showsBottomDivider: false)`)

**Interfaces:**
- Consumes: nichts Neues — beide Typen bleiben `private struct`, nur innerhalb derselben Datei verwendet.
- Produces: `NewSettingsBlock<Content: View>(eyebrow: LocalizedStringKey, content: () -> Content)` (Parameter `showsBottomDivider` entfällt), `NewSettingRow<Control: View>(title: LocalizedStringKey, description: LocalizedStringKey, control: () -> Control)` (Signatur unverändert, nur das Rendering ändert sich) — alle 42 bestehenden Aufrufstellen in den 7 Reiter-Views bleiben dadurch unverändert kompilierbar.

- [ ] **Step 1: `NewSettingsBlock` umbauen — Eyebrow entstylen, Divider entfernen**

Aktuellen Code (Zeilen 122–145) ersetzen:

```swift
private struct NewSettingsBlock<Content: View>: View {
    let eyebrow: LocalizedStringKey
    var showsBottomDivider = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.7)

            content
        }
        .padding(.bottom, 22)
        .overlay(alignment: .bottom) {
            if showsBottomDivider {
                Divider()
            }
        }
        .padding(.bottom, 24)
    }
}
```

durch:

```swift
private struct NewSettingsBlock<Content: View>: View {
    let eyebrow: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            content
        }
        .padding(.bottom, 16)
    }
}
```

- [ ] **Step 2: `NewSettingRow` umbauen — rechtsbündiges Label, Beschreibung als dezente Notiz unter dem Control**

Aktuellen Code (Zeilen 147–173, direkt im Anschluss an den in Step 1 ersetzten Block) ersetzen:

```swift
private struct NewSettingRow<Control: View>: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer(minLength: 0)
                control
            }
            .frame(width: 310, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

durch:

```swift
private struct NewSettingRow<Control: View>: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    @ViewBuilder let control: Control

    private static var labelColumnWidth: CGFloat { 190 }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: Self.labelColumnWidth, alignment: .trailing)

                control

                Spacer(minLength: 0)
            }

            Text(description)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, Self.labelColumnWidth + 12)
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 3: Die drei `showsBottomDivider: false`-Aufrufe anpassen**

In `Feedivo/Views/Settings/SettingsView.swift` an den drei Stellen (Zeilen 402, 478, 844) jeweils `, showsBottomDivider: false` aus dem `NewSettingsBlock(...)`-Aufruf entfernen:

Zeile 402, vorher:
```swift
            NewSettingsBlock(eyebrow: L10n.settingsReadingSection, showsBottomDivider: false) {
```
nachher:
```swift
            NewSettingsBlock(eyebrow: L10n.settingsReadingSection) {
```

Zeile 478, vorher:
```swift
            NewSettingsBlock(eyebrow: L10n.settingsCacheSection, showsBottomDivider: false) {
```
nachher:
```swift
            NewSettingsBlock(eyebrow: L10n.settingsCacheSection) {
```

Zeile 844, vorher:
```swift
            NewSettingsBlock(eyebrow: "Alte Artikel", showsBottomDivider: false) {
```
nachher:
```swift
            NewSettingsBlock(eyebrow: "Alte Artikel") {
```

- [ ] **Step 4: Bauen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **` (schlägt fehl, falls noch eine vierte Aufrufstelle `showsBottomDivider` nutzt, die hier übersehen wurde — dann meldet der Compiler "extra argument 'showsBottomDivider' in call" mit der exakten Zeile)

- [ ] **Step 5: Manuell verifizieren**

App starten, Einstellungen öffnen (Cmd+,), jeden der 7 Reiter durchklicken:
- Labels stehen jetzt rechtsbündig links vom jeweiligen Steuerelement.
- Beschreibungstext ist kleiner/grauer und steht unter dem Steuerelement, nicht mehr neben dem Titel.
- Keine Großschrift-Überschriften mehr, keine Trennlinien zwischen den Blöcken — nur Abstand.
- Fenster ist noch nicht schmaler/nicht automatisch höhenangepasst — das kommt in Task 2.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Settings/SettingsView.swift
git commit -m "Einstellungen: NewSettingsBlock/NewSettingRow im NetNewsWire-Formular-Stil"
```

---

### Task 2: Fenster verschmälern, automatische Höhenanpassung statt Scrollen

**Files:**
- Modify: `Feedivo/App/FeedivoApp.swift:129-137` (`Settings { }`-Szene)
- Modify: `Feedivo/Views/Settings/SettingsView.swift:65-99` (`NewSettingsView.body` und `settingsTab(_:)`)

**Interfaces:**
- Consumes: `NewSettingsBlock`/`NewSettingRow` aus Task 1 (unverändert in ihrer öffentlichen Nutzung durch die 7 Reiter-Views).
- Produces: nichts weiter, terminale UI-Änderung.

- [ ] **Step 1: Settings-Szene auf `.windowResizability(.contentSize)` umstellen**

In `Feedivo/App/FeedivoApp.swift` den Block (Zeilen 129–137) ersetzen:

```swift
        Settings {
            NewSettingsView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .environment(databaseLoadState)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
        }
        .defaultSize(width: 680, height: 560)
```

durch:

```swift
        Settings {
            NewSettingsView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .environment(databaseLoadState)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
        }
        .windowResizability(.contentSize)
```

- [ ] **Step 2: `NewSettingsView` — ScrollView entfernen, feste Breite 512, Inhalt meldet eigene Höhe**

In `Feedivo/Views/Settings/SettingsView.swift` den Block (Zeilen 53–99) ersetzen:

```swift
struct NewSettingsView: View {
    static let windowID = "feedivo-settings-new"

    private enum Layout {
        static let windowWidth: CGFloat = 680
        static let windowHeight: CGFloat = 560
        static let contentWidth: CGFloat = 520
    }

    @Environment(\.interfaceTextSize) private var interfaceTextSize
    @State private var selectedSection = NewSettingsSection.general

    var body: some View {
        TabView(selection: $selectedSection) {
            settingsTab(.general)
            settingsTab(.appearance)
            settingsTab(.notifications)
            settingsTab(.refresh)
            settingsTab(.cleanup)
            settingsTab(.sync)
            settingsTab(.about)
        }
        .font(.system(size: 12))
        .controlSize(.small)
        .frame(
            minWidth: Layout.windowWidth,
            idealWidth: Layout.windowWidth,
            minHeight: Layout.windowHeight,
            idealHeight: Layout.windowHeight
        )
    }

    @ViewBuilder
    private func settingsTab(_ section: NewSettingsSection) -> some View {
        ScrollView {
            settingsContent(for: section)
                .frame(maxWidth: Layout.contentWidth, alignment: .topLeading)
                .padding(.horizontal, 64)
                .padding(.vertical, 34)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .tabItem {
            Label(section.title, systemImage: section.systemImage)
        }
        .tag(section)
    }
```

durch:

```swift
struct NewSettingsView: View {
    static let windowID = "feedivo-settings-new"

    private enum Layout {
        static let windowWidth: CGFloat = 512
    }

    @Environment(\.interfaceTextSize) private var interfaceTextSize
    @State private var selectedSection = NewSettingsSection.general

    var body: some View {
        TabView(selection: $selectedSection) {
            settingsTab(.general)
            settingsTab(.appearance)
            settingsTab(.notifications)
            settingsTab(.refresh)
            settingsTab(.cleanup)
            settingsTab(.sync)
            settingsTab(.about)
        }
        .font(.system(size: 12))
        .controlSize(.small)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: Layout.windowWidth)
    }

    @ViewBuilder
    private func settingsTab(_ section: NewSettingsSection) -> some View {
        settingsContent(for: section)
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor))
            .tabItem {
                Label(section.title, systemImage: section.systemImage)
            }
            .tag(section)
    }
```

- [ ] **Step 3: Bauen**

Run: `xcodebuild -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manuell verifizieren**

App starten, Einstellungen öffnen (Cmd+,):
- Fenster ist jetzt 512pt breit statt 680pt.
- Beim Wechsel zwischen den 7 Reitern passt sich die Fensterhöhe automatisch an den jeweiligen Inhalt an, kein Scrollbalken mehr sichtbar (sofern der Bildschirm hoch genug ist, um den höchsten Reiter ganz darzustellen).

**Bekanntes Risiko:** `TabView` + `.windowResizability(.contentSize)` passt die Fensterhöhe in manchen SwiftUI-Versionen nicht bei jedem Reiter-Wechsel neu an, sondern behält die Höhe des zuerst dargestellten oder des größten Reiters bei. Falls das beim Testen auffällt (Fenster wird beim Reiter-Wechsel nicht kleiner, obwohl der neue Reiter weniger Inhalt hat): `.id(selectedSection)` an die `TabView` in `NewSettingsView.body` anhängen (erzwingt einen Re-Layout-Zyklus pro Reiter-Wechsel). Falls das nötig ist, als zusätzlichen Fix-Schritt dokumentieren, nicht stillschweigend einbauen ohne es zu testen.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/App/FeedivoApp.swift Feedivo/Views/Settings/SettingsView.swift
git commit -m "Einstellungen: Fenster auf 512pt verschmälert, automatische Hoehenanpassung statt Scrollen"
```

---

## Self-Review

**Spec coverage:** Die Spec fordert (1) Fenster schmaler + automatische Höhenanpassung, (2) 7 Reiter unverändert, (3) rechtsbündiges Formular-Layout mit dezenterer Beschreibung, (4) Wegfall von Eyebrow-Großschrift und Karten-Trennlinien, (5) `NewInfoRow` bleibt unangetastet. Task 1 deckt (3), (4) und (5, durch Nicht-Anfassen) ab; Task 2 deckt (1) und (2, durch Nicht-Anfassen der Reiter-Struktur) ab. Keine Lücke gefunden.

**Placeholder-Scan:** Keine TBD/TODO, vollständiger Code in jedem Schritt.

**Typ-Konsistenz:** `NewSettingsBlock<Content: View>(eyebrow:content:)` und `NewSettingRow<Control: View>(title:description:control:)` behalten ihre öffentliche Aufruf-Signatur (bis auf den entfallenden `showsBottomDivider`-Parameter, dessen einzige 3 Nutzungsstellen in Task 1 Step 3 mitkorrigiert werden) — alle anderen 39 Aufrufstellen in den 7 Reiter-Views bleiben unverändert kompilierbar, da sie `showsBottomDivider` nie gesetzt hatten.
