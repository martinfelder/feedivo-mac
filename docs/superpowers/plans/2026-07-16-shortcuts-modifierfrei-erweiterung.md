# Shortcuts-Erweiterung (modifier-frei + fehlende Funktionen) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shortcuts-Einstellungen erlauben modifier-freie Tastenkombinationen (Ein-Zeichen/Leertaste)
ohne Textfeld-Kollisionsrisiko und bieten 8 bisher fehlende Menü-Funktionen als anpassbare
Shortcuts an.

**Architecture:** `CustomizableShortcut` bekommt 8 neue Fälle mit optionalem `defaultSpec` (bisher
nicht-optional). `ShortcutRecorderView` verliert die Modifier-Pflicht. Ein neuer
`TextEditingFocusMonitor` (AppKit-Notification-getrieben, `@MainActor`/`@Observable`) deaktiviert
modifier-freie Menü-Shortcuts, während ein Textfeld editiert wird — `customizableKeyboardShortcut`
wendet dafür ein zusätzliches `.disabled(...)` an, gesteuert über einen neuen, isoliert testbaren
`KeyboardShortcutsSettings.needsTextFieldGuard(for:)`-Helper.

**Tech Stack:** SwiftUI (macOS 14+), AppKit (`NSControl`-Notifications, `NSEvent`), Swift Testing
(`@testable import Feedivo`), GRDB/SQLite ist von diesem Feature nicht betroffen.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-16-shortcuts-modifierfrei-erweiterung-design.md` — bei
  Widersprüchen zwischen Plan und Spec gilt die Spec.
- Kommentare im Code auf Deutsch (Projektkonvention, siehe `CLAUDE.md`).
- `xcodebuild build` muss nach jedem Task grün sein: `xcodebuild build -project Feedivo.xcodeproj
  -scheme Feedivo -destination 'platform=macOS'`.
- Tests laufen gezielt, nie das volle `xcodebuild test` (hängt reproduzierbar, siehe `CLAUDE.md`):
  `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
  -only-testing:FeedivoTests/FeedivoTests -parallel-testing-enabled NO`.
- Neue `L10n.swift`-Konstanten, die nicht 1:1 einem bestehenden String-Literal entsprechen, werden
  vom Xcode-Auto-Stub-Mechanismus NICHT automatisch in `Localizable.xcstrings` angelegt — jeder
  neue `L10n`-Key aus diesem Plan muss manuell im Katalog ergänzt werden (siehe Task 2).
  Verifikation: `grep -c "<key>" Feedivo/Resources/Localizable.xcstrings` muss > 0 sein.
- „Feed löschen" bekommt bewusst KEINEN Shortcut — nicht Teil dieses Plans.
- Keine Änderung an bestehenden, bereits mit Modifier belegten Default-Shortcuts.

---

## Task 1: Datenmodell — `defaultSpec` optional + 8 neue `CustomizableShortcut`-Fälle

**Files:**
- Modify: `Feedivo/Models/CustomizableShortcut.swift`
- Modify: `Feedivo/Resources/L10n.swift:149` (nach der bestehenden `shortcutsLabel*`-Blockliste)
- Test: `FeedivoTests/FeedivoTests.swift:862` (direkt vor der schließenden `}` der `FeedivoTests`-Struct)

**Interfaces:**
- Produces: `CustomizableShortcut` mit 20 Fällen (12 bestehend + 8 neu:
  `feedImportOPML`, `feedExportOPML`, `feedOrganizerOpen`, `articleToggleArchived`,
  `articleCopyLink`, `articleOpenOriginal`, `articleShareOriginal`, `articleExport`).
  `defaultSpec: KeyboardShortcutSpec?` (Typänderung von nicht-optional). Alle 8 neuen Fälle liefern
  `nil`.

- [ ] **Step 1: Neue L10n-Konstanten ergänzen**

In `Feedivo/Resources/L10n.swift`, direkt nach Zeile 149
(`static let shortcutsLabelReaderWebForward = ...`) einfügen:

```swift
    static let shortcutsLabelFeedImportOPML = LocalizedStringKey("shortcuts.label.feedImportOPML")
    static let shortcutsLabelFeedExportOPML = LocalizedStringKey("shortcuts.label.feedExportOPML")
    static let shortcutsLabelFeedOrganizerOpen = LocalizedStringKey("shortcuts.label.feedOrganizerOpen")
    static let shortcutsLabelArticleToggleArchived = LocalizedStringKey("shortcuts.label.articleToggleArchived")
    static let shortcutsLabelArticleCopyLink = LocalizedStringKey("shortcuts.label.articleCopyLink")
    static let shortcutsLabelArticleOpenOriginal = LocalizedStringKey("shortcuts.label.articleOpenOriginal")
    static let shortcutsLabelArticleShareOriginal = LocalizedStringKey("shortcuts.label.articleShareOriginal")
    static let shortcutsLabelArticleExport = LocalizedStringKey("shortcuts.label.articleExport")
```

- [ ] **Step 2: Failing Test schreiben**

In `FeedivoTests/FeedivoTests.swift`, direkt vor der schließenden `}` von `struct FeedivoTests`
(aktuell Zeile 864) einfügen:

```swift

    @Test func customizableShortcutEnthaeltAchtNeueFaelleOhneDefault() {
        let newCases: [CustomizableShortcut] = [
            .feedImportOPML, .feedExportOPML, .feedOrganizerOpen,
            .articleToggleArchived, .articleCopyLink, .articleOpenOriginal,
            .articleShareOriginal, .articleExport
        ]

        for shortcut in newCases {
            #expect(shortcut.defaultSpec == nil, "\(shortcut.rawValue) sollte keinen Default-Shortcut haben")
        }

        #expect(CustomizableShortcut.feedImportOPML.category == .feed)
        #expect(CustomizableShortcut.feedExportOPML.category == .feed)
        #expect(CustomizableShortcut.feedOrganizerOpen.category == .feed)
        #expect(CustomizableShortcut.articleToggleArchived.category == .article)
        #expect(CustomizableShortcut.articleCopyLink.category == .article)
        #expect(CustomizableShortcut.articleOpenOriginal.category == .article)
        #expect(CustomizableShortcut.articleShareOriginal.category == .article)
        #expect(CustomizableShortcut.articleExport.category == .article)

        #expect(CustomizableShortcut.allCases.count == 20)
    }
