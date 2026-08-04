# Design: Native Artikelliste (NSTableView-Migration)

**Datum:** 2026-08-04
**Branch:** `feature/native-article-list-nstableview`
**Voraussetzung:** [2026-08-04-nstableview-vs-list-render-benchmark-design.md](2026-08-04-nstableview-vs-list-render-benchmark-design.md)
  (Spike, abgeschlossen — qualitatives Ergebnis: NSTableView-Prototyp fühlte sich beim
  Scrollen spürbar flüssiger an als die SwiftUI-`List`-Baseline, ohne Instruments-Messung)

## Ziel

Sowohl die Hauptartikelliste (`SQLiteFeedArticleListView`, genutzt in Feed-/Tag-/
Smart-Filter-/Smart-Folder-Ansicht) als auch die separate Ergebnisliste im Suchfenster
(`ArticleSearchWindowView`) bekommen eine NSTableView-basierte, reine-AppKit-Zellen-
Implementierung als Alternative zur bisherigen SwiftUI `List` — hinter einem echten
Settings-Schalter, der auch im normalen Release-Build funktioniert (nicht nur
`#if DEBUG`), damit der Umstieg über mehrere Tage im echten Alltagsbetrieb live
verifiziert werden kann, bevor er zum Standard wird.

Der bereits abgeschlossene Render-Benchmark-Spike (`Feedivo/Views/ArticleList/
RenderBenchmark/`) bleibt vollständig unangetastet als `#if DEBUG`-Regressionswächter
bestehen — die hier neu entstehende Produktivimplementierung liegt in eigenen, neuen
Dateien und ist kein Umbau des Spikes.

## Architekturentscheidung: reine AppKit-Zellen statt gehosteter SwiftUI-Zeilen

Der Spike hat bewusst **keine** SwiftUI-Inhalte pro Zeile gehostet, sondern eine reine
AppKit-Zelle gebaut (`NativeArticleRowCellView`), inklusive Cell-Reuse-sicherer
asynchroner Bild-Ladelogik (`NativeArticleImageLoadGuard`). Das war kein Zufall,
sondern der eigentliche Hebel für den gemessenen/gefühlten Performance-Effekt.

Zwei Wege standen zur Wahl:

1. **Reine AppKit-Zellen (gewählt):** `NativeArticleRowCellView` wird zu voller
   Funktionsparität ausgebaut. Mehr neuer AppKit-Code, aber der eigentliche Zweck der
   Migration (Performance) bleibt erhalten.
2. **NSTableView + gehostete SwiftUI-Zeilen (`NSHostingView`):** Deutlich weniger
   neuer Code, aber ungetestet und fraglich, ob das überhaupt schneller wäre als die
   jetzige `List` — der Spike hat diese Variante nie gemessen. Risiko: kompletter
   Migrationsaufwand ohne den gewünschten Effekt. Verworfen.

Kontextmenüs werden über das AppKit-Standardmuster `NSMenuDelegate` +
`tableView.clickedRow` gebaut — im Projekt bisher kein Präzedenzfall, aber etabliertes,
dokumentiertes AppKit-Verhalten ohne das Risikoprofil der bekannten
NSOutlineView+SwiftUI-Hosting-Drag-Gotchas (ADR-008), da hier keine SwiftUI-Inhalte
gehostet werden.

## Umfang

Beide Artikellisten der App werden in diesem Zyklus migriert:

- **Hauptartikelliste** (`SQLiteFeedArticleListView.articleList`) — hoher Funktionsumfang
  (Kontextmenü, Pagination, Sticky Rows, Filter/Sortierung, Lese-Markierung bei Auswahl).
- **Suchfenster-Ergebnisliste** (`ArticleSearchWindowView.resultList`) — deutlich
  schlanker (kein Kontextmenü, keine Pagination, andere Interaktionsmuster).

Beide nutzen bereits denselben Snapshot-Typ (`ArticleListSnapshot`), was Wiederverwendung
auf Datenebene ermöglicht (siehe unten).

**Nicht im Umfang dieses Zyklus:**
- Entfernen der alten SwiftUI-`List`-Implementierung (separate, spätere Entscheidung,
  erst nach mehrtägiger Live-Verifikation)
