# NSTableView-Artikelliste

Stand: 2026-07-03

## Ziel

Die mittlere Artikelliste von Feedivo soll intern von einer SwiftUI-`List` auf
eine `NSTableView`-basierte macOS-Liste umgestellt werden. Die Änderung ist ein
Performance- und PowerUser-Slice: Feedivo bleibt visuell Feedivo, aber die heiße
Listenfläche bekommt die präzisere AppKit-Tabellenmechanik, die auch
NetNewsWire auf macOS nutzt.

Die Oberfläche soll nicht redesignen. Ziel ist eine optisch möglichst nahe
Nachbildung der aktuellen `ArticleRowView`: Vorschaubild oder Fallback,
Titel, Feed/Datum, Summary, Ungelesen-Punkt, Offline-Indikator und Stern.

## Nicht-Ziele

- Keine Änderung an Sidebar, Reader, Settings, Add Feed, OPML oder First-Run.
- Keine neue Datenbanklogik und keine Änderung an `TimelineStore`.
- Keine Multi-Selection im ersten Slice.
- Kein Spaltenmodus und keine sortierbaren Tabellenköpfe im ersten Slice.
- Kein Drag & Drop.
- Keine Erhöhung oder Neugestaltung des Timeline-Limits.

## Architektur

`SQLiteFeedArticleListView` bleibt der SwiftUI-Container für Suche, Toolbar,
Empty States, Sortierung, Filterung und `SQLiteFeedArticleListState`. Nur der
innere SwiftUI-`List(selection:)`-Block wird durch eine AppKit-Brücke ersetzt.

Geplante Struktur:

```text
SQLiteFeedArticleListView
  ├─ Suchleiste, Toolbar, Empty States bleiben SwiftUI
  └─ SQLiteArticleTableViewRepresentable
       └─ NSScrollView
          └─ NSTableView
             └─ FeedivoArticleTableCellView
```

Die neue Tabelle arbeitet weiterhin mit `ArticleListSnapshot`. Dadurch bleibt
die Datenquelle unverändert SQLite-first:

```text
TimelineStore
→ SQLiteFeedArticleListState.rows
→ filteredRows / visibleRows
→ NSTableView dataSource
→ selectedArticleID Binding
→ SQLiteReaderView
```

## Komponenten

### `SQLiteArticleTableView`

Neue SwiftUI-Brücke als `NSViewRepresentable`. Sie erhält:

- `rows: [ArticleListSnapshot]`
- `selectedArticleID: Binding<String?>`
- Aktions-Closures für Stern, gelesen/ungelesen, Archiv, Kontextmenü-Aktionen
- optional später: `scrollToSelectedArticle`

Die Brücke erstellt eine `NSScrollView` mit eingebetteter `NSTableView`.
Die Tabelle hat im ersten Slice eine einzelne Spalte ohne sichtbaren Header.
Die Zeilenhöhe orientiert sich an der aktuellen SwiftUI-Zeile.

### Coordinator / Data Source / Delegate

Der Coordinator hält die aktuellen Rows, synchronisiert Selection und liefert
Zellen an `NSTableView`.

Wichtige Aufgaben:

- Row Count liefern
- `ArticleListSnapshot` für Zeilen nachschlagen
- Selection aus AppKit nach SwiftUI melden
- externe `selectedArticleID`-Änderungen in der Tabelle auswählen
- Kontextmenü für die Zeile erzeugen
- Doppelklick oder Enter später optional anbinden

### `FeedivoArticleTableCellView`

Native AppKit-Zelle, die die bisherige Row-Optik nachbildet.

Erste Version:

- quadratische Preview-Fläche mit Fallback-Symbol
- Titel mit fetterem Gewicht für ungelesene Artikel
- Feedname und relatives Datum als Metazeile
- Summary mit zwei Zeilen
- blauer Ungelesen-Punkt
- Offline-Indikator
- Stern-Button rechts

Remote-Bilder können im ersten Slice konservativ behandelt werden. Wenn die
bestehende SwiftUI-`CachedRemoteImageView` nicht sinnvoll wiederverwendbar ist,
bekommt die AppKit-Zelle zunächst Fallback/geladene Systemdarstellung; Bildcache
und Async-Loading können danach separat verfeinert werden. Das darf die
Grundmigration nicht blockieren.

## Verhalten

Selection bleibt über `selectedArticleID` gesteuert. Wenn der Benutzer eine
Zeile auswählt, wird `selectedArticleID` gesetzt und `SQLiteReaderView` lädt wie
bisher den Detailartikel.

Wenn `visibleRows` neu berechnet wird, aktualisiert die Brücke die Tabelle. Im
ersten Slice ist `reloadData()` akzeptabel. Danach kann gezielt auf
Row-Diffing/Reload einzelner sichtbarer Zeilen optimiert werden.

Statusänderungen bleiben an die bestehenden Aktionen angeschlossen:

```text
Stern/Gelesen/Archiv
→ ArticleStatusStore / SQLiteFeedArticleListState
→ Snapshot-Reload
→ NSTableView reload
```

Die bestehende Toolbar, Suchleiste, Sortierung, Filterung, Empty States und der
Button zum Einblenden gelesener Artikel bleiben in `SQLiteFeedArticleListView`.

## Fehlerbehandlung

Fehlerzustände bleiben im SwiftUI-Container:

- SQLite fehlt
- Feed fehlt
- Artikel konnten nicht geladen werden
- Keine Treffer / leerer Feed

Die AppKit-Tabelle rendert nur gültige Rows. Wenn keine Rows sichtbar sind,
bleibt die bestehende SwiftUI-Empty-State-Logik zuständig.

## Tests und Verifikation

Manuelle Prüfung:

- Feed auswählen und Artikel anzeigen.
- Tag, Smart Filter und Smart Folder auswählen.
- Suche nutzen.
- Sortierung und Filter ändern.
- Artikel auswählen und Reader prüfen.
- Stern toggeln.
- Gelesen/Ungelesen toggeln.
- Archiv toggeln.
- Kontextmenü-Aktionen prüfen.
- Button zum Einblenden gelesener Artikel prüfen.
- Scrollen mit vielen Artikeln prüfen.

Technische Verifikation:

- `xcodebuild` für Feedivo ausführen.
- Falls möglich: vorhandene Unit Tests ausführen.
- Nach dem Umbau Screenshots gegen den aktuellen Stand prüfen, damit die
  Änderung nicht als Redesign wirkt.

## Entscheid

Feedivo migriert die mittlere Artikelliste auf eine native `NSTableView`, aber
nur als isolierte Hybrid-Komponente. SwiftUI bleibt für Shell, Sidebar, Reader,
Toolbar und Empty States erhalten. Die erste Version priorisiert
Funktionsgleichheit und optische Nähe; tiefere PowerUser-Features wie
Multi-Selection, Spalten oder fein granularer Row-Diff folgen erst nach dieser
Basis.