```

- [ ] **Step 3: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests/customizableShortcutEnthaeltAchtNeueFaelleOhneDefault -parallel-testing-enabled NO`
Expected: FAIL — Compile-Fehler, da `.feedImportOPML` etc. noch nicht existieren.

- [ ] **Step 4: `CustomizableShortcut.swift` komplett auf neue Fälle umstellen**

Vollständiger neuer Inhalt von `Feedivo/Models/CustomizableShortcut.swift`:

```swift
import SwiftUI

enum ShortcutCategory: CaseIterable, Hashable, Sendable {
    case feed
    case article
    case reader

    var titleKey: LocalizedStringKey {
        switch self {
        case .feed: L10n.shortcutsCategoryFeed
        case .article: L10n.shortcutsCategoryArticle
        case .reader: L10n.shortcutsCategoryReader
        }
    }
}

/// Registry aller nutzerdefinierbar gemachten Tastenkombinationen. Bewusst NICHT
/// enthalten: `.keyboardShortcut(.defaultAction)`-Stellen in Dialogen (Export-Sheet,
/// Regel-Assistent, Tag-Manager, …) — das ist die macOS-Konvention "Enter löst den
/// Standard-Button aus", kein eigentlicher, umbenennbarer Befehls-Shortcut. „Feed
/// löschen" ist ebenfalls bewusst nicht enthalten — sensible, destruktive Aktion,
/// die keinen versehentlich auslösbaren Shortcut bekommen soll (Nutzerentscheidung
/// 2026-07-16).
enum CustomizableShortcut: String, CaseIterable, Identifiable, Sendable {
    case feedAdd
    case statisticsOpen
    case feedRefreshAll
    case feedRefresh
    case feedImportOPML
    case feedExportOPML
    case feedOrganizerOpen
    case articleSelectPrevious
    case articleSelectNext
    case articleSearch
    case articleToggleRead
    case articleToggleStarred
    case articleToggleArchived
    case articleOpenInWindow
    case articleCopyLink
    case articleOpenOriginal
    case articleShareOriginal
    case articleExport
    case readerWebBack
    case readerWebForward

    var id: String { rawValue }

    var category: ShortcutCategory {
        switch self {
        case .feedAdd, .statisticsOpen, .feedRefreshAll, .feedRefresh,
             .feedImportOPML, .feedExportOPML, .feedOrganizerOpen:
            .feed
        case .articleSelectPrevious, .articleSelectNext, .articleSearch,
             .articleToggleRead, .articleToggleStarred, .articleToggleArchived,
             .articleOpenInWindow, .articleCopyLink, .articleOpenOriginal,
             .articleShareOriginal, .articleExport:
            .article
        case .readerWebBack, .readerWebForward:
            .reader
        }
    }

    /// Aufgelöster Klartext für Stellen, die keinen `Text`/`LocalizedStringKey`-Kontext
    /// haben (z. B. die Konflikt-Meldung "Bereits belegt durch: %@"). Nutzt denselben
    /// xcstrings-Key wie `titleKey`, nur zur Laufzeit statt SwiftUI-deklarativ aufgelöst.
    var resolvedLabel: String {
        String(localized: "shortcuts.label.\(rawValue)")
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .feedAdd: L10n.shortcutsLabelFeedAdd
        case .statisticsOpen: L10n.shortcutsLabelStatisticsOpen
        case .feedRefreshAll: L10n.shortcutsLabelFeedRefreshAll
        case .feedRefresh: L10n.shortcutsLabelFeedRefresh
        case .feedImportOPML: L10n.shortcutsLabelFeedImportOPML
        case .feedExportOPML: L10n.shortcutsLabelFeedExportOPML
        case .feedOrganizerOpen: L10n.shortcutsLabelFeedOrganizerOpen
        case .articleSelectPrevious: L10n.shortcutsLabelArticleSelectPrevious
        case .articleSelectNext: L10n.shortcutsLabelArticleSelectNext
        case .articleSearch: L10n.shortcutsLabelArticleSearch
        case .articleToggleRead: L10n.shortcutsLabelArticleToggleRead
        case .articleToggleStarred: L10n.shortcutsLabelArticleToggleStarred
        case .articleToggleArchived: L10n.shortcutsLabelArticleToggleArchived
        case .articleOpenInWindow: L10n.shortcutsLabelArticleOpenInWindow
        case .articleCopyLink: L10n.shortcutsLabelArticleCopyLink
        case .articleOpenOriginal: L10n.shortcutsLabelArticleOpenOriginal
        case .articleShareOriginal: L10n.shortcutsLabelArticleShareOriginal
        case .articleExport: L10n.shortcutsLabelArticleExport
        case .readerWebBack: L10n.shortcutsLabelReaderWebBack
        case .readerWebForward: L10n.shortcutsLabelReaderWebForward
        }
    }

    /// Entspricht 1:1 den bisherigen hartcodierten `.keyboardShortcut(...)`-Werten,
    /// damit sich beim Einführen dieses Features für niemanden etwas ändert, der
    /// noch nichts angepasst hat. `nil` bedeutet „kein Default" — die 8 am
    /// 2026-07-16 ergänzten Fälle hatten vorher überhaupt keinen Shortcut und
    /// erscheinen deshalb in den Einstellungen zunächst als „nicht belegt".
    var defaultSpec: KeyboardShortcutSpec? {
        switch self {
        case .feedAdd:
            KeyboardShortcutSpec(key: "n", modifiers: [.command])
        case .statisticsOpen:
            KeyboardShortcutSpec(key: "s", modifiers: [.command, .shift])
        case .feedRefreshAll:
            KeyboardShortcutSpec(key: "r", modifiers: [.command, .shift])
        case .feedRefresh:
            KeyboardShortcutSpec(key: "r", modifiers: [.command])
        case .feedImportOPML, .feedExportOPML, .feedOrganizerOpen:
            nil
        case .articleSelectPrevious:
            KeyboardShortcutSpec(key: SpecialKey.upArrow.rawValue, modifiers: [.command])
        case .articleSelectNext:
            KeyboardShortcutSpec(key: SpecialKey.downArrow.rawValue, modifiers: [.command])
        case .articleSearch:
            KeyboardShortcutSpec(key: "f", modifiers: [.command])
        case .articleToggleRead:
            KeyboardShortcutSpec(key: "u", modifiers: [.command, .shift])
        case .articleToggleStarred:
            KeyboardShortcutSpec(key: "d", modifiers: [.command])
        case .articleToggleArchived, .articleCopyLink, .articleOpenOriginal,
             .articleShareOriginal, .articleExport:
            nil
        case .articleOpenInWindow:
            KeyboardShortcutSpec(key: SpecialKey.return.rawValue, modifiers: [.command])
        case .readerWebBack:
            KeyboardShortcutSpec(key: "[", modifiers: [.command])
        case .readerWebForward:
            KeyboardShortcutSpec(key: "]", modifiers: [.command])
        }
    }
}
```

