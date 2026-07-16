# Design: Shortcuts-Einstellungen — modifier-freie Kombinationen + fehlende Funktionen

**Datum:** 2026-07-16
**Status:** Vom Nutzer freigegeben, bereit für Implementierungsplan

## Ausgangslage

Nutzer-Report: In den Einstellungen unter „Shortcuts" (Feature 19.8, `ShortcutRecorderView.swift`)
lassen sich keine Ein-Zeichen-Shortcuts (z. B. nur `J`) oder Leertaste hinterlegen. Zudem fehlt für
mehrere sinnvolle Menü-Funktionen (Archivieren, Exportieren, Link kopieren, Original öffnen, Teilen,
OPML Import/Export, Verwaltung öffnen) überhaupt ein Shortcut-Eintrag in der Registry.

## Ursache

1. `RecorderNSView.keyDown` (`ShortcutRecorderView.swift:83`) erzwingt bewusst mindestens eine
   Modifier-Taste — Kommentar im Code nennt explizit den Grund: Kollision mit normalem Tippen.
2. `CustomizableShortcut` (`Models/CustomizableShortcut.swift`) enthält nur 12 Fälle; alle übrigen
   `.keyboardShortcut(...)`-Stellen im Code sind bewusst ausgenommene `.defaultAction`-Dialogbuttons
   (Enter-Taste). Acht reale Menü-Aktionen in `ArticleCommands.swift`/`FeedCommands.swift` haben nie
   einen `CustomizableShortcut`-Fall bekommen.

## Entscheidungen (mit Nutzer geklärt)

- Modifier-freie Shortcuts werden erlaubt, mit UI-Warnhinweis — nicht nur für einzelne Kategorien,
  sondern für alle Shortcuts, die der Nutzer manuell so belegt.
- Da die anpassbaren Shortcuts als echte `NSMenuItem`-Tastenkürzel (`CommandMenu`) implementiert
  sind, würde ein ungeschützter modifier-freier Shortcut jede Texteingabe in der App blockieren
  (AppKit prüft Menü-Tastenkürzel vor der normalen Zeicheneingabe, auch ohne Modifier). Deshalb:
  eigener Text-Feld-Schutzmechanismus statt bloßem Entfernen der Sperre (siehe unten).
- Neue anpassbare Funktionen: Artikel archivieren, Artikel exportieren, Link kopieren, Original
  öffnen, Teilen, OPML Import, OPML Export, Verwaltung öffnen. „Feed löschen" bleibt bewusst ohne
  Shortcut-Möglichkeit (sensible, destruktive Aktion — Nutzerentscheidung).

## Architektur

### 1. Datenmodell (`Models/CustomizableShortcut.swift`)

`defaultSpec` wechselt von `KeyboardShortcutSpec` auf `KeyboardShortcutSpec?`. Die bestehenden 12
Fälle behalten ihre konkreten Defaults unverändert. Acht neue Fälle liefern `nil` (kein Shortcut
vorbelegt, taucht in den Einstellungen als „nicht belegt" auf — identisches Verhalten zu heute, wo
diese Aktionen gar keinen Shortcut haben):

```swift
case articleToggleArchived   // .article-Kategorie
case articleCopyLink         // .article
case articleOpenOriginal     // .article
case articleShareOriginal    // .article
case articleExport           // .article
case feedImportOPML          // .feed
case feedExportOPML          // .feed
case feedOrganizerOpen       // .feed
```

`KeyboardShortcutsSettings.spec(for:in:)` bleibt unverändert (`shortcut.defaultSpec` ist jetzt
schon optional-kompatibel, da die Funktion bereits `KeyboardShortcutSpec?` zurückgibt).

### 2. Recorder (`Views/Settings/ShortcutRecorderView.swift`)

`RecorderNSView.keyDown`: `guard !modifiers.isEmpty else { return }` entfällt ersatzlos. Escape
(keyCode 53) bricht weiterhin ab, alle anderen Tasten (inkl. Leertaste, deren
`charactersIgnoringModifiers` bereits `" "` liefert) werden jetzt auch ohne Modifier akzeptiert.

