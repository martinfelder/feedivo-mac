# NetNewsWire vs. Feedivo: Mechanik- und Performance-Vergleich

Stand: 2026-07-03

Diese Notiz hält die Erkenntnisse aus dem Codevergleich zwischen NetNewsWire
(`/Users/martinfelder/Developer/NetNewsWire-main`) und Feedivo fest. Es geht
nicht um Design, sondern um Mechanik: Feed-Verwaltung, Refresh, Persistenz,
Artikelliste, Suche und Reader.

## Aktualisierte Momentaufnahme nach SQLite-Feed-Import-Umbau

Diese Liste fasst den aktuellen Stand nur für Feed-Handling und
Artikel-Handling zusammen. Sie ist als Wiedereinstieg gedacht, wenn die
SQLite-Migration später fortgesetzt wird.

### 1. Eigener ArticleStore

**Erledigt im produktiven Feed-/Artikelpfad.**

Feedivo hat inzwischen eine eigene SQLite/GRDB-Schicht für Artikel, Status,
Timeline, Feeds, Logs, Tags und Suche. Der produktive Reader-/Listenpfad nutzt
SQLite-Snapshots und lädt keine SwiftData-Artikel mehr als Hauptquelle.

Wichtige Bausteine:

- `ArticleDatabase` als breite Fassade für Feed-, Feed-Set-, Article-ID-,
  Ungelesen-, Heute-, Starred-, Such- und Count-Abfragen
- `ArticleStore`
- `ArticleStatusStore`
- `TimelineStore`
- `FeedStore`
- `FeedLogStore`
- SQLite-Records und FTS/Search-Strukturen

### 2. Status aus Article herauslösen

**Erledigt.**

Gelesen, Stern, Archiv und Hidden liegen in `article_statuses`. Statusänderungen
schreiben kleine SQLite-Zeilen statt komplette Artikelobjekte zu invalidieren.
Das entspricht der wichtigen NetNewsWire-Idee, Artikelinhalt und Artikelstatus
getrennt zu behandeln.

### 3. Artikelliste nicht mehr über `@Query`

**Erledigt im Produktpfad.**

`SQLiteFeedArticleListView` und `SQLiteFeedArticleListState` laden leichte
SQLite-Snapshots. Der volle Artikel wird separat für `SQLiteReaderView`
nachgeladen. Die alte SwiftData-Artikelliste ist nicht mehr Produktpfad.

### 4. Eigene Timeline-Fetch-Queue

**Erledigt für den SwiftUI-Produktpfad.**

`TimelineStore` und `SQLiteFeedArticleListState` kapseln Timeline-Loads bereits
außerhalb von SwiftData-`@Query`. `SQLiteFeedArticleListState` startet explizite
Timeline-Requests über eine kleine Queue/Operation-Schicht: laufende und
wartende Loads werden bei Scope-/Suchwechsel gecancelt, während eines noch
laufenden Loads bleibt nur der neueste Pending-Request erhalten.

**Rest im Vergleich zu NetNewsWire:** NetNewsWire kann mit `NSTableView` einzelne
sichtbare Zeilen noch granularer neu laden. Feedivo bleibt hier bewusst SwiftUI,
solange reale Lasttests keine Tabellen-Performanceprobleme zeigen.

### 5. Suche als Datenbank-/Index-Funktion

**Erledigt für Listen- und Suchfensterpfad.**

SQLite/FTS ist vorhanden und die Suche lädt nicht mehr pauschal alle
SwiftData-Artikel in die View. Das entspricht NetNewsWires Grundprinzip:
Suche ist Datenbankschicht, nicht UI-Materialisierung.

### 6. Counts aus dem Store

**Erledigt im produktiven Sidebar-/Listenpfad.**

Feed-Zähler, Sidebar-Badges, Status-Badges und Smart-Folder-Counts kommen aus
SQLite-Snapshots oder gezielten Count-Queries. Sidebar und Feed-Zeilen lesen
`FeedSidebarSnapshot`, Tags und Smart Folders lesen SQLite-Snapshots. Die
verbleibende SwiftData-Abhängigkeit ist nicht mehr Anzeige oder Count, sondern
einige Aktionen und Sheets, die noch SwiftData-`Feed` als Übergangsbackend
auflösen.