- [ ] **Step 5: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests/customizableShortcutEnthaeltAchtNeueFaelleOhneDefault -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 6: Bestehende Shortcut-Tests laufen lassen (Regressionscheck)**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -parallel-testing-enabled NO`
Expected: PASS (alle Tests der Datei, inkl. der bestehenden 5 Shortcut-Tests ab Zeile 802)

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Models/CustomizableShortcut.swift Feedivo/Resources/L10n.swift FeedivoTests/FeedivoTests.swift
git commit -m "Feature: 8 neue anpassbare Shortcut-Funktionen registriert (ohne Default)"
```

---

## Task 2: Localizable.xcstrings — Katalogeinträge für die 8 neuen Labels + Warnhinweis

**Files:**
- Modify: `Feedivo/Resources/Localizable.xcstrings`
- Modify: `Feedivo/Resources/L10n.swift` (1 weitere Konstante für den Warnhinweis)

**Interfaces:**
- Consumes: die 8 `shortcuts.label.*`-Keys aus Task 1, plus `shortcuts.modifierFree.warning` (wird
  in Task 7 von der Einstellungen-UI konsumiert, aber hier bereits mit angelegt, damit der Katalog
  in einem Rutsch vollständig ist).
- Produces: vollständige de/en/fr/it-Übersetzungen für alle 9 neuen Keys im String-Katalog.

- [ ] **Step 1: Warnhinweis-Konstante in L10n.swift ergänzen**

In `Feedivo/Resources/L10n.swift`, direkt nach den in Task 1 ergänzten `shortcutsLabel*`-Zeilen
einfügen:

```swift
    static let shortcutsModifierFreeWarning = LocalizedStringKey("shortcuts.modifierFree.warning")
```

- [ ] **Step 2: Katalogeinträge per Python-Skript ergänzen**

Folgendes Skript ausführen (exaktes bestehendes JSON-Format beibehalten, analog dem bereits im
Projekt etablierten Vorgehen bei fehlenden `L10n`-Katalogeinträgen):

```bash
python3 <<'PYEOF'
import json

path = "Feedivo/Resources/Localizable.xcstrings"
with open(path, encoding="utf-8") as f:
    data = json.load(f)

new_entries = {
    "shortcuts.label.feedImportOPML": {
        "de": "OPML importieren", "en": "Import OPML",
        "fr": "Importer OPML", "it": "Importa OPML",
    },
    "shortcuts.label.feedExportOPML": {
        "de": "OPML exportieren", "en": "Export OPML",
        "fr": "Exporter OPML", "it": "Esporta OPML",
    },
    "shortcuts.label.feedOrganizerOpen": {
        "de": "Verwaltung öffnen", "en": "Open management",
        "fr": "Ouvrir la gestion", "it": "Apri gestione",
    },
    "shortcuts.label.articleToggleArchived": {
        "de": "Archivieren", "en": "Archive",
        "fr": "Archiver", "it": "Archivia",
    },
    "shortcuts.label.articleCopyLink": {
        "de": "Link kopieren", "en": "Copy link",
        "fr": "Copier le lien", "it": "Copia link",
    },
    "shortcuts.label.articleOpenOriginal": {
        "de": "Original öffnen", "en": "Open original",
        "fr": "Ouvrir l'original", "it": "Apri originale",
    },
    "shortcuts.label.articleShareOriginal": {
        "de": "Teilen", "en": "Share",
        "fr": "Partager", "it": "Condividi",
    },
    "shortcuts.label.articleExport": {
        "de": "Exportieren", "en": "Export",
        "fr": "Exporter", "it": "Esporta",
    },
    "shortcuts.modifierFree.warning": {
        "de": "Ohne Zusatztaste – pausiert automatisch, während ein Textfeld fokussiert ist (außer bei Textfeldern innerhalb eines geladenen Original-Artikels).",
        "en": "No modifier key — automatically pauses while a text field is focused (except for text fields inside a loaded original article).",
        "fr": "Sans touche de modification — se met en pause automatiquement pendant qu'un champ de texte est actif (sauf pour les champs de texte à l'intérieur d'un article original chargé).",
        "it": "Senza tasto modificatore — si mette in pausa automaticamente mentre un campo di testo è attivo (tranne per i campi di testo all'interno di un articolo originale caricato).",
    },
}

for key, translations in new_entries.items():
    assert key not in data["strings"], f"{key} existiert bereits im Katalog"
    data["strings"][key] = {
        "localizations": {
            lang: {"stringUnit": {"state": "translated", "value": value}}
            for lang, value in translations.items()
        }
    }

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
    f.write("\n")
PYEOF
```

- [ ] **Step 3: Katalog validieren**

Run: `python3 -c "import json; json.load(open('Feedivo/Resources/Localizable.xcstrings'))" && echo "JSON gültig"`
Expected: `JSON gültig` (kein Parse-Fehler)

Run: `grep -c "shortcuts.label.feedImportOPML\|shortcuts.label.feedExportOPML\|shortcuts.label.feedOrganizerOpen\|shortcuts.label.articleToggleArchived\|shortcuts.label.articleCopyLink\|shortcuts.label.articleOpenOriginal\|shortcuts.label.articleShareOriginal\|shortcuts.label.articleExport\|shortcuts.modifierFree.warning" Feedivo/Resources/Localizable.xcstrings`
Expected: `9` (jeder der 9 neuen Keys kommt genau einmal als JSON-Schlüssel vor)

