# Design: Reader-Toolbar frei anpassbar (Feature 19.4)

**Datum:** 2026-07-18
**Status:** Zur Umsetzung freigegeben

## Kontext

Feature 19.4 ("Toolbar anpassen") stand laut `FEATURES.md` seit 2026-07-10 auf ⏸️ Zurückgestellt.
Ursprünglich geplant war macOS' natives Rechtsklick-„Symbolleiste anpassen…"-Sheet
(`.toolbar(id:)` + `ToolbarItem(id:)` je Element). Dieser Ansatz wurde 2026-07-10 versucht und
noch vor dem Commit wieder verworfen (keine Code-Reste, kein dokumentierter Grund).
Zusätzlich existiert in `CLAUDE.md` ein Gotcha zu genau dieser Stelle: ein früherer Versuch,
die einzelne `ToolbarItemGroup(placement: .primaryAction)` in mehrere unabhängige
`ToolbarItemGroup`-Geschwister aufzuteilen, führte zu einem `NSToolbar`-Layout-Bug (zwei Items
rendern identisch übereinander). Der aktuelle, stabile Zustand ist bewusst **eine einzige**
`ToolbarItemGroup` mit ~14 Controls (`SQLiteReaderView.swift:123–271`).

Dieses Design nutzt deshalb bewusst **keine** native `NSToolbar`-Customization-API, sondern
eine eigene, App-interne Reihenfolge-/Sichtbarkeits-Einstellung — analog zu bereits im Projekt
etablierten Mustern (`CustomizableShortcut`-Registry, `SidebarFeedVisibilitySettings`,
`FeedRecord.sortIndex`).

## Ziel

Der Nutzer kann in den Einstellungen frei festlegen, in welcher Reihenfolge die Icons der
Reader-Toolbar erscheinen und welche davon überhaupt sichtbar sind. Betrifft ausschließlich die
Reader-Toolbar (nicht Sidebar, Artikelliste oder Menubar-Popover).

## Betroffene Toolbar-Elemente (14, Stand heute)

Suche, Original öffnen, Regel erstellen, Stern, Archivieren, Gelesen/Ungelesen, Link kopieren,
Exportieren, Web zurück, Web vorwärts, Drucken, Ansichts-Umschalter (Segmented Picker),
Darstellung (Textformat-Popover), Inspector ein-/ausblenden.

Alle 14 sind gleichberechtigt frei umsortier- und ausblendbar — explizit auch der Segmented
Picker (Ansicht) und der optisch abweichende „titleAndIcon bordered"-Inspector-Button, obwohl
sie sich stilistisch von den übrigen reinen Icon-Buttons unterscheiden. Bewusst akzeptiertes
Restrisiko: an beliebiger Position innerhalb der flachen Icon-Reihe können diese beiden optisch
etwas aus dem Rahmen fallen — kein Blocker, aber beim Live-Test zu beobachten.

## Architektur

### 1. Datenmodell — `ReaderToolbarItem`

Neue Datei `Feedivo/Models/ReaderToolbarItem.swift`:

```swift
enum ReaderToolbarItem: String, CaseIterable, Identifiable, Codable {
    case search, openOriginal, createRule, star, archive, toggleRead
    case copyLink, export, webBack, webForward, print
    case displayModePicker, appearance, inspector

    var id: String { rawValue }
    var titleKey: LocalizedStringKey { … }   // für die Einstellungen-Liste
    var systemImage: String { … }            // Vorschau-Icon in der Liste
}
```

Reihenfolge von `allCases` entspricht der heutigen Standard-Anzeigereihenfolge (Auslieferungszustand).

### 2. Persistenz — `ReaderToolbarSettings`

Neue Datei `Feedivo/Services/ReaderToolbarSettings.swift`, nach dem Vorbild von
`SidebarFeedVisibilitySettings`/`CustomizableShortcut`:

- `@AppStorage`-persistierte, JSON-kodierte `orderedItemIDs: [String]` (vollständige Reihenfolge
  aller 14 Items, unabhängig von Sichtbarkeit) + `hiddenItemIDs: Set<String>`
- `visibleOrderedItems: [ReaderToolbarItem]` — berechnete, gefilterte Anzeigereihenfolge
- **Vorwärtskompatibilität:** Beim Lesen werden `ReaderToolbarItem`-Fälle, die noch nicht in
  `orderedItemIDs` stehen (z. B. ein künftig neu hinzugefügtes Toolbar-Icon), automatisch ans
  Ende angehängt und als sichtbar markiert — sonst blieben neue Features für Bestandsnutzer
  unsichtbar, analog zum bereits etablierten Muster bei `CustomizableShortcut.defaultSpec`.
- `resetToDefault()` setzt `orderedItemIDs`/`hiddenItemIDs` auf den Auslieferungszustand zurück
- Mutationsmethoden für die Einstellungen-UI: Verschieben (`onMove`-kompatibel) und
  Sichtbarkeit umschalten
- Reine `@AppStorage`-Einstellung ohne SQLite-Bezug — Änderungen lösen automatisch ein
  SwiftUI-Reload aus (kein `SQLiteDataInvalidation.bumpStatusVersion()` nötig)

### 3. Einstellungen-UI — neuer Tab „Toolbar"