- Drag & Drop auf Artikelzeilen (existiert heute nicht, wird nicht neu eingeführt)
- Row-Diffing/Insert-Animationen (v1 nutzt `reloadData()` bei geänderten Snapshots,
  identisch zum bereits reviewten Spike-Verhalten)
- Migration weiterer Listen in der App (z. B. Sidebar — bereits auf NSOutlineView,
  siehe ADR-008; Feed-Organizer-Tabellen — außerhalb des Scopes)

## Komponenten

Neue Dateien unter `Feedivo/Views/ArticleList/Native/` (kein `#if DEBUG` — echter
Produktivcode, gated ausschließlich über den neuen Settings-Schalter):

### Hauptliste

- **`NativeArticleListTableView`** — `NSViewRepresentable`-Wrapper, ersetzt die
  `articleList`-Computed-Property in `SQLiteFeedArticleListView` bei aktiviertem
  Schalter. Erhält dieselben Eingaben wie heute: `displayState`/`effectiveRows`,
  Selektions-Binding (`selectedArticleID`), sowie alle bestehenden Callback-Closures
  (`onToggleRead`, `onToggleStarred`, `onToggleArchived`, `onRequestAssignTag`,
  `onCreateRule`, `onCopyLink`, `onOpenOriginal`, `onShareOriginal`, `onOpenInNewTab`,
  `onOpenInWindow`, `onExport`, `onDelete`, `onMarkAllRead`, `loadMore`,
  `showReadArticles`-Trigger). Die komplette State-/Sticky-Row-/Filter-/Sortier-Logik in
  `SQLiteFeedArticleListView`/`SQLiteArticleListDisplayState` bleibt unverändert — nur
  die *Darstellung* wird ausgetauscht, keine Datenfluss-Änderung.

- **`NativeArticleRowCellView`** (Produktiv-Variante, eigenständig von der
  Spike-Version unter `RenderBenchmark/`) — baut die Spike-Zelle zu voller Parität mit
  `ArticleRowView` aus:
  - Bildposition links/rechts/aus (`ArticleListImagePosition`) — Spike hatte nur links
    fest verdrahtet
  - Feedname-Position vor/nach Titel (`ArticleListFeedNamePosition`)
  - Variable Zusammenfassungszeilen 0–3 (`ArticleListSummaryLineCount`) — Spike hatte
    nur binär sichtbar/versteckt
  - Datumsanzeige relativ/absolut (`ArticleDateDisplayMode`) statt fest verdrahtetem
    `DateFormatter`
  - Barrierefreiheits-Label (`setAccessibilityLabel`, spiegelt
    `ArticleRowView.accessibilityLabel`)
  - Stern-Button bleibt wie im Spike bereits funktionierend

- **`NativeArticleListCoordinator`** — `NSObject`, `NSTableViewDataSource`,
  `NSTableViewDelegate`, `NSMenuDelegate`:
  - Zeilenzahl = `visibleRows.count` + Trailing-Rows (siehe unten)
  - Kontextmenü: `menuNeedsUpdate(_:)` baut das Menü frisch anhand von
    `tableView.clickedRow`, identische 13 Aktions-Einträge (+ 3 Trenner)/Titel/
    Aktivierungsbedingungen wie
    `ArticleRowView.contextMenu` heute (Gelesen/Ungelesen, Stern, Trenner, Archiv,
    Tag zuweisen [disabled ohne `hasAvailableTags`], Regel erstellen, Trenner, In neuem
    Tab öffnen, In Fenster öffnen, Link kopieren [disabled ohne `hasOriginalURL`],
    Original öffnen [disabled ohne `hasOriginalURL`], Teilen [disabled ohne
    `hasOriginalURL`], Exportieren, Löschen [destruktiv], Trenner, Alle als gelesen
    markieren)
  - Pagination: bei `state.hasMore` eine zusätzliche Trailing-Row (kleinere feste Höhe,
    `ProgressView`-Äquivalent als `NSProgressIndicator`), ausgelöst über
    `tableView(_:willDisplayCell:forTableColumn:row:)` statt SwiftUIs `onAppear` —
    ruft `state.loadMore()` auf, sobald diese Row kurz vor dem Sichtbarwerden steht
  - "N gelesene Artikel anzeigen"-Footer: zusätzliche Trailing-Row (eigene feste Höhe),
    nur wenn `!showsReadArticles && hiddenReadRowCount > 0` — Klick setzt
    `showsReadArticles = true` über eine Callback-Closure
  - `tableView(_:heightOfRow:)` liefert je nach Zeilentyp `ArticleRowHeightMetrics.height(...)`
    (Inhalts-Rows) oder eine kleinere feste Konstante (Trailing-Rows)
  - Selektion: `tableViewSelectionDidChange` aktualisiert das Binding; programmatische
    Selektions-Updates (z. B. nach automatischem Feed-Sprung) setzen `selectRowIndexes`
    nur bei tatsächlicher Abweichung (`if tableView.selectedRow != index`), identisch
    zum bereits reviewten Spike-Muster in `updateNSView` — verhindert Rückkopplungs-
    schleifen
  - `reloadData()` nur bei tatsächlich geänderten Snapshots (Array-Vergleich), sonst nur
    Coordinator-Referenzen aktualisieren — identisch zum bereits reviewten
    Spike-Verhalten in `NativeArticleTableView.updateNSView`

