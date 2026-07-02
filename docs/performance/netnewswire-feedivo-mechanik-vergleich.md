# NetNewsWire vs. Feedivo: Mechanik- und Performance-Vergleich

Stand: 2026-07-02

Diese Notiz hält die Erkenntnisse aus dem Codevergleich zwischen NetNewsWire
(`/Users/martinfelder/Developer/NetNewsWire-main`) und Feedivo fest. Es geht
nicht um Design, sondern um Mechanik: Feed-Verwaltung, Refresh, Persistenz,
Artikelliste, Suche und Reader.

## Kurzfazit

Feedivo ist nach den letzten Performance-Slices deutlich näher an NetNewsWire:
Feedivo nutzt inzwischen Conditional GET, Body-Hash-Skip, Batch-Refreshes mit
eigenen SwiftData-Kontexten, leichte Fetch-Descriptoren, Feednamen-Snapshots,
Reader-Background-Snapshots und Snapshot-basierte Artikelzeilen.

Die wichtigsten verbleibenden Unterschiede liegen nicht mehr bei kleinen
Zeilenoptimierungen, sondern bei tieferen Architekturentscheidungen:

- NetNewsWire trennt Artikelinhalt und Artikelstatus in der Persistenz.
- NetNewsWire nutzt eine eigene SQLite-Schicht mit gezielten SQL-Abfragen,
  Status-Cache und Suchindex.
- NetNewsWire kontrolliert Timeline-Fetches zentral über cancellable Operations.
- NetNewsWire rendert die Artikelliste per `NSTableView` und lädt bei
  Statusänderungen nur betroffene sichtbare Zellen neu.
- Feedivo nutzt SwiftData und SwiftUI-`@Query`; dadurch ist die Implementierung
  moderner und einfacher, aber bei sehr großen Datenmengen weniger präzise
  steuerbar.

## 1. Artikel und Status

### NetNewsWire

NetNewsWire trennt Artikel und Status bewusst:

- `Modules/Articles/Sources/Articles/Article.swift`
- `Modules/Articles/Sources/Articles/ArticleStatus.swift`
- `Modules/ArticlesDatabase/Sources/ArticlesDatabase/ArticlesTable.swift`
- `Modules/ArticlesDatabase/Sources/ArticlesDatabase/StatusesTable.swift`
- `Technotes/ArticlesAndStatuses.markdown`

Der Artikel ist weitgehend immutable. Statuswerte wie gelesen/ungelesen,
Favorit und `dateArrived` liegen in einer separaten `statuses`-Tabelle.
NetNewsWire kann Statusdaten sogar behalten, wenn alte Artikel bereits gelöscht
wurden. Dadurch erkennt die App später wieder auftauchende alte Artikel besser
und muss beim Lesen nicht den kompletten Artikel-Datensatz als geändert
behandeln.

### Feedivo

Feedivo speichert Status direkt im SwiftData-`Article`:

- `Feedivo/Models/Article.swift`

Relevante Felder:

- `isRead`
- `isStarred`
- `isArchived`
- `isHidden`
- `offlineStateRaw`

### Auswirkung

Statusänderungen betreffen in Feedivo dasselbe SwiftData-Modell wie Titel,
Summary, Content, Feed-ID und Offline-Daten. Das kann mehr SwiftData-
Invalidierungen und SwiftUI-Updates auslösen als NetNewsWires getrennte
Status-Tabelle.

Feedivo hat diesen Nachteil bereits entschärft:

- `Feed.unreadCount` wird nicht mehr pro Listenwechsel breit neu berechnet.
- Auto-Lesen bündelt Feed-Zähler-Updates.
- `ArticleRowView` rendert sichtbare Werte über `ArticleListItemSnapshot`.
- Feednamen kommen über `feedID -> title`-Snapshots statt über Relationships.

### Möglicher nächster Schritt

Ein separates `ArticleStatus`-SwiftData-Modell wäre der größte strukturelle
Schritt in Richtung NetNewsWire. Das ist aber invasiv: Migration,
Query-Umbau, Reader, Export, Regeln, Smart Folders und iCloud Sync müssten
mitgezogen werden.

Pragmatischer Zwischenweg: Status-spezifische Aktionen weiter bündeln und
Status-Änderungen konsequent über kleine Update-Pfade führen.

## 2. Artikelliste und Timeline

### NetNewsWire

NetNewsWire nutzt AppKit:

- `Mac/MainWindow/Timeline/TimelineViewController.swift`
- `Mac/MainWindow/Timeline/TimelineTableView.swift`
- `Mac/MainWindow/Timeline/Cell/TimelineCellData.swift`
- `Mac/MainWindow/Timeline/Cell/TimelineTableCellView.swift`