- [ ] **Step 4: Build ausführen (String-Katalog wird kompiliert, deckt kaputtes JSON auf)**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Resources/Localizable.xcstrings Feedivo/Resources/L10n.swift
git commit -m "Docs: Localizable.xcstrings — 9 neue Shortcuts-Katalogeinträge (de/en/fr/it) ergänzt"
```

---

## Task 3: `KeyboardShortcutSpec.displaySymbols` — Leertaste als „␣" anzeigen

**Files:**
- Modify: `Feedivo/Models/KeyboardShortcutSpec.swift:77-84`
- Test: `FeedivoTests/FeedivoTests.swift` (direkt nach `keyboardShortcutSpecLiefertKorrekteAnzeigeSymbole`, aktuell Zeile 812)

**Interfaces:**
- Consumes: keine neuen Abhängigkeiten.
- Produces: `KeyboardShortcutSpec.displaySymbols` zeigt für `key == " "` das Zeichen `"␣"` statt eines
  unsichtbaren Leerzeichens.

- [ ] **Step 1: Failing Test schreiben**

In `FeedivoTests/FeedivoTests.swift`, direkt nach dem bestehenden Test
`keyboardShortcutSpecLiefertKorrekteAnzeigeSymbole` (schließende `}` aktuell Zeile 812) einfügen:

```swift

    @Test func keyboardShortcutSpecZeigtLeertasteAlsSonderzeichen() {
        let plainSpace = KeyboardShortcutSpec(key: " ", modifiers: [])
        #expect(plainSpace.displaySymbols == "␣")

        let shiftSpace = KeyboardShortcutSpec(key: " ", modifiers: [.shift])
        #expect(shiftSpace.displaySymbols == "⇧␣")
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests/keyboardShortcutSpecZeigtLeertasteAlsSonderzeichen -parallel-testing-enabled NO`
Expected: FAIL — `plainSpace.displaySymbols` liefert aktuell `" "` (ein Leerzeichen), nicht `"␣"`.

- [ ] **Step 3: `displaySymbols` implementieren**

In `Feedivo/Models/KeyboardShortcutSpec.swift`, den bestehenden `displaySymbols`-Computed-Property
(Zeilen 77-84) ersetzen durch:

```swift
    /// Für die Einstellungen-Liste, z. B. "⌘⇧R". Leertaste wird als „␣" dargestellt,
    /// da ein rohes Leerzeichen im Badge unsichtbar und damit verwirrend wäre.
    var displaySymbols: String {
        let modifierSymbols = ShortcutModifier.allCases
            .filter { modifiers.contains($0) }
            .map(\.symbol)
            .joined()
        let keySymbol: String
        if let specialKey = SpecialKey(rawValue: key) {
            keySymbol = specialKey.displaySymbol
        } else if key == " " {
            keySymbol = "␣"
        } else {
            keySymbol = key.uppercased()
        }
        return modifierSymbols + keySymbol
    }
```

- [ ] **Step 4: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests/keyboardShortcutSpecZeigtLeertasteAlsSonderzeichen -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 5: Regressionscheck bestehender Symbol-Test**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests/keyboardShortcutSpecLiefertKorrekteAnzeigeSymbole -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Models/KeyboardShortcutSpec.swift FeedivoTests/FeedivoTests.swift
git commit -m "Feature: Leertaste als ␣-Symbol im Shortcut-Badge dargestellt"
```

---

## Task 4: Recorder — Modifier-Pflicht entfernen

**Files:**
- Modify: `Feedivo/Views/Settings/ShortcutRecorderView.swift:61-100`

**Interfaces:**
- Consumes: keine.
- Produces: `RecorderNSView.keyDown` ruft `onCapture` jetzt auch bei modifikator-freien
  Tastendrücken auf (bisher: `guard !modifiers.isEmpty else { return }` verhinderte das).

**Hinweis:** `RecorderNSView` ist ein reiner AppKit-`NSView`-Event-Handler ohne Dependency-Injection-
Seam für `NSEvent` — nicht sinnvoll isoliert unit-testbar (bereits vor diesem Plan so). Verifikation
erfolgt über Build + die für Task 8 vorgesehene manuelle Live-Prüfung.

- [ ] **Step 1: Guard entfernen und Kommentar aktualisieren**

In `Feedivo/Views/Settings/ShortcutRecorderView.swift`, den Kommentar über `RecorderNSView` (Zeilen
61-63) und den `keyDown`-Body (Zeilen 70-100) ersetzen durch:

```swift
/// Fängt Tastendrücke ab, solange `isRecording` aktiv ist. Modifier-freie Kombinationen
/// (nur ein Zeichen oder Leertaste) sind seit 2026-07-16 bewusst erlaubt — siehe
/// `TextEditingFocusMonitor` für den zugehörigen Textfeld-Schutzmechanismus, der
/// verhindert, dass ein so belegter Shortcut normales Tippen blockiert.
private final class RecorderNSView: NSView {
    var onCapture: ((String, Set<ShortcutModifier>) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Escape (keyCode 53) bricht die Aufnahme ab, ohne etwas zu ändern.
        guard event.keyCode != 53 else {
            onCancel?()
            return
        }

        var modifiers: Set<ShortcutModifier> = []
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }

        let key: String
        switch event.keyCode {
        case 126: key = SpecialKey.upArrow.rawValue
        case 125: key = SpecialKey.downArrow.rawValue
        case 36: key = SpecialKey.return.rawValue
        default:
            guard let character = event.charactersIgnoringModifiers?.lowercased(), !character.isEmpty else {
                return
            }
            key = character
        }

        onCapture?(key, modifiers)
    }

    override func resignFirstResponder() -> Bool {
        onCancel?()
        return super.resignFirstResponder()
    }
}
```

- [ ] **Step 2: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Feedivo/Views/Settings/ShortcutRecorderView.swift
git commit -m "Feature: Shortcut-Recorder erlaubt modifier-freie Tastenkombinationen"
```

---

## Task 5: `TextEditingFocusMonitor` + Registrierung in `FeedivoAppDelegate`

**Files:**
- Create: `Feedivo/Services/TextEditingFocusMonitor.swift`
- Modify: `Feedivo/App/FeedivoAppDelegate.swift:28-34`
- Test: `FeedivoTests/FeedivoTests.swift` (neuer Test direkt vor der schließenden `}` der Struct)

**Interfaces:**
- Produces: `@MainActor @Observable final class TextEditingFocusMonitor` mit
  `static let shared: TextEditingFocusMonitor`, `private(set) var isEditingText: Bool` (Default
  `false`), `func startObserving(center: NotificationCenter = .default)`.
- Wird von Task 6 (`KeyboardShortcutsSettings.customizableKeyboardShortcut`) konsumiert.

- [ ] **Step 1: Failing Test schreiben**

In `FeedivoTests/FeedivoTests.swift`, direkt vor der schließenden `}` der `FeedivoTests`-Struct
einfügen:

```swift

    @MainActor
    @Test func textEditingFocusMonitorReagiertAufBeginnUndEndeNotification() async throws {
        let center = NotificationCenter()
        let monitor = TextEditingFocusMonitor()
        monitor.startObserving(center: center)

        #expect(monitor.isEditingText == false)

        center.post(name: NSControl.textDidBeginEditingNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(monitor.isEditingText == true)

        center.post(name: NSControl.textDidEndEditingNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(monitor.isEditingText == false)
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests/textEditingFocusMonitorReagiertAufBeginnUndEndeNotification -parallel-testing-enabled NO`
Expected: FAIL — Compile-Fehler, `TextEditingFocusMonitor` existiert noch nicht. `init()` muss dafür
nicht-privat sein (Test erzeugt eine eigene Instanz statt `.shared`, um Parallel-Test-Interferenz
über den globalen `NotificationCenter.default` zu vermeiden).

- [ ] **Step 3: `TextEditingFocusMonitor.swift` anlegen**

Neue Datei `Feedivo/Services/TextEditingFocusMonitor.swift`:

```swift
import AppKit
import SwiftUI

/// Beobachtet app-weit, ob gerade ein `NSTextField`/`NSTextView` editiert wird (SwiftUI
/// `TextField` läuft auf macOS intern über `NSTextField`, löst dieselben Notifications
/// aus). Grundlage für den Textfeld-Schutz modifier-freier Shortcuts — siehe
/// `KeyboardShortcutsSettings.customizableKeyboardShortcut(_:overrides:)`.
///
/// Bekannte Grenze: Textfelder innerhalb einer im `WKWebView` geladenen Webseite
/// (Originalartikel-Ansicht) laufen nicht über `NSControl` und lösen diese
/// Notifications nicht aus — dort bleibt ein theoretisches Kollisionsrisiko für
/// modifier-freie Shortcuts bestehen (dokumentierte, nicht behobene Einschränkung).
@Observable
@MainActor
final class TextEditingFocusMonitor {
    static let shared = TextEditingFocusMonitor()

    private(set) var isEditingText = false
    private var beginObserver: NSObjectProtocol?
    private var endObserver: NSObjectProtocol?

    init() {}

    /// `queue: .main` + `@MainActor`-Closure ist die von Apple empfohlene Brücke
    /// zwischen `NotificationCenter` und MainActor-isolierten Swift-Typen — eine
    /// naive nicht-isolierte Closure würde bei aktivem `SWIFT_DEFAULT_ACTOR_ISOLATION
    /// = MainActor` (siehe CLAUDE.md-Gotcha) nicht kompilieren.
    func startObserving(center: NotificationCenter = .default) {
        beginObserver = center.addObserver(
            forName: NSControl.textDidBeginEditingNotification,
            object: nil,
            queue: .main
        ) { @MainActor [weak self] _ in
            self?.isEditingText = true
        }

        endObserver = center.addObserver(
            forName: NSControl.textDidEndEditingNotification,
            object: nil,
            queue: .main
        ) { @MainActor [weak self] _ in
            self?.isEditingText = false
        }
    }
}
```

- [ ] **Step 4: In `FeedivoAppDelegate` registrieren**

In `Feedivo/App/FeedivoAppDelegate.swift`, in `applicationDidFinishLaunching` (Zeile 28), direkt
nach der bestehenden Zeile `UNUserNotificationCenter.current().delegate = self` (Zeile 34)
einfügen:

```swift
        TextEditingFocusMonitor.shared.startObserving()
```

- [ ] **Step 5: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests/textEditingFocusMonitorReagiertAufBeginnUndEndeNotification -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Services/TextEditingFocusMonitor.swift Feedivo/App/FeedivoAppDelegate.swift FeedivoTests/FeedivoTests.swift
git commit -m "Feature: TextEditingFocusMonitor beobachtet Textfeld-Fokus app-weit"
```

---

## Task 6: `KeyboardShortcutsSettings` — Textfeld-Schutz für modifier-freie Shortcuts anwenden

**Files:**
- Modify: `Feedivo/Services/KeyboardShortcutsSettings.swift`
- Test: `FeedivoTests/FeedivoTests.swift` (neuer Test direkt vor der schließenden `}` der Struct)

**Interfaces:**
- Consumes: `TextEditingFocusMonitor.shared.isEditingText` aus Task 5.
- Produces: `KeyboardShortcutsSettings.needsTextFieldGuard(for: KeyboardShortcutSpec) -> Bool`
  (pure Funktion, `true` genau dann, wenn `spec.modifiers.isEmpty`).
  `customizableKeyboardShortcut(_:overrides:)` wendet bei `needsTextFieldGuard == true` zusätzlich
  `.disabled(TextEditingFocusMonitor.shared.isEditingText)` an.

- [ ] **Step 1: Failing Test schreiben**

In `FeedivoTests/FeedivoTests.swift`, direkt vor der schließenden `}` der `FeedivoTests`-Struct
einfügen:

```swift

    @Test func needsTextFieldGuardIstWahrNurOhneModifier() {
        let ohneModifier = KeyboardShortcutSpec(key: "j", modifiers: [])
        let mitModifier = KeyboardShortcutSpec(key: "j", modifiers: [.command])
        let leertasteOhneModifier = KeyboardShortcutSpec(key: " ", modifiers: [])

        #expect(KeyboardShortcutsSettings.needsTextFieldGuard(for: ohneModifier) == true)
        #expect(KeyboardShortcutsSettings.needsTextFieldGuard(for: mitModifier) == false)
        #expect(KeyboardShortcutsSettings.needsTextFieldGuard(for: leertasteOhneModifier) == true)
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests/needsTextFieldGuardIstWahrNurOhneModifier -parallel-testing-enabled NO`
Expected: FAIL — Compile-Fehler, `needsTextFieldGuard` existiert noch nicht.

- [ ] **Step 3: `KeyboardShortcutsSettings.swift` vollständig aktualisieren**

Vollständiger neuer Inhalt von `Feedivo/Services/KeyboardShortcutsSettings.swift`:

```swift
import Foundation
import SwiftUI

/// Persistierte Nutzer-Überschreibungen für Feature "Shortcuts anpassen". Wird als
/// JSON-codierter String in einem einzigen `@AppStorage`-Key abgelegt (analog dem
/// String-Raw-Value-Muster von `ArticleSortOption`/`ReaderFontPreset` — 12 Einzel-
/// Keys wären hier unübersichtlicher als ein Blob).
///
/// `values` ist bewusst `[String: KeyboardShortcutSpec?]` (Wert selbst optional) statt
/// nur `[String: KeyboardShortcutSpec]`, um drei Zustände pro Shortcut zu unterscheiden:
/// - Schlüssel fehlt → nicht angepasst, `CustomizableShortcut.defaultSpec` gilt
/// - Schlüssel vorhanden mit Wert → auf diese Kombination umgelegt
/// - Schlüssel vorhanden mit `nil` → bewusst gelöscht, gar kein Shortcut
///
/// Achtung beim Schreiben: `values[id] = nil` (bare nil) ENTFERNT den Schlüssel
/// (Zustand 1), `values[id] = .some(nil)` setzt ihn explizit auf "gelöscht"
/// (Zustand 3) — das ist Swifts Standardverhalten bei optionalen Dictionary-Werten,
/// kein Bug.
struct KeyboardShortcutOverrides: Equatable {
    var values: [String: KeyboardShortcutSpec?]

    init(values: [String: KeyboardShortcutSpec?] = [:]) {
        self.values = values
    }

    static let storageKey = "customKeyboardShortcuts"

    static func resolved(from rawValue: String) -> KeyboardShortcutOverrides {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: KeyboardShortcutSpec?].self, from: data)
        else {
            return KeyboardShortcutOverrides()
        }

        return KeyboardShortcutOverrides(values: decoded)
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(values),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return string
    }
}

enum KeyboardShortcutsSettings {
    static let storageKey = KeyboardShortcutOverrides.storageKey

    static func spec(
        for shortcut: CustomizableShortcut,
        in overrides: KeyboardShortcutOverrides
    ) -> KeyboardShortcutSpec? {
        if let override = overrides.values[shortcut.id] {
            return override
        }

        return shortcut.defaultSpec
    }

    static func conflictingShortcut(
        for spec: KeyboardShortcutSpec,
        excluding: CustomizableShortcut,
        in overrides: KeyboardShortcutOverrides
    ) -> CustomizableShortcut? {
        CustomizableShortcut.allCases.first { candidate in
            candidate != excluding && Self.spec(for: candidate, in: overrides) == spec
        }
    }

    /// Modifier-freie Shortcuts (nur ein Zeichen oder Leertaste) brauchen den
    /// `TextEditingFocusMonitor`-Schutz in `customizableKeyboardShortcut`, da sie
    /// sonst als normales `NSMenuItem`-Tastenkürzel jede Texteingabe blockieren
    /// würden. Als eigene Funktion extrahiert, damit sowohl die Menü-Verdrahtung
    /// als auch die Warnzeile in den Einstellungen (Task 7) dieselbe Bedingung
    /// nutzen, statt sie unabhängig voneinander zu duplizieren.
    static func needsTextFieldGuard(for spec: KeyboardShortcutSpec) -> Bool {
        spec.modifiers.isEmpty
    }
}

extension View {
    /// Wendet den nutzerdefinierten (oder Default-)Shortcut für `shortcut` an — oder
    /// gar keinen, wenn der Nutzer ihn in den Einstellungen bewusst gelöscht hat.
    /// Modifier-freie Shortcuts werden zusätzlich deaktiviert, solange gerade ein
    /// Textfeld editiert wird (`TextEditingFocusMonitor`) — sonst würde z. B. das
    /// Tippen von „j" im Suchfeld statt eines „j" den Menübefehl auslösen.
    @ViewBuilder
    func customizableKeyboardShortcut(
        _ shortcut: CustomizableShortcut,
        overrides: KeyboardShortcutOverrides
    ) -> some View {
        if let spec = KeyboardShortcutsSettings.spec(for: shortcut, in: overrides) {
            if KeyboardShortcutsSettings.needsTextFieldGuard(for: spec) {
                self.keyboardShortcut(spec.keyEquivalent, modifiers: spec.eventModifiers)
                    .disabled(TextEditingFocusMonitor.shared.isEditingText)
            } else {
                self.keyboardShortcut(spec.keyEquivalent, modifiers: spec.eventModifiers)
            }
        } else {
            self
        }
    }
}
```

- [ ] **Step 4: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests/needsTextFieldGuardIstWahrNurOhneModifier -parallel-testing-enabled NO`
Expected: PASS

- [ ] **Step 5: Build ausführen (deckt Verwendungsstellen in `ArticleCommands.swift`/`FeedCommands.swift` ab)**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Services/KeyboardShortcutsSettings.swift FeedivoTests/FeedivoTests.swift
git commit -m "Feature: Modifier-freie Shortcuts pausieren waehrend Textfeld-Fokus"
```

---

## Task 7: Einstellungen-UI — Warnzeile für modifier-freie Shortcuts

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift:1481-1517` (`ShortcutSettingRow.body`)

**Interfaces:**
- Consumes: `KeyboardShortcutsSettings.needsTextFieldGuard(for:)` aus Task 6, `L10n.shortcutsModifierFreeWarning` aus Task 2.
- Produces: neue, bedingt sichtbare Warnzeile unterhalb des Recorders in `ShortcutSettingRow`.

**Hinweis:** Reine SwiftUI-View-Änderung ohne isolierte Unit-Test-Möglichkeit im Projekt (kein
ViewInspector o. ä. im Einsatz) — Verifikation über Build + manuelle Live-Prüfung (siehe Task 8).

- [ ] **Step 1: Warnzeile ergänzen**

In `Feedivo/Views/Settings/SettingsView.swift`, den `body` von `ShortcutSettingRow` (Zeilen
1481-1517) ersetzen durch:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 12) {
                Text(shortcut.titleKey)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: Self.labelColumnWidth, alignment: .trailing)

                ShortcutRecorderView(
                    spec: spec,
                    onCapture: { capture($0) },
                    onClear: { clear() }
                )

                if isCustomized {
                    Button {
                        reset()
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.shortcutsResetButtonHelp)
                }

                Spacer(minLength: 0)
            }

            if let conflictMessage {
                Text(conflictMessage)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .padding(.leading, Self.labelColumnWidth + 12)
            }

            if let spec, KeyboardShortcutsSettings.needsTextFieldGuard(for: spec) {
                Text(L10n.shortcutsModifierFreeWarning)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .padding(.leading, Self.labelColumnWidth + 12)
            }
        }
        .padding(.vertical, 4)
    }
```

- [ ] **Step 2: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Feedivo/Views/Settings/SettingsView.swift
git commit -m "Feature: Warnhinweis fuer modifier-freie Shortcuts in den Einstellungen"
```

---

## Task 8: Menü-Verdrahtung — 8 neue Shortcuts an Buttons anhängen

**Files:**
- Modify: `Feedivo/App/ArticleCommands.swift`
- Modify: `Feedivo/App/FeedCommands.swift`

**Interfaces:**
- Consumes: `CustomizableShortcut.articleToggleArchived/.articleCopyLink/.articleOpenOriginal/
  .articleShareOriginal/.articleExport/.feedImportOPML/.feedExportOPML/.feedOrganizerOpen` aus
  Task 1, `customizableKeyboardShortcut(_:overrides:)` aus Task 6 (unverändertes Interface).
- Produces: alle 8 neuen Menü-Funktionen sind ab jetzt in den Einstellungen unter „Shortcuts"
  sichtbar und anpassbar.

- [ ] **Step 1: `ArticleCommands.swift` vollständig aktualisieren**

Vollständiger neuer Inhalt von `Feedivo/App/ArticleCommands.swift`:

```swift
import SwiftUI

struct ArticleCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.articleCommandActions)
    private var articleCommandActions

    @AppStorage(KeyboardShortcutOverrides.storageKey)
    private var shortcutOverridesRawValue = KeyboardShortcutOverrides().rawValue

    private var shortcutOverrides: KeyboardShortcutOverrides {
        KeyboardShortcutOverrides.resolved(from: shortcutOverridesRawValue)
    }

    var body: some Commands {
        CommandMenu(L10n.articleCommandsMenu) {
            Button(L10n.articlePreviousCommand) {
                articleCommandActions?.selectPreviousArticle()
            }
            .customizableKeyboardShortcut(.articleSelectPrevious, overrides: shortcutOverrides)
            .disabled(articleCommandActions?.canSelectPreviousArticle != true)

            Button(L10n.articleNextCommand) {
                articleCommandActions?.selectNextArticle()
            }
            .customizableKeyboardShortcut(.articleSelectNext, overrides: shortcutOverrides)
            .disabled(articleCommandActions?.canSelectNextArticle != true)

            Divider()

            Button(L10n.articleSearchCommand) {
                openWindow(id: ArticleSearchWindowView.windowID)
            }
            .customizableKeyboardShortcut(.articleSearch, overrides: shortcutOverrides)

            Divider()

            Button(articleCommandActions?.toggleReadTitle ?? L10n.articleRowMarkRead) {
                articleCommandActions?.toggleRead()
            }
            .customizableKeyboardShortcut(.articleToggleRead, overrides: shortcutOverrides)
            .disabled(articleCommandActions?.canPerformActions != true)

            Button(articleCommandActions?.toggleStarredTitle ?? L10n.articleRowStarAdd) {
                articleCommandActions?.toggleStarred()
            }
            .customizableKeyboardShortcut(.articleToggleStarred, overrides: shortcutOverrides)
            .disabled(articleCommandActions?.canPerformActions != true)

            Button(articleCommandActions?.toggleArchivedTitle ?? L10n.articleArchiveCommand) {
                articleCommandActions?.toggleArchived()
            }
            .customizableKeyboardShortcut(.articleToggleArchived, overrides: shortcutOverrides)
            .disabled(articleCommandActions?.canPerformActions != true)

            Divider()

            Button(L10n.articleOpenInWindowCommand) {
                articleCommandActions?.openInArticleWindow()
            }
            .customizableKeyboardShortcut(.articleOpenInWindow, overrides: shortcutOverrides)
            .disabled(articleCommandActions?.canPerformActions != true)

            Button(L10n.articleCopyLinkCommand) {
                articleCommandActions?.copyLink()
            }
            .customizableKeyboardShortcut(.articleCopyLink, overrides: shortcutOverrides)
            .disabled(articleCommandActions?.canPerformLinkActions != true)

            Button(L10n.articleOpenOriginalCommand) {
                articleCommandActions?.openOriginal()
            }
            .customizableKeyboardShortcut(.articleOpenOriginal, overrides: shortcutOverrides)
            .disabled(articleCommandActions?.canPerformLinkActions != true)

            Button(L10n.articleShareCommand) {
                articleCommandActions?.shareOriginal()
            }
            .customizableKeyboardShortcut(.articleShareOriginal, overrides: shortcutOverrides)
            .disabled(articleCommandActions?.canPerformLinkActions != true)

            Button(L10n.articleExportCommand) {
                articleCommandActions?.requestExport()
            }
            .customizableKeyboardShortcut(.articleExport, overrides: shortcutOverrides)
            .disabled(articleCommandActions?.canPerformActions != true)
        }
    }
}
```

- [ ] **Step 2: `FeedCommands.swift` vollständig aktualisieren**

Vollständiger neuer Inhalt von `Feedivo/App/FeedCommands.swift`:

```swift
import SwiftUI

struct FeedCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    @FocusedValue(\.feedCommandActions)
    private var feedCommandActions

    @AppStorage(KeyboardShortcutOverrides.storageKey)
    private var shortcutOverridesRawValue = KeyboardShortcutOverrides().rawValue

    private var shortcutOverrides: KeyboardShortcutOverrides {
        KeyboardShortcutOverrides.resolved(from: shortcutOverridesRawValue)
    }

    var body: some Commands {
        CommandMenu(L10n.feedCommandsMenu) {
            Button(L10n.feedAddCommand) {
                feedCommandActions?.requestAddFeed()
            }
            .customizableKeyboardShortcut(.feedAdd, overrides: shortcutOverrides)
            .disabled(feedCommandActions?.canAddFeed != true)

            Button(L10n.feedImportOPMLCommand) {
                feedCommandActions?.requestImportOPML()
            }
            .customizableKeyboardShortcut(.feedImportOPML, overrides: shortcutOverrides)
            .disabled(feedCommandActions?.canImportOPML != true)

            Button(L10n.feedExportOPMLCommand) {
                feedCommandActions?.requestExportOPML()
            }
            .customizableKeyboardShortcut(.feedExportOPML, overrides: shortcutOverrides)
            .disabled(feedCommandActions?.canExportOPML != true)

            Divider()

            Button("Verwaltung...") {
                openWindow(id: OrganizerWindowView.windowID)
            }
            .customizableKeyboardShortcut(.feedOrganizerOpen, overrides: shortcutOverrides)

            Button(L10n.statisticsCommand) {
                openWindow(id: StatisticsWindowView.windowID)
            }
            .customizableKeyboardShortcut(.statisticsOpen, overrides: shortcutOverrides)

            Divider()

            Button(L10n.feedRefreshAllCommand) {
                feedCommandActions?.refreshAllFeeds()
            }
            .customizableKeyboardShortcut(.feedRefreshAll, overrides: shortcutOverrides)
            .disabled(feedCommandActions?.canRefreshAllFeeds != true)

            Button(L10n.feedRefreshCommand) {
                feedCommandActions?.refreshSelectedFeed()
            }
            .customizableKeyboardShortcut(.feedRefresh, overrides: shortcutOverrides)
            .disabled(feedCommandActions?.canPerformFeedAction != true)

            Divider()

            Button(L10n.feedDeleteCommand) {
                feedCommandActions?.requestDelete()
            }
            .disabled(feedCommandActions?.canPerformFeedAction != true)
        }
    }
}
```

- [ ] **Step 3: Build ausführen**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Vollständige Testsuite der Datei laufen lassen (Abschluss-Regressionscheck)**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests -parallel-testing-enabled NO`
Expected: PASS (alle Tests in `FeedivoTests.swift`, inkl. der 3 in diesem Plan neu hinzugekommenen)