`KeyboardShortcutSpec.displaySymbols` (`Models/KeyboardShortcutSpec.swift`) bekommt eine
Sonderbehandlung: `key == " "` zeigt `"␣"` statt eines unsichtbaren Leerzeichens im Badge.

### 3. Text-Feld-Schutz — `TextEditingFocusMonitor`

Neue Datei `Services/TextEditingFocusMonitor.swift`:

```swift
@Observable
@MainActor
final class TextEditingFocusMonitor {
    static let shared = TextEditingFocusMonitor()
    private(set) var isEditingText = false

    func startObserving() {
        NotificationCenter.default.addObserver(
            forName: NSControl.textDidBeginEditingNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.isEditingText = true }
        NotificationCenter.default.addObserver(
            forName: NSControl.textDidEndEditingNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.isEditingText = false }
    }
}
```

`startObserving()` wird einmalig in `FeedivoAppDelegate.applicationDidFinishLaunching` aufgerufen
(gleiches Registrierungsmuster wie der bestehende `UNUserNotificationCenterDelegate`-Eintrag dort).

`customizableKeyboardShortcut(_:overrides:)` (`Services/KeyboardShortcutsSettings.swift`) wendet bei
modifier-freiem `spec` zusätzlich `.disabled(TextEditingFocusMonitor.shared.isEditingText)` an:

```swift
@ViewBuilder
func customizableKeyboardShortcut(
    _ shortcut: CustomizableShortcut,
    overrides: KeyboardShortcutOverrides
) -> some View {
    if let spec = KeyboardShortcutsSettings.spec(for: shortcut, in: overrides) {
        if spec.modifiers.isEmpty {
            self.keyboardShortcut(spec.keyEquivalent, modifiers: spec.eventModifiers)
                .disabled(TextEditingFocusMonitor.shared.isEditingText)
        } else {
            self.keyboardShortcut(spec.keyEquivalent, modifiers: spec.eventModifiers)
        }
    } else {
        self
    }
}
```

SwiftUI verknüpft mehrere `.disabled(...)`-Aufrufe auf derselben View per OR — bestehende
`.disabled(feedCommandActions?.canPerformFeedAction != true)`-Ketten in `ArticleCommands.swift`/
`FeedCommands.swift` bleiben unverändert wirksam, der neue Aufruf kommt additiv dazu.