### 7. Refresh schreibt direkt in den Store

**Weitgehend erledigt, aber noch mit SwiftData-Aktionsbrücke.**

Feed-Refresh, Feed hinzufügen, OPML-Import und First-Run-Wizard schreiben
SQLite-first. Neue Artikel aus diesen Pfaden landen in SQLite. SwiftData bekommt
bei neuen Feeds nur noch eine minimale Feed-Übergangsidentität, damit
verbleibende Aktionspfade während des Übergangs stabil bleiben.

`SQLiteFeedSubscriptionService` kapselt Feed hinzufügen und OPML-Import. Nach
SQLite-Schreibvorgängen wird `SQLiteDataInvalidation.statusVersion` gebumped,
damit Sidebar, Listen und Counts neu laden.

### 8. Retention NetNewsWire-artig

**Grundlegend erledigt.**

Retention löscht SQLite-Artikel feed-basiert, berücksichtigt Feed-Overrides und
schützt eine konfigurierbare Mindestanzahl neuester Artikel pro Feed. Vor dem
Löschen sichert Feedivo die Artikelidentität und den letzten Status nun in
`article_identity_history`. Beim späteren Upsert kann `ArticleStore` diese
Historie über `sourceID`, Link oder Titel-Hash wiederfinden und Gelesen/Stern/
Archiv/Hidden übernehmen.

**Rest im Vergleich zu NetNewsWire:** Feedivo hat damit die wichtigste
Langzeit-Wiedererkennung, aber noch keine separate UI oder Policy für Ablauf,
Debugging oder gezielte Pflege dieser Historie.

### 9. Optional: AppKit-Tabelle für Artikelliste

**Nicht umgesetzt, bewusst offen.**

Feedivo bleibt aktuell bei SwiftUI. Da die Liste inzwischen leichte
SQLite-Snapshots nutzt, sollte zuerst mit großen realen Datenbeständen gemessen
werden. Eine `NSTableView`-basierte Liste wäre erst sinnvoll, wenn SwiftUI trotz
SQLite-Snapshots messbar nicht reicht.

## Aktuell größter Restblock

Feedivo ist beim Artikel-Handling inzwischen deutlich NetNewsWire-artiger. Der
Feed-Handling-Block ist inzwischen teilweise geschlossen:

- [x] Sidebar-Anzeige und Artikellisten-Routing weg von `@Query [Feed]` —
  Sidebar nutzt nur noch `SQLiteSidebarState.snapshots`, ContentView routet
  ausgewählte Feeds per SQLite-Feed-ID in `SQLiteFeedArticleListView`.
- [x] Feed-Auswahl vollständig über SQLite-Feed-ID: `SidebarSelection.feed`
  trägt `FeedRecord.id` (String); Artikelliste bekommt `init(feedID:)`.
- [x] `FeedRowView` rendert aus `FeedSidebarSnapshot`; `FeedPropertiesView`/
  `FeedRenameView` laden `FeedRecord` via `FeedStore.feed(id:)`.
- [x] Timeline-Loads laufen über eine cancellable latest-wins
  Queue/Operation-Schicht.
- [x] Listen- und Suchfenster-Suche laufen über SQLite/FTS.
- [ ] temporäre SwiftData-Feed-Bridge entfernen — SwiftData `Feed` ist nur noch
  Aktionsbackend (Refresh/Delete/Badge/OPML/Wizard) und wird per ID aufgelöst.
- [ ] Verbleibende `ContentView`-Abhängigkeiten von `@Query [Feed]` entfernen:
  First-Run-Entscheidung, OPML-/Wizard-Übergabe, Refresh-All/Delete/Feed-Menü und
  Dock-Badge müssen direkt aus SQLite-Snapshots/Stores funktionieren.
- [ ] alte SwiftData-Fallbacks löschen oder hart isolieren, sobald diese
  Restabhängigkeiten weg sind.