Wichtige Mechanik:

- Die Timeline hält ein `ArticleArray`.
- Wenn dieselben Artikel in derselben Reihenfolge bleiben, ruft sie nur
  `reloadVisibleCells()` auf.
- `articleRowMap` mappt `articleID -> rowIndexes`.
- Status-/Icon-/Avatar-Änderungen laden nur sichtbare betroffene Zellen neu.
- `NSTableView` virtualisiert Zeilen sehr direkt und kontrollierbar.

### Feedivo

Feedivo nutzt SwiftUI:

- `Feedivo/Views/ArticleList/ArticleListView.swift`
- `Feedivo/Views/ArticleList/ArticleRowView.swift`
- `Feedivo/Views/ArticleList/ArticleListItemSnapshot.swift`
- `Feedivo/Views/ArticleList/ArticleListQuery.swift`

Wichtige Mechanik:

- SwiftData-`@Query` liefert Artikel pro Feed, Tag, Smart Filter oder Smart
  Folder.
- Fetches sind limitiert (`initialFetchLimit = 50`, Batchgröße 50).
- `propertiesToFetch` vermeidet schwere Felder wie `content` und
  `offlineContent`.
- `ArticleListPreparedArticles` sortiert und filtert gemeinsam.
- `ArticleRowView` hält selbst keine `Article`-Property mehr und rendert über
  `ArticleListItemSnapshot`.

### Auswirkung

Feedivo hat die größten SwiftUI-Listenprobleme reduziert, aber NetNewsWire hat
weiterhin mehr Kontrolle darüber, welche sichtbaren Zeilen wann neu geladen
werden. SwiftUI entscheidet mehr selbst, welche Views invalidiert werden.

### Möglicher nächster Schritt

Nicht sofort alles umbauen. Sinnvoll wäre zuerst Profiling mit großem
Datenbestand. Wenn die Artikelliste weiter auffällig ist, wäre der nächste
Umbau:

- Listen stärker über leichte Snapshot-/ID-Arrays führen.
- `Article` erst für Aktionen, Reader und Export nachladen.
- Selektionszustand stärker über `Article.id`/`PersistentIdentifier` statt über
  lebende `Article`-Objekte führen.

## 3. Fetch-Schicht für Artikellisten

### NetNewsWire

NetNewsWire kapselt Timeline-Fetches:

- `Shared/Timeline/FetchRequestQueue.swift`
- `Shared/Timeline/FetchRequestOperation.swift`
- `Modules/Account/Sources/Account/ArticleFetcher.swift`
- `Modules/Account/Sources/Account/SingleArticleFetcher.swift`

Mechanik:

- Fetches sind cancellable.
- Neue Sidebar-Auswahl kann alte Fetches abbrechen.
- `fetchSerialNumber` verhindert, dass veraltete Ergebnisse später noch die UI
  überschreiben.
- Read-Filter werden pro Sidebar-Item berücksichtigt.

### Feedivo

Feedivo nutzt mehrere gezielte SwiftData-Queries:

- `FeedArticleListContent`
- `TagArticleListContent`
- `SmartFilterArticleListContent`
- `SmartFolderArticleListContent`

Diese Views initialisieren jeweils ihre eigene `@Query` mit einem passenden
`FetchDescriptor`.

### Auswirkung

Feedivo hat gute Query-Spezialisierung, aber keine zentrale Fetch-Queue für die
Artikelliste. SwiftData/SwiftUI steuert die Query-Lebensdauer stärker selbst.
Bei schnellen Scope-Wechseln ist NetNewsWires explizite Abbruchlogik klarer.

### Möglicher nächster Schritt

Nur relevant, wenn Profiling Scope-Wechsel oder Suchwechsel als Problem zeigt.
Dann könnte eine eigene `ArticleListDataSource` entstehen, die Snapshots lädt,
veraltete Tasks verwirft und SwiftUI nur fertige Ergebnis-Snapshots gibt.

## 4. Persistenz: SQLite vs. SwiftData

### NetNewsWire

NetNewsWire nutzt eine eigene SQLite/FMDatabase-Schicht:

- `Modules/ArticlesDatabase/Sources/ArticlesDatabase/ArticlesDatabase.swift`
- `Modules/ArticlesDatabase/Sources/ArticlesDatabase/ArticlesTable.swift`
- `Modules/ArticlesDatabase/Sources/ArticlesDatabase/StatusesTable.swift`
- `Modules/ArticlesDatabase/Sources/ArticlesDatabase/SearchTable.swift`