### Suchfenster-Ergebnisliste

- **`NativeArticleSearchResultTableView`** — eigener, schlankerer
  `NSViewRepresentable`-Wrapper für `ArticleSearchWindowView.resultList`. Kein
  Kontextmenü, keine Pagination (Suchergebnisse werden komplett auf einmal geladen).
  Doppelklick öffnet im Reader-Fenster (nativ über `NSTableView.doubleAction`, ersetzt
  die bisherige `TapGesture(count: 2).exclusively(before:)`-Konstruktion). Return-Taste
  öffnet ebenfalls im Reader-Fenster (über eine kleine `NSTableView`-Subklasse mit
  `keyDown`-Override, die bei `Return` denselben Öffnen-Callback wie `doubleAction`
  auslöst und alle anderen Tasten unverändert an `super.keyDown` durchreicht).
  Einzelklick selektiert (`tableViewSelectionDidChange`), analog zur bisherigen
  `selectedResultID`-Bindung. Pfeiltasten-Navigation kommt nativ von `NSTableView` —
  die bisherigen manuellen `onKeyPress(.downArrow/.upArrow)`-Handler in
  `ArticleSearchWindowView` entfallen für diesen Pfad ersatzlos.
- **`NativeArticleSearchResultCellView`** — eigene, einfachere Zelle nach dem Vorbild
  von `ArticleSearchResultRow`: Titel (2 Zeilen), Feedname + Datum, Zusammenfassung
  (`ReaderContentRenderer.htmlToPlainText`, 2 Zeilen), "Original öffnen"-Button
  (Safari-Symbol, borderless).

### Wiederverwendet unverändert (kein neuer Code)

- **`ArticleRowHeightMetrics`** — bereits reine AppKit-Mathematik
  (`NSLayoutManager`/`NSFont`), rendert-agnostisch, direkt nutzbar für beide neuen
  Zellen.
- **`ImageCacheService`** — Bild-/Favicon-Laden, bereits vom Spike genutzt.
- **`NativeArticleImageLoadGuard`** — Cell-Reuse-sichere Lade-Token-Prüfung, bereits vom
  Spike genutzt und reviewt; wird 1:1 auch von der neuen Produktiv-Zelle verwendet
  (eigene Instanz/Import, kein Umbau des Spike-Codes).

## Rollout-Mechanismus

Neuer Eintrag in `ArticleListDisplaySettings.swift`:

```swift
enum NativeArticleListSettings {
    static let isEnabledKey = "articleList.usesNativeTableView"
    static let defaultIsEnabled = false
}
```

Ein Schalter im Einstellungen-Tab "Artikelliste" (`SettingsView.swift`, dieselbe Stelle
wie Bildposition/Zusammenfassungszeilen/Datumsformat). **Ein einziger, gemeinsamer
Schalter für beide Listen** (Hauptliste + Suchfenster) — bewusst keine zwei getrennten
Schalter, das hält die Beta-Erfahrung konsistent und vermeidet einen halb migrierten
Zwischenzustand, den der Nutzer aktiv verwalten müsste.