- [ ] `FeedViewModel` weiter verschlanken, sodass Feed-Abo, Refresh und
  Artikelstore stärker in dedizierten Services liegen.

Kurzfassung: **Artikel-Handling ist größtenteils SQLite-/NetNewsWire-artig.
Feed-Navigationsidentität ist SQLite-only (Feed-ID). Offen ist das Entfernen der
verbleibenden SwiftData-Feed-Brücke und der `ContentView`-Restabhängigkeiten von
`@Query [Feed]` — Folge-Slice `sqlite-only-feed-bridge-removal`.**

## Kurzfazit

Feedivo ist nach den letzten SQLite-Slices deutlich näher an NetNewsWire:
Feedivo nutzt inzwischen SQLite/GRDB für den produktiven Feed-/Artikelpfad,
Conditional GET, Body-Hash-Skip, SQLite-first Refreshes, getrennte Statuszeilen,
FTS-Suche, cancellable latest-wins Timeline-Queue, Feednamen-Snapshots,
Reader-SQLite-Snapshots und Snapshot-basierte Artikelzeilen.

Die wichtigsten verbleibenden Unterschiede liegen nicht mehr bei kleinen
Zeilenoptimierungen, sondern bei tieferen Architekturentscheidungen:

- NetNewsWire rendert die Artikelliste per `NSTableView` und kann bei
  Statusänderungen einzelne sichtbare Zellen noch granularer neu laden.
- NetNewsWire behält alte Status-/Seen-Metadaten länger als Artikelinhalte.
- NetNewsWire hat eine Account-Schicht für lokale und Sync-Accounts; Feedivo ist
  aktuell lokal SQLite-first und hält Sync bewusst zurück.
- Feedivo nutzt noch SwiftData als Übergangsbackend für einige Feed-Aktionen und
  First-Run-/OPML-/Refresh-All-Übergaben.

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

Feedivo speichert produktive Artikelstatus inzwischen in SQLite:

- `Feedivo/Database/Records/ArticleStatusRecord.swift`
- `Feedivo/Stores/ArticleStatusStore.swift`
- Tabelle `article_statuses`

SwiftData-`Article` existiert noch als Legacy-/Übergangsmodell, ist aber nicht
mehr die Statusquelle für den produktiven Listen-/Reader-Pfad.

### Auswirkung

Statusänderungen betreffen nicht mehr den vollständigen Artikelinhalt.
`ArticleStatusStore` aktualisiert kleine Statuszeilen, korrigiert
`feeds.unreadCount` und bump't `SQLiteDataInvalidation.statusVersion`, damit
Sidebar und Listen gezielt neu laden.

### Möglicher nächster Schritt

Nächster NetNewsWire-artiger Schritt ist nicht mehr Status-Separierung, sondern
eine kleine Historientabelle für gelöschte/alte Artikelidentitäten, falls
Retention aggressiver werden soll.

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

Feedivo nutzt im Produktpfad SwiftUI mit SQLite-Snapshots:

- `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift`
- `Feedivo/ViewModels/SQLiteFeedArticleListState.swift`
- `Feedivo/Stores/TimelineStore.swift`
- `Feedivo/Views/ArticleList/ArticleRowView.swift`
- `Feedivo/Views/ArticleList/ArticleListItemSnapshot.swift`

Wichtige Mechanik:

- `TimelineStore` liefert leichte `ArticleListSnapshot`s per SQL.
- Feed-, Tag-, SmartFilter- und SmartFolder-Scopes laufen über SQLite.
- Suchtext wird mit SQLite/FTS kombiniert.
- `ArticleRowView` hält keine lebenden `Article`-Objekte mehr und rendert über
  Snapshots.

### Auswirkung

Feedivo hat die frühere SwiftData-Listenmaterialisierung ersetzt. Der relevante
Unterschied zu NetNewsWire ist nun nur noch die Rendering-Schicht:
`NSTableView` gibt NetNewsWire mehr Kontrolle über sichtbare Zellen, während
Feedivo SwiftUI-Listen nutzt.

### Möglicher nächster Schritt