Mechanik:

- Eigene Tabellen und Indizes.
- Gezielte SQL-Abfragen für Artikel, Counts und Status.
- Status-Cache (`StatusCache`).
- eigener Search-Index.
- DB-Arbeit läuft über `DatabaseQueue`.

### Feedivo

Feedivo nutzt SwiftData:

- `@Model` für `Article`, `Feed`, `Tag`, `Rule`, `SmartFolder` usw.
- `FetchDescriptor`
- `propertiesToFetch`
- mehrere `ModelContext`s für Background-Refresh und Reader-Snapshots

### Auswirkung

SwiftData nimmt viel Arbeit ab, lässt aber weniger direkte Kontrolle über
Join-Strategien, Indizes, Status-Cache, FTS/Suche und gezielte Row-Updates.
NetNewsWire kann bei großen Datenmengen genauer bestimmen, was SQLite wirklich
tun soll.

### Möglicher nächster Schritt

Nicht SQLite neu bauen. Für Feedivo ist realistischer:

- noch mehr `propertiesToFetch`
- statusnahe Aktionen klein halten
- Suche nicht über volle SwiftData-Objektlisten laufen lassen
- Smart-Folder-Fallbacks reduzieren

## 5. Suche

### NetNewsWire

NetNewsWire hat eine eigene Such-Tabelle:

- `Modules/ArticlesDatabase/Sources/ArticlesDatabase/SearchTable.swift`
- `ArticlesTable.fetchArticlesMatching(...)`

Die Suche ist Teil der Datenbankschicht.

### Feedivo

Feedivo hat ein eigenes Suchfenster:

- `Feedivo/Views/ArticleList/ArticleSearchWindowView.swift`

Aktuell lädt es:

- alle Artikel per `@Query(sort: \Article.publishedAt, order: .reverse)`
- alle Feeds
- alle Tags

Danach filtert `ArticleSearchWindowState` im Speicher. Der Suchtext ist
debounced, aber die Artikelmenge liegt trotzdem in der View.

### Auswirkung

Bei 100'000 Artikeln ist das einer der klarsten verbleibenden Unterschiede.
Die Suche kann viel Speicher und CPU binden, sobald das Suchfenster geöffnet
wird.

### Möglicher nächster Schritt

Das ist der pragmatisch beste nächste Performance-Slice:

- Suchfenster nicht mehr mit globaler `@Query` auf alle Artikel starten.
- Suchergebnisse über gezielte `FetchDescriptor`s laden.
- Erst ab Suchtext oder aktivem Filter suchen.
- Ergebnislimit einführen.
- Optional später: eigener Suchindex oder normalisierte Suchfelder.

## 6. Refresh und Feed-Skip-Logik

### NetNewsWire

NetNewsWire vermeidet Feed-Arbeit sehr aggressiv:

- `Technotes/AvoidFeedParsing.markdown`
- `Modules/Account/Sources/Account/LocalAccount/LocalAccountRefresher.swift`

Mechanik:

- Conditional GET
- Content-Hash
- Cache-Control-Auswertung
- Mindestabstand zwischen Checks
- Host-Sonderfälle
- Reddit-Limitierung
- bekannte Nicht-Feed-Hosts
- Abbruch bei Daten, die sicher kein Feed sind
- Conditional-GET-Daten werden nach ca. 8 Tagen teilweise verworfen, damit
  fehlerhafte Server nicht dauerhaft `304 Not Modified` erzwingen.

### Feedivo

Feedivo hat bereits:

- Conditional GET
- Body-Hash
- `ETag`/`Last-Modified`
- Skip bei `304 Not Modified`
- Skip bei gleichem Body-Hash
- Batch-Refresh mit eigenen SwiftData-Kontexten
- keine neuen Info-Logs für unveränderte Feeds
- kein SwiftData-Save, wenn Validatoren unverändert sind

Relevante Dateien:

- `Feedivo/Services/FeedService.swift`
- `Feedivo/Services/FeedBackgroundRefreshService.swift`
- `Feedivo/ViewModels/FeedViewModel.swift`

### Auswirkung

Feedivo hat die wichtigsten NetNewsWire-Prinzipien schon übernommen. Offen sind
vor allem NetNewsWires zusätzliche Schutzmechanismen gegen zu häufige oder
offensichtlich sinnlose Feed-Abrufe.

### Möglicher nächster Schritt

Wenn Refresh weiterhin auffällig ist:

- Cache-Control respektieren.
- Mindestabstand pro Feed ergänzen.
- spezielle Hosts/ungültige Hosts früh überspringen.
- Conditional-GET-Validatoren nach längerer Zeit kontrolliert verwerfen.
- Antwortdaten früh abbrechen, wenn sie eindeutig kein Feed sind.

## 7. Retention und alte Statusdaten

### NetNewsWire

NetNewsWire löscht alte Artikel und Statusdaten unterschiedlich:

- `Technotes/DatabaseCleanup.md`

Artikel werden früher gelöscht, Statusdaten bleiben länger. Dadurch kann ein
alter wiederauftauchender Artikel als alt erkannt werden.

### Feedivo

Feedivo hat:

- `ArticleRetentionSettings`
- `ArticleRetentionCleanupService`
- `OrphanedArticleCleanupService`

Status liegt aber im Artikel selbst. Wenn der Artikel gelöscht wird, ist auch
sein Status weg.

### Auswirkung

Feedivo kann alte wiederauftauchende Artikel schlechter von echten neuen
Artikeln unterscheiden, wenn der alte Artikel bereits bereinigt wurde.

### Möglicher nächster Schritt

Separater `ArticleStatus`- oder `SeenArticle`-Store. Weniger invasiv als ein
vollständiger Statusmodell-Umbau wäre eine kleine Tabelle/Modellklasse für:

- stabile Artikel-ID
- Feed-ID
- erstes Ankunftsdatum
- letzter bekannter Lesestatus

Das wäre besonders relevant, wenn Retention aggressiver wird.

## 8. Reader

### NetNewsWire

NetNewsWire rendert Artikel per vorbereitetem HTML in einem `WKWebView`:

- `Shared/Article Rendering/ArticleRenderer.swift`
- `Mac/MainWindow/Detail/DetailWebViewController.swift`
- `Shared/ArticleStyles/ArticleTheme.swift`

Das HTML wird aus Template, CSS und Artikelwerten zusammengesetzt und in eine
WebView geladen. Themes sind CSS-/HTML-basiert.

### Feedivo

Feedivo rendert nativ in SwiftUI:

- `Feedivo/Views/Reader/ReaderView.swift`
- `Feedivo/Views/Reader/ReaderContentRenderer.swift`
- `Feedivo/Views/Reader/ReaderPreparedArticle.swift`
- `Feedivo/Views/Reader/WebContentView.swift`

Feedivo hat zusätzlich:

- nativen SwiftUI-Reader
- Originalansicht per WKWebView
- Vollartikel-Modus per Readability.js
- Background-Loader für schwere Artikelinhalte
- `LazyVStack` für native Reader-Blöcke
- kompakte Cache-Keys mit Text-Fingerprints

### Auswirkung

NetNewsWire gibt lange Artikel an WebKit ab. Feedivo baut native SwiftUI-Blöcke.
Das ist flexibler und macOS-nativ im Look, kann aber bei sehr langen Artikeln
mehr SwiftUI-View-Arbeit erzeugen. Die letzten Optimierungen haben das bereits
reduziert.

### Möglicher nächster Schritt

Nur bei gemessenen Reader-Problemen weiterarbeiten. Denkbare Schritte:

- weitere Reader-Snapshot-Vereinfachung
- sehr lange Artikel optional stärker chunked rendern
- HTML-/Bildblock-Erkennung weiter minimieren

## Priorisierte nächste Maßnahmen

### 1. Suchfenster query-basiert umbauen

Größter pragmatischer Hebel. Aktuell lädt das Suchfenster alle Artikel in die
View. Ziel: Suchergebnisse erst nach Suchtext/Filter laden, mit Limit.

### 2. Profiling mit großem Testbestand

Bevor weitere Listen- oder Reader-Umbauten passieren, sollte gemessen werden:

- Feed wechseln
- Alle Artikel öffnen
- Ungelesen öffnen
- Smart Folder öffnen
- Suche öffnen
- schnell Artikel lesen
- alle Feeds aktualisieren

### 3. Komplexe Smart Folders reduzieren

Datum-/komplexe Smart-Folder-Pfade fallen teilweise auf In-Memory-Filterung
zurück. Das kann bei 100'000 Artikeln teuer sein.

### 4. Refresh-Skip-Logik erweitern

NetNewsWire-artige Ergänzungen:

- Cache-Control
- Mindestabstand
- ungültige Hosts
- Nicht-Feed-Daten früh abbrechen
- Validatoren periodisch verwerfen

### 5. Statusdaten langfristig separieren

Größter Architekturhebel, aber auch größter Umbau. Für v1 nur angehen, wenn
Profiling zeigt, dass Statusänderungen trotz der bisherigen Optimierungen
weiterhin dominieren.