- [ ] **Step 5: Commit**

```bash
git add Feedivo/App/ArticleCommands.swift Feedivo/App/FeedCommands.swift
git commit -m "Feature: 8 bisher schortcut-lose Menuefunktionen an Shortcuts-Einstellungen angebunden"
```

- [ ] **Step 6: Manuelle Live-Verifikation dokumentieren (nicht automatisierbar)**

Kein computer-use-Zugriff auf native macOS-Apps in dieser Umgebung verfügbar (Projektkonvention,
siehe `CLAUDE.md`). Folgende Punkte bleiben für den Nutzer als manuelle Checkliste offen und sollten
in `CLAUDE.md` unter „Aktuell in Arbeit" als ausstehend vermerkt werden, sobald dieser Plan
abgeschlossen ist:

1. In den Einstellungen unter „Shortcuts" einen der 8 neuen Einträge (z. B. „Archivieren") mit
   Modifier-Taste belegen — Menübefehl in der Menüleiste reagiert korrekt.
2. Denselben Eintrag stattdessen modifier-frei (nur „J") belegen — Warnzeile erscheint, Shortcut
   funktioniert außerhalb von Textfeldern.
3. Bei aktivem modifier-freiem Shortcut in ein Textfeld (Suche, Feed-/Ordner-Umbenennen, Tag-Name,
   Regel-Name) klicken und „J" tippen — der Buchstabe muss im Feld ankommen, der Menübefehl darf
   NICHT auslösen.
4. Leertaste als modifier-freien Shortcut belegen — Badge zeigt „␣", Verhalten identisch zu Punkt 2/3.
5. Bekannte Grenze bewusst gegenprüfen: ein Formularfeld innerhalb eines im WKWebView geladenen
   Original-Artikels — falls hier tatsächlich eine Kollision auftritt, als neuen Gotcha in
   `CLAUDE.md` dokumentieren statt stillschweigend zu ignorieren.

---

## Self-Review-Notiz für den Plan-Autor (nicht Teil der Ausführung)

- Spec-Abdeckung: Alle 6 Architektur-Abschnitte der Spec (Datenmodell, Recorder, Text-Feld-Schutz,
  Einstellungen-UI, Menü-Verdrahtung, Lokalisierung) sind auf Tasks 1-8 abgebildet — keine Lücke.
- Platzhalter-Scan: keine TBD/TODO-Stellen; jeder Code-Block ist vollständig, keine
  „analog zu Task N"-Verweise ohne ausgeschriebenen Code.
- Typkonsistenz geprüft: `defaultSpec: KeyboardShortcutSpec?` (Task 1) wird in Task 1/6 konsistent
  verwendet; `needsTextFieldGuard(for: KeyboardShortcutSpec) -> Bool` (Task 6) wird in Task 7 mit
  identischer Signatur aufgerufen; `TextEditingFocusMonitor.shared.isEditingText: Bool` (Task 5)
  wird in Task 6 identisch referenziert.