**Bekannte Grenze (dokumentiert, nicht gefixt):** Textfelder *innerhalb* einer im `WKWebView`
geladenen Webseite („Originalartikel"-Ansicht) laufen nicht über `NSControl`/`NSTextView` und lösen
die Notifications nicht aus — dort bleibt ein theoretisches Kollisionsrisiko bei modifier-freien
Shortcuts bestehen. Seltener Fall (nur bei Formularfeldern in eingebetteten Artikeln, z. B.
Kommentarfelder). Analog zu bestehenden Projekt-Gotchas wird das als bekannte Einschränkung im
CLAUDE.md-Gotcha-Abschnitt festgehalten, nicht stillschweigend als „gelöst" behandelt.

### 4. Einstellungen-UI (`Views/Settings/SettingsView.swift`, `ShortcutSettingRow`)

Neue Warnzeile unter dem Recorder, sichtbar sobald `spec?.modifiers.isEmpty == true` (unabhängig von
der bestehenden `conflictMessage`-Zeile, beide können gleichzeitig sichtbar sein):

```swift
if let spec, spec.modifiers.isEmpty {
    Text(L10n.shortcutsModifierFreeWarning)
        .font(.system(size: 10.5))
        .foregroundStyle(.orange)
        .padding(.leading, Self.labelColumnWidth + 12)
}
```

Warnhinweis-Text (neuer L10n-Key `shortcuts.modifierFree.warning`): erklärt kurz, dass der Shortcut
bei fokussiertem Textfeld pausiert, mit Verweis auf die WKWebView-Ausnahme in knapper Form, z. B.
„Ohne Zusatztaste — pausiert automatisch, während ein Textfeld fokussiert ist (außer bei Textfeldern
innerhalb eines geladenen Original-Artikels)."

### 5. Neue Menü-Verdrahtung

`ArticleCommands.swift`: `.customizableKeyboardShortcut(...)` ergänzt an den Buttons für
Archivieren (`.articleToggleArchived`), Link kopieren (`.articleCopyLink`), Original öffnen
(`.articleOpenOriginal`), Teilen (`.articleShareOriginal`), Exportieren (`.articleExport`) — jeweils
mit demselben `overrides`-Parameter wie die bestehenden Aufrufe in derselben Datei, bestehende
`.disabled(...)`-Ketten bleiben unangetastet.

`FeedCommands.swift`: analog für OPML Import (`.feedImportOPML`), OPML Export (`.feedExportOPML`),
Verwaltung öffnen (`.feedOrganizerOpen` — dieser Button hängt an keiner `feedCommandActions`-Bedingung,
bekommt also nur den Shortcut-Modifier, kein zusätzliches `.disabled`).

### 6. Lokalisierung

Neue `L10n.swift`-Konstanten + zugehörige `Localizable.xcstrings`-Einträge (manuell ergänzt, da der
Auto-Stub-Mechanismus bei indirekten `L10n`-Keys bekanntlich nicht greift — siehe bestehender Gotcha
in `CLAUDE.md`):

- 8× `shortcuts.label.<neuerFall>` (Zeilen-Beschriftung, analog bestehendem Muster)
- 1× `shortcuts.modifierFree.warning`

## Testing

Erweiterung der bestehenden inline-Testsuite in `FeedivoTests.swift` (Abschnitt ab Zeile ~800, keine
neue Datei nötig — folgt dem bestehenden Muster für dieses Feature):

- `KeyboardShortcutSpec.displaySymbols` liefert `"␣"` für Leertaste-Spec ohne Modifier.
- `RecorderNSView`-Verhalten ist AppKit-Event-getrieben und nicht direkt unit-testbar (bereits
  heute so, kein neuer Testlücken-Typ) — bleibt manuell zu verifizieren.
- `CustomizableShortcut.allCases` enthält die 8 neuen Fälle mit `defaultSpec == nil`.
- `KeyboardShortcutsSettings.spec(for:in:)` liefert weiterhin korrekt `nil`, wenn weder Override
  noch Default existiert (neuer Fall im Vergleich zum bisherigen Verhalten, wo `defaultSpec` nie
  `nil` war — bestehender Test `keyboardShortcutsSettingsFaelltAufDefaultZurueckWennNichtAngepasst`
  bleibt für die alten 12 Fälle unverändert grün).
- `TextEditingFocusMonitor` ist AppKit-Notification-getrieben; ein Unit-Test kann `NotificationCenter`
  direkt eine `textDidBeginEditingNotification`/`textDidEndEditingNotification` posten lassen und
  `isEditingText` danach prüfen (kein echtes `NSTextField` nötig, `object: nil` beim Observer
  akzeptiert jeden Absender).

**Ausstehend nach Implementierung (nicht automatisierbar):** manuelle Live-Verifikation, dass (a)
ein modifier-freier Shortcut in Sidebar-/Artikelliste tatsächlich funktioniert, (b) er beim Tippen
in Suchfeld/Umbenennen-Feld/Tag-Namensfeld pausiert, (c) das Verhalten bei einem Formularfeld
innerhalb eines geladenen Original-Artikels (bekannte Grenze) — konsistent mit dem etablierten
Projektmuster für UI-nahe Änderungen ohne computer-use-Zugriff auf native macOS-Apps.

## Out of Scope

- „Feed löschen" bekommt bewusst keinen Shortcut.
- Keine Änderung an bestehenden, bereits mit Modifier belegten Shortcuts.
- Keine Umstellung der bestehenden Shortcuts auf den neuen `onKeyPress`-Ansatz (verworfene
  Alternative B) — nur die neue Text-Feld-Schutzlogik für modifier-freie Fälle.
