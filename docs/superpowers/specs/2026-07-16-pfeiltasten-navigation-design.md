# Design: Pfeiltasten-Navigation (Artikelliste + Reader-Zustandswechsel)

**Datum:** 2026-07-16
**Status:** Vom Nutzer freigegeben, bereit für Implementierungsplan

## Ausgangslage

Nutzerwunsch: reine (modifier-freie) Pfeiltasten sollen grundlegende Navigation ermöglichen —
Hoch/Runter für vorherigen/nächsten Artikel, Rechts für einen zweistufigen Übergang
native Ansicht → eingebettete Originalansicht → externer Browser.

## Rechercheergebnis: Hoch/Runter benötigen keinen neuen Code

`SQLiteFeedArticleListView`s `List(selection: $selectedArticleID)`
(`Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:384`) ist über eine durchgängige
`@Binding`-Kette exakt an denselben State gebunden, den auch die bestehenden ⌘↑/⌘↓-Menübefehle
(`CustomizableShortcut.articleSelectPrevious`/`.articleSelectNext`) mutieren
(`ContentView.swift:39`, `selectedSQLiteArticleID`). macOS' native `List`-Tastatursteuerung
bewegt diese Selektion bei Fokus auf die Liste bereits per Pfeiltaste — SwiftUI unterscheidet
nicht zwischen Maus- und Tastatur-ausgelöster Selektionsänderung, alle bestehenden
`.onChange(of:)`-Seiteneffekte (Gelesen-Markierung, Sticky-Row-Caching, Reader-Snapshot-Reload)
feuern identisch. **Kein Implementierungs-Task nötig** — wird nur als Teil der manuellen
Verifikationscheckliste bestätigt.

## Entscheidungen (mit Nutzer geklärt)

- Fest eingebautes Standardverhalten, NICHT über das Shortcuts-Einstellungssystem anpassbar.
- Hoch/Runter wirken nur, wenn die Artikelliste den Tastaturfokus hat (natives Verhalten,
  keine zusätzliche Scoping-Logik nötig).
- Rechts-Pfeil: `native` → `web` (eingebettete Originalansicht) → externer Browser (bei
  wiederholtem Rechts-Druck im `web`-Zustand: erneutes Öffnen, harmlos).
- Links-Pfeil: `web` → `native` (symmetrischer Rückweg). Im `native`-Zustand oder nach
  Öffnen im Browser tut Links-Pfeil nichts.
- Kein Wirken ohne ausgewählten Artikel oder ohne `originalURL` (analog zur bestehenden
  `.disabled(originalURL == nil)`-Regel am Ansicht-Picker).

## Architektur

### Warum kein `CustomizableShortcut`/`CommandMenu`