Nicht sofort auf AppKit umbauen. Erst mit großem Datenbestand messen, ob
SwiftUI-Listen mit SQLite-Snapshots reichen. Ein `NSTableView`-Umbau ist nur
dann sinnvoll, wenn Profiling sichtbare Listeninvalidierungen als Problem zeigt.

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

Feedivo nutzt `SQLiteFeedArticleListState` als kleine Fetch-Koordination:

- `SQLiteTimelineLoadRequest`
- `SQLiteTimelineLoadScope`
- `SQLiteTimelineLoadOperation`
- `SQLiteTimelineLoadQueue`
- latest-wins Pending-Request: laufende und wartende Requests werden gecancelt,
  nur der neueste wartet auf den Abschluss des aktuellen Loads
- `ArticleDatabase`/`TimelineStore` für die eigentlichen SQL-Fetches

### Auswirkung

Feedivo hat die wichtigste NetNewsWire-Mechanik übernommen: Timeline-Loads laufen
nicht mehr als unkoordinierte Einzel-Tasks, sondern durch eine kleine
Queue/Operation-Schicht. Alte Loads werden abgebrochen, mittlere Pending-Loads
werden ersetzt und verspätete Ergebnisse dürfen die aktuelle Liste nicht mehr
überschreiben.

### Möglicher nächster Schritt

Nur relevant, wenn Profiling weitere Probleme zeigt: die interne Queue könnte in
eine eigene Datei ausgelagert werden, damit sie getrennt vom SwiftUI-State
getestet werden kann.

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

Feedivo nutzt für den produktiven Feed-/Artikelpfad SQLite/GRDB:

- eigene Tabellen und Migrationen für Feeds, Artikel, Status, Logs, Tags,
  Regeln, Smart Folders, FTS und Offline-Inhalte
- `ArticleDatabase` als breite Fassade für allgemeine Artikel-Fetches, Suche,
  Reader-Daten, Statusänderungen und aggregierte Counts
- gezielte Stores wie `ArticleStore`, `TimelineStore`, `FeedStore`,
  `ArticleStatusStore`, `TagStore`
- SwiftData bleibt noch Übergangsbackend für einige Feed-Aktionen und alte
  Modelle, nicht mehr Hauptpersistenz der heißen Artikeldaten.

### Auswirkung

Feedivo hat die Kontrolle über Joins, Indizes, FTS/Suche und gezielte
Status-Updates inzwischen in SQLite verlagert. Der verbleibende Unterschied ist
nicht mehr die Artikelpersistenz, sondern die noch nicht vollständig entfernte
SwiftData-Feed-Brücke in `ContentView`/`FeedViewModel`.

### Möglicher nächster Schritt

Nächster Schritt ist `sqlite-only-feed-bridge-removal`: `ContentView` und
Feed-Menü-/Refresh-/Delete-/OPML-/Wizard-Übergaben sollen keine SwiftData-
`Feed`-Arrays mehr brauchen.

## 5. Suche

### NetNewsWire

NetNewsWire hat eine eigene Such-Tabelle:

- `Modules/ArticlesDatabase/Sources/ArticlesDatabase/SearchTable.swift`
- `ArticlesTable.fetchArticlesMatching(...)`

Die Suche ist Teil der Datenbankschicht.

### Feedivo

Feedivo hat ein eigenes Suchfenster und SQLite/FTS:

- `Feedivo/Views/ArticleList/ArticleSearchWindowView.swift`
- `ArticleStore.searchArticles(state:)`
- `TimelineStore` kombiniert Suchtext mit Feed-, Tag-, SmartFilter- und
  SmartFolder-Scopes.

### Auswirkung

Der frühere Hauptunterschied ist geschlossen: Das Suchfenster materialisiert
nicht mehr alle SwiftData-Artikel. Suche ist jetzt Datenbankschicht.

### Möglicher nächster Schritt

Nur noch Profiling-/Qualitätsthemen bleiben: Ranking, Ergebnislimits, leere
Suche und FTS-Tokenizer können später verfeinert werden.

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
- Batch-Refresh und SQLite-first Refresh über `SQLiteFeedRefreshService`
- keine neuen Info-Logs für unveränderte Feeds
- kein SwiftData-Save, wenn Validatoren unverändert sind