Neue Datei `Feedivo/Views/Settings/ToolbarSettingsView.swift`, als eigener Tab in
`SettingsView.swift` registriert (analog zum bestehenden „Shortcuts"-Tab):

- `List` mit allen 14 `ReaderToolbarItem`s in gespeicherter Reihenfolge (Icon + Bezeichnung je Zeile)
- `.onMove` für natives SwiftUI-Drag&Drop-Reordering (keine NSOutlineView nötig — reine flache
  Liste ohne Baumstruktur)
- Toggle/Checkbox pro Zeile zum Ein-/Ausblenden
- Button „Standard wiederherstellen" am Fuß der Liste → `ReaderToolbarSettings.resetToDefault()`
- Liest/schreibt direkt gegen `ReaderToolbarSettings`; die Reader-Toolbar reagiert live, ohne
  Neustart

**Unabhängigkeit von Shortcuts/Menü:** Ausblenden eines Toolbar-Icons entfernt nur den
Toolbar-Button. Tastenkombination und Menüleisten-Befehl (`CustomizableShortcut`,
`ArticleCommands`) bleiben unverändert erreichbar — Toolbar-Sichtbarkeit und
Shortcut-/Menü-System sind bereits heute unabhängige Mechanismen.

### 4. Toolbar-Rendering-Umbau — `SQLiteReaderView.swift`

Die äußere Struktur bleibt **exakt eine einzige** `ToolbarItemGroup(placement: .primaryAction)`
(`readerToolbarContent`, aktuell Zeile 123–271) — das war bereits der bestehende Fix für den
dokumentierten `NSToolbar`-Icon-Overlap-Bug. Es werden **keine** neuen, separat registrierten
Toolbar-Items ergänzt, und `.toolbar(id:)`/`ToolbarItem(id:)` bleibt außen vor (das ist der
2026-07-10 bereits verworfene Ansatz).

Der bisher hartkodierte Block aus 6 `ControlGroup`s + Picker + 2 Buttons wird ersetzt durch:

```swift
ForEach(toolbarSettings.visibleOrderedItems) { item in
    toolbarItemView(for: item)
}
.id(toolbarRebuildGeneration)
```

Neue `@ViewBuilder func toolbarItemView(for item: ReaderToolbarItem) -> some View` schaltet über
den Fall und gibt exakt den bisherigen Button-/Picker-Code unverändert zurück — Icon, Help-Text,
bestehende `.disabled(...)`-Bedingungen und `.customizableKeyboardShortcut(...)` (Web-Back,
Web-Forward, Print) bleiben 1:1 erhalten. Die bisherige visuelle `ControlGroup`-Bündelung
(z. B. Stern+Archivieren+Gelesen als optische Einheit) entfällt zugunsten einer flachen Sequenz,
da feste Bündelgrenzen bei freier Umsortierung keinen Sinn mehr ergeben.

Bestehende Laufzeit-Bedingungen (z. B. Web-Zurück/-Vorwärts `.disabled` außerhalb des
Web-Modus) bleiben unangetastet und wirken unabhängig von Position/Sichtbarkeit in der
Nutzer-Konfiguration.

## Testing

- Neue Unit-Tests für `ReaderToolbarSettings` (analog `SidebarFeedVisibilitySettingsTests`):
  Standard-Reihenfolge, Verstecken/Anzeigen, Umsortieren+Persistenz, Vorwärtskompatibilität
  (neuer Case wird automatisch angehängt), Reset-to-Default.
- Reine View-Änderungen in `SQLiteReaderView.swift` bleiben ohne automatisierten Test (kein
  ViewInspector im Projekt) — manuelle Live-Verifikation nötig.

## Manuelle Live-Verifikationscheckliste (für den Implementierungsplan vorzusehen)

1. Neuer „Toolbar"-Tab in den Einstellungen erscheint, zeigt alle 14 Elemente in der
   heutigen Standardreihenfolge.
2. Ein Icon per Drag&Drop verschieben — Reader-Toolbar übernimmt die neue Reihenfolge sofort,
   ohne Neustart.
3. Ein Icon ausblenden — verschwindet aus der Toolbar; zugehöriger Menüpunkt/Shortcut bleibt
   unverändert funktionsfähig.
4. Segmented Picker (Ansicht) und Inspector-Button an eine andere Position verschieben —
   funktionieren weiterhin korrekt, optische Auffälligkeit an ungewöhnlicher Position bewusst
   in Kauf genommen.
5. „Standard wiederherstellen" — setzt Reihenfolge und Sichtbarkeit auf den Auslieferungszustand
   zurück.
6. Bestehende Laufzeit-Bedingungen weiterhin korrekt: Web-Zurück/-Vorwärts nur im Web-Modus
   aktiv, Drucken/Exportieren/etc. bei fehlendem Artikel weiterhin `.disabled`.
7. Vollbild-/Fenstergrößen-Wechsel (bestehender `toolbarRebuildGeneration`-Mechanismus) weiterhin
   ohne Icon-Overlap-Regression.
8. Verhalten in einem Artikel-Popout-Fenster (separates `WindowGroup(for: ArticleWindowRequest.self)`)
   identisch zum Hauptfenster, da dieselbe `SQLiteReaderView` wiederverwendet wird.

## Nicht Teil dieses Features

- Sidebar-, Artikelliste- oder Menubar-Popover-Icons (nur Reader-Toolbar betroffen)
- Natives macOS-Rechtsklick-„Symbolleiste anpassen…"-Sheet (bewusst verworfen, siehe Kontext)
- Neue/zusätzliche Toolbar-Aktionen (reine Anpassbarkeit der bestehenden 14 Elemente)
