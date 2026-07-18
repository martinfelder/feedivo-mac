# Reader-Toolbar frei anpassbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nutzer können Reihenfolge und Sichtbarkeit der 14 Reader-Toolbar-Icons frei über einen neuen Settings-Tab "Toolbar" anpassen.

**Architektur:** Neues `ReaderToolbarItem`-Enum registriert alle 14 Toolbar-Elemente; eine `ReaderToolbarLayout`-Struct persistiert Reihenfolge + Sichtbarkeit als JSON-String in einem einzigen `@AppStorage`-Key (identisches Muster zu `KeyboardShortcutOverrides`); ein neuer Settings-Tab bietet eine `List` mit `.onMove`-Drag&Drop + Sichtbarkeits-Toggle pro Zeile; `SQLiteReaderView.readerToolbarContent` rendert die Icons dynamisch in der gespeicherten Reihenfolge, bleibt dabei aber technisch **eine einzige** `ToolbarItemGroup` (kein `.toolbar(id:)`).

**Tech Stack:** SwiftUI (macOS 14+), `@AppStorage` + JSON (Foundation `JSONEncoder`/`JSONDecoder`), Swift Testing (`import Testing`, `@Test`, `#expect`).

## Global Constraints

- Keine native `.toolbar(id:)`/`ToolbarItem(id:)`-Customization-API verwenden — dieser Ansatz wurde am 2026-07-10 bereits versucht und verworfen (siehe `FEATURES.md:884-886`).
- Die äußere `ToolbarItemGroup(placement: .primaryAction)` in `SQLiteReaderView.swift` bleibt **eine einzige** Gruppe — keine zusätzlichen, separat registrierten Toolbar-Items (bekannter `NSToolbar`-Icon-Overlap-Bug, siehe CLAUDE.md-Gotcha).
- Wo ein bestehender L10n-Key inhaltlich passt, diesen wiederverwenden statt einen neuen anzulegen (siehe Task 1 — 13 von 14 Labels sind bereits vorhanden).
- Neue Einträge in `Localizable.xcstrings` ausschließlich per reiner Text-Anker-Einfügung nach `"strings" : {` — niemals per vollem `json.load`/`json.dump`-Roundtrip (bekannter Formatierungs-Gotcha, siehe CLAUDE.md).
- Tests: Swift Testing (`import Testing`, `@testable import Feedivo`, `struct ...Tests`, `@Test func ...()`, `#expect(...)`), deutsche Testfunktionsnamen, analog bestehender Dateien wie `FeedivoTests/FeedLogRetentionSettingsTests.swift`.
- Build-Verifikation nach jedem Task: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`.
- Test-Verifikation gezielt (nie die volle Suite — bekanntes Hänge-Problem): `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/<SuiteName> -parallel-testing-enabled NO`.
- Kommentare im Code auf Deutsch (Projektkonvention).

---

### Task 1: `ReaderToolbarItem`-Enum (Datenmodell)

**Files:**
- Create: `Feedivo/Models/ReaderToolbarItem.swift`
- Test: `FeedivoTests/ReaderToolbarItemTests.swift`

**Interfaces:**
- Produces: `enum ReaderToolbarItem: String, CaseIterable, Identifiable, Sendable` mit 14 Fällen (`search, openOriginal, createRule, star, archive, toggleRead, copyLink, export, webBack, webForward, print, displayModePicker, appearance, inspector`), `var id: String`, `var label: Text`, `var systemImage: String`. Wird von Task 2 (`ReaderToolbarLayout`), Task 3 (Settings-Zeilen) und Task 4 (Toolbar-Rendering) konsumiert.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

Datei `FeedivoTests/ReaderToolbarItemTests.swift`:

```swift
import Testing
@testable import Feedivo

struct ReaderToolbarItemTests {
    @Test func allCasesHatVierzehnEindeutigeItems() {
        let rawValues = ReaderToolbarItem.allCases.map(\.rawValue)

        #expect(ReaderToolbarItem.allCases.count == 14)
        #expect(Set(rawValues).count == 14)
    }

    @Test func idEntsprichtRawValue() {
        for item in ReaderToolbarItem.allCases {
            #expect(item.id == item.rawValue)
        }
    }

    @Test func systemImageIstFuerJedesItemGesetzt() {
        for item in ReaderToolbarItem.allCases {
            #expect(item.systemImage.isEmpty == false)
        }
    }