Relevante Dateien:

- `Feedivo/Services/FeedService.swift`
- `Feedivo/Services/SQLiteFeedRefreshService.swift`
- `Feedivo/ViewModels/FeedViewModel.swift`

### Auswirkung

Feedivo hat die wichtigsten NetNewsWire-Prinzipien schon übernommen und schreibt
Refresh-Ergebnisse direkt in SQLite. Offen sind vor allem NetNewsWires
zusätzliche Schutzmechanismen gegen zu häufige oder offensichtlich sinnlose
Feed-Abrufe.

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

Status liegt separat in `article_statuses`. Vor dem Löschen alter SQLite-Artikel
schreibt `ArticleRetentionCleanupService` nun zusätzlich eine langlebigere
`article_identity_history`-Zeile. Diese Historie enthält stabile Quellen-ID,
Link, Titel-Hash, Seen-Zeitpunkte und den letzten Gelesen/Stern/Archiv/Hidden-
Status.

### Auswirkung

Feedivo kann alte wiederauftauchende Artikel nun wiedererkennen, auch wenn der
eigentliche Artikel und seine `article_statuses`-Zeile bereits durch Retention
entfernt wurden. Beim erneuten Upsert wird der letzte bekannte Status aus
`article_identity_history` wiederhergestellt. Zusätzlich verhindert die
Mindestanzahl pro Feed, dass selten aktualisierte Feeds durch aggressive
Aufbewahrung komplett leergeräumt werden.

### Möglicher nächster Schritt

Die grundlegende Historie ist umgesetzt. Offen bleiben Feinschliffe, falls
Retention sehr aggressiv genutzt wird:

- Ablauf-/Bereinigungspolitik für sehr alte Historieneinträge
- Debug- oder Wartungsansicht für wiedererkannte Artikel
- strengere Heuristik für Titel-Hash-Fallbacks bei Feeds mit vielen identischen
  Titeln

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

### 1. SwiftData-Feed-Brücke entfernen

Nächster Architekturblock. Ziel:

- `ContentView` braucht keine `@Query [Feed]` mehr.
- First-Run-Entscheidung, OPML-/Wizard-Sheets, Feed-Menü, Refresh-All, Delete und
  Dock-Badge lesen Feed-Bestand direkt aus SQLite.
- `FeedViewModel.refreshAllFeeds` bekommt SQLite-Snapshots statt SwiftData-
  `Feed`-Arrays.
- Danach kann `SQLiteFeedSubscriptionService` die temporäre SwiftData-
  Feed-Übergangsidentität entfernen.

### 2. FeedViewModel weiter verschlanken

`FeedViewModel` enthält noch Legacy- und Übergangslogik. NetNewsWire-artiger wäre:

- `SQLiteFeedSubscriptionService` für Add/OPML
- `SQLiteFeedRefreshService`/Refresh-Koordinator für Refresh-All
- `FeedStore`/`ArticleDatabase` für Counts und Status
- SwiftData-Fallback nur noch isoliert oder gelöscht

### 3. Profiling mit großem Testbestand

Bevor weitere Listen- oder Reader-Umbauten passieren, sollte gemessen werden:

- Feed wechseln
- Alle Artikel öffnen
- Ungelesen öffnen
- Smart Folder öffnen
- Suche öffnen
- schnell Artikel lesen
- alle Feeds aktualisieren

### 4. Refresh-Skip-Logik erweitern

NetNewsWire-artige Ergänzungen:

- Cache-Control
- Mindestabstand
- ungültige Hosts
- Nicht-Feed-Daten früh abbrechen
- Validatoren periodisch verwerfen

### 5. Identity-Historie verfeinern

Die Langzeit-Wiedererkennung alter Artikel ist mit `article_identity_history`
grundlegend vorhanden; die Mindestanzahl pro Feed ist ebenfalls umgesetzt. Für
v1 nur weiter ausbauen, wenn Retention aggressiv genutzt wird oder reale Feeds
alte Artikel häufig erneut liefern.