`SQLiteFeedArticleListView.articleList` und `ArticleSearchWindowView.resultList`
lesen beide denselben `@AppStorage(NativeArticleListSettings.isEnabledKey)`-Wert und
wählen darüber zwischen ihrer bestehenden `List`-Variante und der jeweiligen neuen
`Native*TableView`-Variante. Die alte SwiftUI-Implementierung wird in diesem Zyklus
nicht gelöscht — das ist eine separate, spätere Entscheidung, die erst nach
mehrtägiger Live-Verifikation im Alltagsbetrieb ansteht.

## Fehlerbehandlung / Edge Cases

- **Leere Liste:** Die bestehenden `ContentUnavailableView`-Leerzustände
  (`articleListEmptyState`, Suchfenster-`emptyState`) bleiben SwiftUI-Views außerhalb
  der Tabelle — bei 0 sichtbaren Zeilen wird die `Native*TableView` gar nicht erst
  gerendert (identisch zur heutigen Verzweigung in `articleContent`/
  `ArticleSearchWindowView.body`).
- **Scope-/Datenwechsel während eines laufenden Bild-Ladevorgangs:** abgedeckt durch
  `NativeArticleImageLoadGuard` (bereits reviewt).
- **Schalter wird während offener Sheets/Popover umgeschaltet:** kein Sonderfall nötig —
  `@AppStorage`-Änderung baut die jeweilige View neu auf, offene Sheets (Export,
  Regel-Erstellung, Tag-Zuweisung, Löschbestätigung) hängen an `SQLiteFeedArticleListView`
  selbst, nicht an der Listendarstellung, und bleiben unberührt.
- **Programmatische Selektionsänderung von außen** (automatischer Feed-Sprung,
  Tastatur-Navigation über `SQLiteArticleNavigationState`): läuft weiterhin über dieselbe
  `selectedArticleID`-Bindung, die die Coordinator-`updateNSView`-Methode konsumiert —
  kein neuer Pfad nötig.

## Testing-Strategie

- **Automatisiert:** Neue headless-AppKit-Tests (analog zum Spike-Muster) für
  `NativeArticleListCoordinator`/`NativeArticleSearchResultTableView`s
  Höhenberechnung, Trailing-Row-Zählung, Kontextmenü-Aufbau (Titel/Aktivierung je
  Snapshot-Zustand) und Selektions-Synchronisierung. Kein Anspruch, SwiftUI-`List`-
  Rendering selbst zu vergleichen (unmöglich headless, siehe Spike-Erkenntnis).
- **Whole-Branch-Review** nach Abschluss aller Implementierungs-Tasks.
- **Manuelle Live-Verifikation durch den Nutzer** (Release-Build, Schalter aktiviert,
  über mehrere Tage Alltagsbetrieb): Kontextmenü (alle 13 Aktions-Einträge inkl. disabled-
  Zustände), Pagination bei einem Feed mit vielen Artikeln, "N gelesene anzeigen"-
  Footer, Tastaturnavigation (Pfeiltasten, bestehender automatischer Feed-Sprung-
  Mechanismus), alle Anzeige-Einstellungs-Kombinationen (Bildposition × Feedname-
  Position × Zusammenfassungszeilen × Datumsmodus × Textgröße), Suchfenster
  (Doppelklick, Return-Taste, Pfeiltasten, "Original öffnen"-Button), Verhalten bei
  Smart-Folder-Sticky-Rows und Cmd-Klick-Ausnahme beim automatischen Lese-Markieren.

## Offene Punkte / Risiken

- Kein hartes Performance-Ziel definiert (der Spike lieferte nur ein qualitatives
  Signal, keine Instruments-Messung) — Erfolgskriterium für "wird Standard" ist der
  subjektive Eindruck des Nutzers nach der Live-Verifikationsphase, nicht eine Kennzahl.
- `NSTableView.doubleAction`/`keyDown`-basierte Interaktion im Suchfenster ist ein neues
  Muster in diesem Projekt (bisherige AppKit-Bridges — `WebContentView`,
  `SidebarOutlineView`, `ShortcutRecorderView` — nutzen es nicht) — kein bekanntes
  Risiko, aber ohne direkten Präzedenzfall im Code.