    @Test func deklarationsreihenfolgeEntsprichtHeutigerStandardToolbarReihenfolge() {
        let expectedOrder: [ReaderToolbarItem] = [
            .search, .openOriginal, .createRule, .star, .archive, .toggleRead,
            .copyLink, .export, .webBack, .webForward, .print,
            .displayModePicker, .appearance, .inspector
        ]

        #expect(ReaderToolbarItem.allCases == expectedOrder)
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ReaderToolbarItemTests -parallel-testing-enabled NO`
Expected: FAIL — "Cannot find 'ReaderToolbarItem' in scope"

- [ ] **Step 3: Minimale Implementierung schreiben**

Datei `Feedivo/Models/ReaderToolbarItem.swift`:

```swift
import SwiftUI

/// Registry aller Icons/Controls der Reader-Toolbar, die der Nutzer im
/// Einstellungen-Tab "Toolbar" frei umsortieren und ein-/ausblenden kann
/// (Feature 19.4). Die Deklarationsreihenfolge der Fälle entspricht der
/// heutigen Standard-Anzeigereihenfolge in
/// `SQLiteReaderView.readerToolbarContent` und ist zugleich der
/// Auslieferungszustand von `ReaderToolbarLayout()`.
enum ReaderToolbarItem: String, CaseIterable, Identifiable, Sendable {
    case search
    case openOriginal
    case createRule
    case star
    case archive
    case toggleRead
    case copyLink
    case export
    case webBack
    case webForward
    case print
    case displayModePicker
    case appearance
    case inspector

    var id: String { rawValue }

    /// Neutrales, zustandsunabhängiges Label für die Einstellungen-Liste.
    /// 13 der 14 Fälle nutzen dafür bereits bestehende Shortcuts-/Reader-Labels
    /// (`shortcuts.label.*` sind bereits state-unabhängig formuliert, z. B.
    /// "Stern umschalten" statt "Stern hinzufügen"/"Stern entfernen").
    /// `.createRule` ist der einzige Fall mit einem `String(localized:)`-Key
    /// (`L10n.articleCreateRuleCommand`) statt `LocalizedStringKey` — `Text(String)`
    /// zeigt den bereits aufgelösten String unverändert an, `Text(LocalizedStringKey)`
    /// löst den Schlüssel selbst auf; beide Initializer-Aufrufe sind hier bewusst
    /// gemischt, um für alle 14 Fälle ohne neue xcstrings-Einträge auszukommen.
    var label: Text {
        switch self {
        case .search: Text(L10n.shortcutsLabelArticleSearch)
        case .openOriginal: Text(L10n.shortcutsLabelArticleOpenOriginal)
        case .createRule: Text(L10n.articleCreateRuleCommand)
        case .star: Text(L10n.shortcutsLabelArticleToggleStarred)
        case .archive: Text(L10n.shortcutsLabelArticleToggleArchived)
        case .toggleRead: Text(L10n.shortcutsLabelArticleToggleRead)
        case .copyLink: Text(L10n.shortcutsLabelArticleCopyLink)
        case .export: Text(L10n.shortcutsLabelArticleExport)
        case .webBack: Text(L10n.shortcutsLabelReaderWebBack)
        case .webForward: Text(L10n.shortcutsLabelReaderWebForward)
        case .print: Text(L10n.shortcutsLabelArticlePrint)
        case .displayModePicker: Text(L10n.readerDisplayModePicker)
        case .appearance: Text(L10n.readerAppearanceButton)
        case .inspector: Text(L10n.readerInspectorButton)
        }
    }

    var systemImage: String {
        switch self {
        case .search: "magnifyingglass"
        case .openOriginal: "safari"
        case .createRule: "slider.horizontal.3"
        case .star: "star"
        case .archive: "archivebox"
        case .toggleRead: "circle"
        case .copyLink: "link"
        case .export: "square.and.arrow.up"
        case .webBack: "chevron.backward"
        case .webForward: "chevron.forward"
        case .print: "printer"
        case .displayModePicker: "rectangle.2.swap"
        case .appearance: "textformat"
        case .inspector: "sidebar.right"
        }
    }
}
```

- [ ] **Step 4: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ReaderToolbarItemTests -parallel-testing-enabled NO`
Expected: PASS (4 Tests grün)

- [ ] **Step 5: Build verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Models/ReaderToolbarItem.swift FeedivoTests/ReaderToolbarItemTests.swift
git commit -m "Feature: ReaderToolbarItem-Registry fuer anpassbare Reader-Toolbar (Task 1/4)"
```

---

### Task 2: `ReaderToolbarLayout` (Persistenz)

**Files:**
- Create: `Feedivo/Services/ReaderToolbarSettings.swift`
- Test: `FeedivoTests/ReaderToolbarSettingsTests.swift`

**Interfaces:**
- Consumes: `ReaderToolbarItem: String, CaseIterable, Identifiable, Sendable` (Task 1) — insbesondere `ReaderToolbarItem.allCases`, `ReaderToolbarItem(rawValue:)`.
- Produces: `struct ReaderToolbarLayout: Equatable` mit `var order: [String]`, `var hiddenItemIDs: Set<String>`, `init(order:hiddenItemIDs:)` (Defaults = Auslieferungszustand), `static let storageKey: String`, `static func resolved(from rawValue: String) -> ReaderToolbarLayout`, `static func resetToDefault() -> ReaderToolbarLayout`, `var rawValue: String`, `var orderedItems: [ReaderToolbarItem]`, `var visibleOrderedItems: [ReaderToolbarItem]`, `mutating func move(fromOffsets: IndexSet, toOffset: Int)`, `mutating func setHidden(_ isHidden: Bool, for item: ReaderToolbarItem)`. Wird von Task 3 (Settings-View) und Task 4 (`SQLiteReaderView`) konsumiert.

- [ ] **Step 1: Fehlschlagenden Test schreiben**

Datei `FeedivoTests/ReaderToolbarSettingsTests.swift`:

```swift
import Testing
@testable import Feedivo

struct ReaderToolbarSettingsTests {
    @Test func defaultLayoutEnthaeltAlleItemsSichtbarInDeklarationsreihenfolge() {
        let layout = ReaderToolbarLayout()

        #expect(layout.orderedItems == ReaderToolbarItem.allCases)
        #expect(layout.visibleOrderedItems == ReaderToolbarItem.allCases)
        #expect(layout.hiddenItemIDs.isEmpty)
    }

    @Test func rawValueRundtripErhaeltReihenfolgeUndSichtbarkeit() {
        var layout = ReaderToolbarLayout()
        layout.move(fromOffsets: [3], toOffset: 0)
        layout.setHidden(true, for: .print)

        let restored = ReaderToolbarLayout.resolved(from: layout.rawValue)

        #expect(restored.order == layout.order)
        #expect(restored.hiddenItemIDs == layout.hiddenItemIDs)
    }

    @Test func resolvedLiefertDefaultBeiUngueltigemJSON() {
        let layout = ReaderToolbarLayout.resolved(from: "das ist kein JSON")

        #expect(layout == ReaderToolbarLayout())
    }

    @Test func setHiddenBlendetItemAusSichtbarerListeAusBleibtAberInOrderedItems() {
        var layout = ReaderToolbarLayout()
        layout.setHidden(true, for: .star)

        #expect(layout.visibleOrderedItems.contains(.star) == false)
        #expect(layout.orderedItems.contains(.star) == true)

        layout.setHidden(false, for: .star)
        #expect(layout.visibleOrderedItems.contains(.star) == true)
    }

    @Test func resolvedHaengtFehlendesItemSichtbarAnsEndeAn() {
        let allButInspector = ReaderToolbarItem.allCases
            .map(\.rawValue)
            .filter { $0 != ReaderToolbarItem.inspector.rawValue }
        let rawValue = "{\"order\":\(jsonArray(allButInspector)),\"hidden\":[]}"

        let layout = ReaderToolbarLayout.resolved(from: rawValue)

        #expect(layout.order.last == ReaderToolbarItem.inspector.rawValue)
        #expect(layout.visibleOrderedItems.contains(.inspector) == true)
    }

    @Test func resolvedEntferntUnbekannteVeralteteEintraege() {
        let rawValue = "{\"order\":[\"obsoleteItem\",\"search\"],\"hidden\":[]}"

        let layout = ReaderToolbarLayout.resolved(from: rawValue)

        #expect(layout.order.contains("obsoleteItem") == false)
        #expect(layout.orderedItems.count == ReaderToolbarItem.allCases.count)
    }

    @Test func resetToDefaultSetztAufAuslieferungszustandZurueck() {
        var layout = ReaderToolbarLayout()
        layout.setHidden(true, for: .print)
        layout.move(fromOffsets: [0], toOffset: 5)

        let reset = ReaderToolbarLayout.resetToDefault()

        #expect(reset == ReaderToolbarLayout())
    }

    private func jsonArray(_ values: [String]) -> String {
        "[" + values.map { "\"\($0)\"" }.joined(separator: ",") + "]"
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ReaderToolbarSettingsTests -parallel-testing-enabled NO`
Expected: FAIL — "Cannot find 'ReaderToolbarLayout' in scope"

- [ ] **Step 3: Minimale Implementierung schreiben**

Datei `Feedivo/Services/ReaderToolbarSettings.swift`:

```swift
import Foundation

/// Persistierte Reihenfolge und Sichtbarkeit der Reader-Toolbar-Icons
/// (Feature 19.4 "Toolbar anpassen"). Wird — analog zu
/// `KeyboardShortcutOverrides` — als JSON-codierter String in einem
/// einzigen `@AppStorage`-Key abgelegt statt in vielen Einzel-Keys.
struct ReaderToolbarLayout: Equatable {
    private struct StoredLayout: Codable {
        var order: [String]
        var hidden: [String]
    }

    var order: [String]
    var hiddenItemIDs: Set<String>

    init(
        order: [String] = ReaderToolbarItem.allCases.map(\.rawValue),
        hiddenItemIDs: Set<String> = []
    ) {
        self.order = order
        self.hiddenItemIDs = hiddenItemIDs
    }

    static let storageKey = "readerToolbarLayout"

    static func resolved(from rawValue: String) -> ReaderToolbarLayout {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(StoredLayout.self, from: data)
        else {
            return ReaderToolbarLayout()
        }

        return ReaderToolbarLayout(order: decoded.order, hiddenItemIDs: Set(decoded.hidden))
            .normalized()
    }

    static func resetToDefault() -> ReaderToolbarLayout {
        ReaderToolbarLayout()
    }

    var rawValue: String {
        let stored = StoredLayout(order: order, hidden: Array(hiddenItemIDs))
        guard let data = try? JSONEncoder().encode(stored),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return string
    }

    /// Alle Items in gespeicherter Reihenfolge inkl. ausgeblendeter — Grundlage
    /// für die Einstellungen-Liste, in der auch ausgeblendete Items sichtbar
    /// bleiben müssen, damit sie wieder eingeblendet werden können.
    var orderedItems: [ReaderToolbarItem] {
        order.compactMap { ReaderToolbarItem(rawValue: $0) }
    }

    /// Nur sichtbare Items in Reihenfolge — Grundlage für das tatsächliche
    /// Toolbar-Rendering in `SQLiteReaderView`.
    var visibleOrderedItems: [ReaderToolbarItem] {
        orderedItems.filter { !hiddenItemIDs.contains($0.rawValue) }
    }

    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var items = order
        items.move(fromOffsets: source, toOffset: destination)
        order = items
    }

    mutating func setHidden(_ isHidden: Bool, for item: ReaderToolbarItem) {
        if isHidden {
            hiddenItemIDs.insert(item.rawValue)
        } else {
            hiddenItemIDs.remove(item.rawValue)
        }
    }

    /// Hängt `ReaderToolbarItem`-Fälle, die noch nicht in `order` stehen (z. B.
    /// ein künftig neu hinzugefügtes Toolbar-Icon bei einem Bestandsnutzer),
    /// sichtbar ans Ende an, und entfernt unbekannte/veraltete Einträge aus
    /// `order` (z. B. ein in einer späteren Version wieder entferntes Icon).
    private func normalized() -> ReaderToolbarLayout {
        let knownRawValues = Set(ReaderToolbarItem.allCases.map(\.rawValue))
        var normalizedOrder = order.filter { knownRawValues.contains($0) }
        let present = Set(normalizedOrder)
        let missing = ReaderToolbarItem.allCases.map(\.rawValue).filter { !present.contains($0) }
        normalizedOrder.append(contentsOf: missing)

        return ReaderToolbarLayout(order: normalizedOrder, hiddenItemIDs: hiddenItemIDs)
    }
}
```

- [ ] **Step 4: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ReaderToolbarSettingsTests -parallel-testing-enabled NO`
Expected: PASS (7 Tests grün)

- [ ] **Step 5: Build verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Services/ReaderToolbarSettings.swift FeedivoTests/ReaderToolbarSettingsTests.swift
git commit -m "Feature: ReaderToolbarLayout-Persistenz fuer anpassbare Reader-Toolbar (Task 2/4)"
```

---

### Task 3: Settings-Tab "Toolbar"

**Files:**
- Modify: `Feedivo/Resources/L10n.swift:222` (nach `readerInspectorButton`)
- Modify: `Feedivo/Resources/Localizable.xcstrings:3` (Text-Anker-Einfügung nach `"strings" : {`)
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (mehrere Stellen: `SettingsSection`-Enum, `TabView`-Body, `settingsContent`-Switch, neue Views am Dateiende)

**Interfaces:**
- Consumes: `ReaderToolbarItem` (Task 1), `ReaderToolbarLayout` (Task 2) — insbesondere `ReaderToolbarLayout.storageKey`, `.resolved(from:)`, `.orderedItems`, `.hiddenItemIDs`, `.move(fromOffsets:toOffset:)`, `.setHidden(_:for:)`, `.resetToDefault()`.
- Produces: Neuer Tab „Toolbar" in `SettingsView`, keine neuen öffentlichen Swift-Symbole, die spätere Tasks brauchen (Task 4 ist unabhängig von dieser UI).

- [ ] **Step 1: Neuen L10n-Key ergänzen**

In `Feedivo/Resources/L10n.swift`, nach Zeile 222 (`static let readerInspectorButton = LocalizedStringKey("reader.inspector.button")`) einfügen:

```swift
    static let settingsReaderToolbarSection = LocalizedStringKey("settings.readerToolbar.section")
    static let readerToolbarResetButton = LocalizedStringKey("readerToolbar.reset.button")
```

(Zweiter Key exakt nach Spec-Wortlaut „Standard wiederherstellen" — bewusst ein eigener Key statt Wiederverwendung von `L10n.shortcutsResetAllButton` ("Alle zurücksetzen"), Nutzerentscheidung im Pre-Flight-Check vor Task-Start.)

- [ ] **Step 2: Neuen xcstrings-Eintrag per Text-Anker-Einfügung ergänzen**

**Nicht** `json.load`/`json.dump` auf die ganze Datei anwenden (siehe Global Constraints — reformatiert ~31000 Zeilen). Stattdessen:

```bash
python3 - <<'PYEOF'
path = "Feedivo/Resources/Localizable.xcstrings"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

anchor = '  "strings" : {\n'
assert content.count(anchor) == 1, "Anker nicht gefunden oder nicht eindeutig"

new_entry = '''    "settings.readerToolbar.section" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Toolbar"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Toolbar"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Barre d'outils"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Barra degli strumenti"
          }
        }
      }
    },
    "readerToolbar.reset.button" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Standard wiederherstellen"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Restore Defaults"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Restaurer les valeurs par défaut"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ripristina impostazioni predefinite"
          }
        }
      }
    },
'''

content = content.replace(anchor, anchor + new_entry, 1)

with open(path, "w", encoding="utf-8") as f:
    f.write(content)
PYEOF
```

Run: `git diff --stat Feedivo/Resources/Localizable.xcstrings`
Expected: nur Insertions (z. B. `1 file changed, 21 insertions(+)`), **keine** Deletions — sonst wurde versehentlich die ganze Datei reformatiert, dann Änderung verwerfen und Schritt wiederholen.

- [ ] **Step 3: Neuen Tab-Fall in `SettingsSection` ergänzen**

In `Feedivo/Views/Settings/SettingsView.swift`, Zeilen 3-13, `old_string`:

```swift
private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case articleList
    case menubar
    case shortcuts
    case notifications
```

`new_string`:

```swift
private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case articleList
    case menubar
    case shortcuts
    case readerToolbar
    case notifications
```

- [ ] **Step 4: `title`-Switch ergänzen**

`old_string`:

```swift
        case .shortcuts:
            L10n.shortcutsSettingsSection
        case .notifications:
            L10n.settingsNotificationsSection
```

`new_string`:

```swift
        case .shortcuts:
            L10n.shortcutsSettingsSection
        case .readerToolbar:
            L10n.settingsReaderToolbarSection
        case .notifications:
            L10n.settingsNotificationsSection
```

- [ ] **Step 5: `systemImage`-Switch ergänzen**

`old_string`:

```swift
        case .shortcuts:
            "keyboard"
        case .notifications:
            "bell.badge"
```

`new_string`:

```swift
        case .shortcuts:
            "keyboard"
        case .readerToolbar:
            "rectangle.3.group"
        case .notifications:
            "bell.badge"
```

- [ ] **Step 6: `TabView`-Body ergänzen**

`old_string`:

```swift
            settingsTab(.shortcuts)
            settingsTab(.notifications)
```

`new_string`:

```swift
            settingsTab(.shortcuts)
            settingsTab(.readerToolbar)
            settingsTab(.notifications)
```

- [ ] **Step 7: `settingsContent`-Switch ergänzen**

`old_string`:

```swift
        case .shortcuts:
            ShortcutsSettingsView()
        case .notifications:
            NotificationSettingsView()
```

`new_string`:

```swift
        case .shortcuts:
            ShortcutsSettingsView()
        case .readerToolbar:
            ReaderToolbarSettingsView()
        case .notifications:
            NotificationSettingsView()
```

- [ ] **Step 8: Neue Views am Dateiende ergänzen**

Die Datei endet aktuell mit `ShortcutSettingRow.reset()`. `old_string` (exakter Dateiabschluss):

```swift
    private func reset() {
        var updated = overrides
        updated.values.removeValue(forKey: shortcut.id)
        overridesRawValue = updated.rawValue
        conflictMessage = nil
    }
}
```

`new_string`:

```swift
    private func reset() {
        var updated = overrides
        updated.values.removeValue(forKey: shortcut.id)
        overridesRawValue = updated.rawValue
        conflictMessage = nil
    }
}

private struct ReaderToolbarSettingsView: View {
    @AppStorage(ReaderToolbarLayout.storageKey)
    private var toolbarLayoutRawValue = ReaderToolbarLayout().rawValue

    private var layout: ReaderToolbarLayout {
        ReaderToolbarLayout.resolved(from: toolbarLayoutRawValue)
    }

    var body: some View {
        SettingsBlock(eyebrow: L10n.settingsReaderToolbarSection) {
            List {
                ForEach(layout.orderedItems) { item in
                    ReaderToolbarSettingsRow(
                        item: item,
                        isVisible: !layout.hiddenItemIDs.contains(item.rawValue),
                        onToggleVisible: { toggleVisible(item) }
                    )
                }
                .onMove(perform: moveItems)
            }
            .listStyle(.inset)
            .frame(height: 360)

            Button(L10n.readerToolbarResetButton) {
                toolbarLayoutRawValue = ReaderToolbarLayout.resetToDefault().rawValue
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        var updated = layout
        updated.move(fromOffsets: source, toOffset: destination)
        toolbarLayoutRawValue = updated.rawValue
    }

    private func toggleVisible(_ item: ReaderToolbarItem) {
        var updated = layout
        updated.setHidden(!updated.hiddenItemIDs.contains(item.rawValue), for: item)
        toolbarLayoutRawValue = updated.rawValue
    }
}

private struct ReaderToolbarSettingsRow: View {
    let item: ReaderToolbarItem
    let isVisible: Bool
    let onToggleVisible: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.systemImage)
                .frame(width: 20)
                .foregroundStyle(isVisible ? Color.primary : Color.secondary)

            item.label
                .font(.system(size: 13))
                .foregroundStyle(isVisible ? Color.primary : Color.secondary)

            Spacer()

            Toggle(isOn: Binding(
                get: { isVisible },
                set: { _ in onToggleVisible() }
            )) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 9: Build verifizieren**

Kein automatisierter Test für diese View möglich (kein ViewInspector im Projekt, siehe CLAUDE.md-Gotcha). Verifikation ausschließlich per Build:

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 10: Commit**

```bash
git add Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings Feedivo/Views/Settings/SettingsView.swift
git commit -m "Feature: Settings-Tab 'Toolbar' fuer Reader-Toolbar-Reihenfolge/Sichtbarkeit (Task 3/4)"
```

---

### Task 4: Reader-Toolbar dynamisch rendern

**Files:**
- Modify: `Feedivo/Views/Reader/SQLiteReaderView.swift:71-89` (neue `@AppStorage` + computed property)
- Modify: `Feedivo/Views/Reader/SQLiteReaderView.swift:123-271` (`readerToolbarContent` + neue `toolbarItemView(for:)`-Methode)

**Interfaces:**
- Consumes: `ReaderToolbarItem` (Task 1), `ReaderToolbarLayout` (Task 2) — `ReaderToolbarLayout.storageKey`, `.resolved(from:)`, `.visibleOrderedItems`.
- Produces: Keine neuen öffentlichen Symbole — letzter Task, konsumiert nur.

- [ ] **Step 1: `@AppStorage` + computed property ergänzen**

In `Feedivo/Views/Reader/SQLiteReaderView.swift`, `old_string` (Zeilen 71-89):

```swift
    @AppStorage(KeyboardShortcutOverrides.storageKey)
    private var shortcutOverridesRawValue = KeyboardShortcutOverrides().rawValue

    // Der Artikelinfo-Inspector (ArticleMetadataInspectorView) mutiert Tags UND Ordner
    // direkt in SQLite (Tags -> SidebarBadgeInvalidation, Ordner -> SQLiteDataInvalidation)
    // und bumpt anschliessend den jeweiligen Zaehler, aktualisiert dabei aber nur seine
    // eigene lokale Snapshot-Kopie — nicht den `state.snapshot` dieser View, aus dem
    // readerArticleMetadata sowohl Tag-Chips als auch Ordnername im Artikel-Header
    // rendert. Ohne diese Beobachtung blieben Aenderungen im Reader unsichtbar, bis ein
    // Artikelwechsel `state.load(...)` erneut ausloest (Nutzer-Report 2026-07-12).
    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey)
    private var directTagVersion = 0

    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersion = 0

    private var shortcutOverrides: KeyboardShortcutOverrides {
        KeyboardShortcutOverrides.resolved(from: shortcutOverridesRawValue)
    }
```

`new_string`:

```swift
    @AppStorage(KeyboardShortcutOverrides.storageKey)
    private var shortcutOverridesRawValue = KeyboardShortcutOverrides().rawValue

    @AppStorage(ReaderToolbarLayout.storageKey)
    private var readerToolbarLayoutRawValue = ReaderToolbarLayout().rawValue

    // Der Artikelinfo-Inspector (ArticleMetadataInspectorView) mutiert Tags UND Ordner
    // direkt in SQLite (Tags -> SidebarBadgeInvalidation, Ordner -> SQLiteDataInvalidation)
    // und bumpt anschliessend den jeweiligen Zaehler, aktualisiert dabei aber nur seine
    // eigene lokale Snapshot-Kopie — nicht den `state.snapshot` dieser View, aus dem
    // readerArticleMetadata sowohl Tag-Chips als auch Ordnername im Artikel-Header
    // rendert. Ohne diese Beobachtung blieben Aenderungen im Reader unsichtbar, bis ein
    // Artikelwechsel `state.load(...)` erneut ausloest (Nutzer-Report 2026-07-12).
    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey)
    private var directTagVersion = 0

    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersion = 0

    private var shortcutOverrides: KeyboardShortcutOverrides {
        KeyboardShortcutOverrides.resolved(from: shortcutOverridesRawValue)
    }

    private var readerToolbarLayout: ReaderToolbarLayout {
        ReaderToolbarLayout.resolved(from: readerToolbarLayoutRawValue)
    }
```

- [ ] **Step 2: `readerToolbarContent` auf dynamisches Rendering umstellen**

`old_string` (Zeilen 123-271, kompletter bisheriger Inhalt von `readerToolbarContent`):

```swift
    @ToolbarContentBuilder
    private var readerToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Group {
                Spacer()

                ControlGroup {
                    Button {
                        openWindow(id: ArticleSearchWindowView.windowID)
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .help(L10n.articleSearchCommand)

                    Button {
                        openOriginal()
                    } label: {
                        Image(systemName: "safari")
                    }
                    .help(L10n.articleOpenOriginalCommand)
                    .disabled(originalURL == nil)
                }

                // Status-Gruppe: Regel erstellen / Stern / Archivieren / Ungelesen
                ControlGroup {
                    Button {
                        if let snapshot = state.snapshot {
                            onCreateRule(snapshot)
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .help(L10n.articleCreateRuleCommand)
                    .disabled(state.snapshot == nil)

                    Button {
                        if let database {
                            state.toggleStarred(database: database)
                        }
                    } label: {
                        Image(systemName: state.snapshot?.isStarred == true ? "star.fill" : "star")
                    }
                    .help(state.snapshot?.isStarred == true ? L10n.articleRowStarRemove : L10n.articleRowStarAdd)
                    .disabled(state.snapshot == nil)

                    Button {
                        if let database {
                            state.toggleArchived(database: database)
                        }
                    } label: {
                        Image(systemName: state.snapshot?.isArchived == true ? "archivebox.fill" : "archivebox")
                    }
                    .help(state.snapshot?.isArchived == true ? L10n.articleUnarchiveCommand : L10n.articleArchiveCommand)
                    .disabled(state.snapshot == nil)

                    Button {
                        if let database {
                            state.toggleRead(database: database)
                        }
                    } label: {
                        Image(systemName: state.snapshot?.isRead == true ? "circle" : "circle.fill")
                    }
                    .help(state.snapshot?.isRead == true ? L10n.articleRowMarkUnread : L10n.articleRowMarkRead)
                    .disabled(state.snapshot == nil)
                }

                ControlGroup {
                    Button {
                        copyLink()
                    } label: {
                        Image(systemName: "link")
                    }
                    .help(L10n.articleCopyLinkCommand)
                    .disabled(originalURL == nil)

                    Button {
                        requestExportArticle()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help(L10n.articleExportCommand)
                    .disabled(state.snapshot == nil)
                }

                ControlGroup {
                    Button {
                        webNavigationController.goBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .help(L10n.readerWebBackCommand)
                    .customizableKeyboardShortcut(.readerWebBack, overrides: shortcutOverrides)
                    .disabled(readerDisplayMode != .web || !webNavigationController.canGoBack)

                    Button {
                        webNavigationController.goForward()
                    } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .help(L10n.readerWebForwardCommand)
                    .customizableKeyboardShortcut(.readerWebForward, overrides: shortcutOverrides)
                    .disabled(readerDisplayMode != .web || !webNavigationController.canGoForward)
                }

                ControlGroup {
                    Button {
                        printCurrentArticle()
                    } label: {
                        Image(systemName: "printer")
                    }
                    .help(L10n.articlePrintCommand)
                    .customizableKeyboardShortcut(.articlePrint, overrides: shortcutOverrides)
                    .disabled(state.snapshot == nil)
                }

                Picker(L10n.readerDisplayModePicker, selection: $readerDisplayModeRawValue) {
                    ForEach(ReaderDisplayMode.allCases) { mode in
                        Text(mode.titleKey)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .help(L10n.readerDisplayModeToggleHelp)
                .disabled(originalURL == nil)

                Button {
                    isAppearancePopoverPresented.toggle()
                } label: {
                    Image(systemName: "textformat")
                }
                .help(L10n.readerAppearanceButton)
                .popover(isPresented: $isAppearancePopoverPresented, arrowEdge: .bottom) {
                    readerAppearancePopover
                }

                Button {
                    isMetadataInspectorPresented.toggle()
                } label: {
                    Label(L10n.readerInspectorButton, systemImage: "sidebar.right")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .symbolVariant(isMetadataInspectorPresented ? .fill : .none)
                .help(L10n.readerInspectorButton)
            }
            .id(toolbarRebuildGeneration)
        }
    }
```

`new_string`:

```swift
    @ToolbarContentBuilder
    private var readerToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Group {
                Spacer()

                ForEach(readerToolbarLayout.visibleOrderedItems) { item in
                    toolbarItemView(for: item)
                }
            }
            .id(toolbarRebuildGeneration)
        }
    }

    // Ehemals 6 fest verdrahtete ControlGroup-Buendel + Picker + 2 Buttons in
    // fester Reihenfolge (siehe Git-Historie). Seit Feature "Toolbar anpassen"
    // (2026-07-18) rendert readerToolbarContent stattdessen dynamisch ueber
    // readerToolbarLayout.visibleOrderedItems — die alte ControlGroup-Buendelung
    // (z. B. Stern+Archivieren+Gelesen als optische Einheit) entfaellt bewusst,
    // da feste Buendelgrenzen bei freier Umsortierung keinen Sinn mehr ergeben.
    // Jeder einzelne Case unten entspricht 1:1 dem vorherigen Button-/Picker-Code
    // (Icon, .help(...), .disabled(...), .customizableKeyboardShortcut(...)
    // unveraendert) — nur die ControlGroup-Klammerung wurde entfernt.
    @ViewBuilder
    private func toolbarItemView(for item: ReaderToolbarItem) -> some View {
        switch item {
        case .search:
            Button {
                openWindow(id: ArticleSearchWindowView.windowID)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help(L10n.articleSearchCommand)

        case .openOriginal:
            Button {
                openOriginal()
            } label: {
                Image(systemName: "safari")
            }
            .help(L10n.articleOpenOriginalCommand)
            .disabled(originalURL == nil)

        case .createRule:
            Button {
                if let snapshot = state.snapshot {
                    onCreateRule(snapshot)
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help(L10n.articleCreateRuleCommand)
            .disabled(state.snapshot == nil)

        case .star:
            Button {
                if let database {
                    state.toggleStarred(database: database)
                }
            } label: {
                Image(systemName: state.snapshot?.isStarred == true ? "star.fill" : "star")
            }
            .help(state.snapshot?.isStarred == true ? L10n.articleRowStarRemove : L10n.articleRowStarAdd)
            .disabled(state.snapshot == nil)

        case .archive:
            Button {
                if let database {
                    state.toggleArchived(database: database)
                }
            } label: {
                Image(systemName: state.snapshot?.isArchived == true ? "archivebox.fill" : "archivebox")
            }
            .help(state.snapshot?.isArchived == true ? L10n.articleUnarchiveCommand : L10n.articleArchiveCommand)
            .disabled(state.snapshot == nil)

        case .toggleRead:
            Button {
                if let database {
                    state.toggleRead(database: database)
                }
            } label: {
                Image(systemName: state.snapshot?.isRead == true ? "circle" : "circle.fill")
            }
            .help(state.snapshot?.isRead == true ? L10n.articleRowMarkUnread : L10n.articleRowMarkRead)
            .disabled(state.snapshot == nil)

        case .copyLink:
            Button {
                copyLink()
            } label: {
                Image(systemName: "link")
            }
            .help(L10n.articleCopyLinkCommand)
            .disabled(originalURL == nil)

        case .export:
            Button {
                requestExportArticle()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help(L10n.articleExportCommand)
            .disabled(state.snapshot == nil)

        case .webBack:
            Button {
                webNavigationController.goBack()
            } label: {
                Image(systemName: "chevron.backward")
            }
            .help(L10n.readerWebBackCommand)
            .customizableKeyboardShortcut(.readerWebBack, overrides: shortcutOverrides)
            .disabled(readerDisplayMode != .web || !webNavigationController.canGoBack)

        case .webForward:
            Button {
                webNavigationController.goForward()
            } label: {
                Image(systemName: "chevron.forward")
            }
            .help(L10n.readerWebForwardCommand)
            .customizableKeyboardShortcut(.readerWebForward, overrides: shortcutOverrides)
            .disabled(readerDisplayMode != .web || !webNavigationController.canGoForward)

        case .print:
            Button {
                printCurrentArticle()
            } label: {
                Image(systemName: "printer")
            }
            .help(L10n.articlePrintCommand)
            .customizableKeyboardShortcut(.articlePrint, overrides: shortcutOverrides)
            .disabled(state.snapshot == nil)

        case .displayModePicker:
            Picker(L10n.readerDisplayModePicker, selection: $readerDisplayModeRawValue) {
                ForEach(ReaderDisplayMode.allCases) { mode in
                    Text(mode.titleKey)
                        .tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .help(L10n.readerDisplayModeToggleHelp)
            .disabled(originalURL == nil)

        case .appearance:
            Button {
                isAppearancePopoverPresented.toggle()
            } label: {
                Image(systemName: "textformat")
            }
            .help(L10n.readerAppearanceButton)
            .popover(isPresented: $isAppearancePopoverPresented, arrowEdge: .bottom) {
                readerAppearancePopover
            }

        case .inspector:
            Button {
                isMetadataInspectorPresented.toggle()
            } label: {
                Label(L10n.readerInspectorButton, systemImage: "sidebar.right")
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .symbolVariant(isMetadataInspectorPresented ? .fill : .none)
            .help(L10n.readerInspectorButton)
        }
    }
```

- [ ] **Step 3: Build verifizieren**

Der exhaustive `switch` über `ReaderToolbarItem` ist die einzige "Test"-Absicherung dieses Refactors auf Vollständigkeit — fehlt ein Case, ist das ein Compile-Fehler, kein Laufzeitfehler:

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Gezielte Tests aus Task 1+2 erneut laufen lassen (Regressionscheck)**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/ReaderToolbarItemTests -only-testing:FeedivoTests/ReaderToolbarSettingsTests -parallel-testing-enabled NO`
Expected: PASS (alle 11 Tests grün)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/Reader/SQLiteReaderView.swift
git commit -m "Feature: Reader-Toolbar rendert Icons dynamisch nach ReaderToolbarLayout (Task 4/4)"
```

---

## Manuelle Live-Verifikationscheckliste (nach Task 4, vor Push)

Kein computer-use für native macOS-Apps in dieser Umgebung verfügbar — folgende Punkte sind vom Nutzer manuell zu prüfen:

1. Neuer „Toolbar"-Tab in den Einstellungen erscheint, zeigt alle 14 Elemente in der heutigen Standardreihenfolge.
2. Ein Icon per Drag&Drop verschieben — Reader-Toolbar übernimmt die neue Reihenfolge sofort, ohne Neustart.
3. Ein Icon ausblenden (Toggle) — verschwindet aus der Toolbar; zugehöriger Menüpunkt/Shortcut bleibt unverändert funktionsfähig.
4. Segmented Picker (Ansicht) und Inspector-Button an eine andere Position verschieben — funktionieren weiterhin korrekt.
5. „Alle zurücksetzen" — setzt Reihenfolge und Sichtbarkeit auf den Auslieferungszustand zurück.
6. Bestehende Laufzeit-Bedingungen weiterhin korrekt: Web-Zurück/-Vorwärts nur im Web-Modus aktiv, Drucken/Exportieren/etc. bei fehlendem Artikel weiterhin `.disabled`.
7. Vollbild-/Fenstergrößen-Wechsel weiterhin ohne Icon-Overlap-Regression (bestehender `toolbarRebuildGeneration`-Mechanismus).
8. Verhalten in einem Artikel-Popout-Fenster identisch zum Hauptfenster (dieselbe `SQLiteReaderView` wird wiederverwendet).