Die anpassbaren Shortcuts aus dem vorherigen Feature laufen über echte `NSMenuItem`-
Tastenkürzel — für modifier-freie Kombinationen braucht das den `TextEditingFocusMonitor`-
Schutz, dessen Reaktivität innerhalb von `Commands`-Bodies noch nicht live verifiziert ist
(siehe `CLAUDE.md`, „Aktuell in Arbeit"). Diese Navigation ist außerdem laut
Nutzerentscheidung explizit NICHT anpassbar — ein fester `.onKeyPress`-Handler ist deshalb
sowohl architektonisch einfacher als auch von diesem offenen Risiko unabhängig. Bewährtes
Vorbild im selben Projekt: `ArticleSearchWindowView.swift:269-277`
(`.onKeyPress(.upArrow)`/`.onKeyPress(.downArrow)` für die dortige Ergebnisliste).

### Rechts-/Links-Pfeil-Handler

Neue `.onKeyPress(.rightArrow)`/`.onKeyPress(.leftArrow)`-Modifier in `ContentView.swift`,
angehängt an den Wurzel-Container der Hauptfenster-Inhalte (oberhalb der
`NavigationSplitView`, umschließt sowohl Artikelliste als auch Reader-Spalte). SwiftUIs
`onKeyPress`-Events blubbern die Fokus-Kette hoch, wenn die fokussierte Kind-View sie nicht
selbst konsumiert:
- Die Artikelliste (`List`) konsumiert nur Hoch/Runter für Zeilennavigation, nicht
  Rechts/Links — die Events erreichen den Root-Handler auch bei fokussierter Liste.
- Ein fokussiertes Textfeld (Suche, Umbenennen, Tag-/Regel-Name) konsumiert Rechts/Links
  selbst für Cursor-Bewegung — kollisionsfrei, kein `TextEditingFocusMonitor`-Äquivalent
  nötig, da dies kein `NSMenuItem`-Tastenkürzel ist.

Logik im Handler (Pseudocode, exakte Typen/Namen im Implementierungsplan):

```swift
.onKeyPress(.rightArrow) {
    guard selectedSQLiteArticleID != nil, originalURLAvailable else { return .ignored }
    switch ReaderDisplayMode(rawValue: readerDisplayModeRawValue) {
    case .native:
        readerDisplayModeRawValue = ReaderDisplayMode.web.rawValue
    case .web:
        articleCommandActions?.openOriginal()
    case .none:
        break
    }
    return .handled
}
.onKeyPress(.leftArrow) {
    guard selectedSQLiteArticleID != nil else { return .ignored }
    if ReaderDisplayMode(rawValue: readerDisplayModeRawValue) == .web {
        readerDisplayModeRawValue = ReaderDisplayMode.native.rawValue
        return .handled
    }
    return .ignored
}
```

`originalURLAvailable` entspricht derselben Bedingung, die den bestehenden Ansicht-Picker in
`SQLiteReaderView.swift:208-216` deaktiviert (`originalURL == nil`) — muss im Plan an die
tatsächlich in `ContentView.swift` verfügbare Datenquelle angepasst werden (Snapshot oder
Resolver-Aufruf), nicht neu erfunden werden.

`openOriginal()` ist dieselbe Aktion, die bereits der Menübefehl „Original öffnen" nutzt
(`ArticleCommandActions.openOriginal`, `ArticleCommands.swift:71`) — keine neue
Browser-Öffnungslogik, reine Wiederverwendung.

### Kein neuer State, keine neue Persistenz

`readerDisplayModeRawValue` (`@AppStorage`, `ReaderDisplayMode.storageKey`) ist bereits
vorhanden und wird vom Handler nur gelesen/geschrieben — dieselbe Quelle, die auch der
bestehende Picker in den Reader-Einstellungen nutzt. Kein neues Modell, keine Migration.

## Testing

Reines SwiftUI-`.onKeyPress`-Verhalten in einer komplexen View-Hierarchie ist im Projekt
nicht unit-testbar (kein ViewInspector, siehe bereits etablierte Praxis bei ähnlichen
UI-Änderungen). Die Zustandsübergangs-LOGIK selbst (welcher `ReaderDisplayMode`-Wert bei
welchem Ausgangszustand resultiert) kann als reine Funktion extrahiert und unit-getestet
werden, falls das im Plan sauber isolierbar ist — sonst bleibt es bei manueller
Verifikation.

**Manuelle Live-Verifikationscheckliste (ergänzt die bestehende aus dem vorherigen Feature):**
1. Artikel in der Liste per Klick auswählen, dann Pfeil-Runter/-Hoch drücken — Artikelliste
   navigiert, Reader aktualisiert sich, Gelesen-Markierung/Sticky-Row-Verhalten bleibt
   identisch zu Mausklick-Navigation (sollte bereits ohne Code-Änderung funktionieren).
2. Bei ausgewähltem Artikel in nativer Ansicht Rechts-Pfeil drücken — wechselt zur
   eingebetteten Originalansicht (WKWebView).
3. Nochmals Rechts-Pfeil im Web-Zustand — öffnet den Artikel im externen Standard-Browser.
4. Links-Pfeil im Web-Zustand — wechselt zurück zur nativen Ansicht.
5. **Entscheidender Fokus-Test:** Rechts-/Links-Pfeil funktioniert sowohl direkt nach
   Artikelauswahl (Artikelliste fokussiert) als auch nach Klick in den Reader-Bereich —
   SwiftUI-Fokus-Bubbling über `NavigationSplitView`-Spaltengrenzen ist nicht vorab
   garantiert und muss live bestätigt werden.
6. Ohne ausgewählten Artikel bzw. bei einem Artikel ohne `originalURL`: Rechts-/Links-Pfeil
   tun nichts, keine falsche Reaktion oder Absturz.
7. Rechts-Pfeil in einem fokussierten Textfeld (Suche, Umbenennen) bewegt weiterhin nur den
   Text-Cursor, löst keinen Reader-Zustandswechsel aus.

## Out of Scope

- Kein Wraparound am Anfang/Ende der Artikelliste (bestehendes Verhalten von
  `SQLiteArticleNavigationState` bleibt unangetastet).
- Keine Anpassbarkeit über die Shortcuts-Einstellungen (Nutzerentscheidung).
- Kein Verhalten für die Sidebar (`NSOutlineView`) — Pfeiltasten dort bleiben unangetastet
  (laut Recherche wegen `shouldSelectItem == false` ADR-008-Invariante ohnehin folgenlos).
- Kein zusätzliches Verhalten für die separate Artikel-Popout-Fenster-Szene
  (`ArticleWindowView`) — nur das Hauptfenster (`ContentView`) ist Teil dieses Features.
