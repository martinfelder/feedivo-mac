# NetNewsWire vs. Feedivo: Mechanik- und Performance-Vergleich

Stand: 2026-07-15 (siehe unten: Update 2026-07-28 zu Render-/Lade-Performance)

> **Update 2026-07-28:** Gezielter Vergleich der Artikel-Lade-/Render-Pipeline
> (Nutzer-Eindruck: NetNewsWire fühlt sich beim Laden/Rendern von Artikeln
> spürbar schneller an als Feedivo). Neuer Abschnitt
> „Update 2026-07-28: Render-/Lade-Performance-Vergleich" weiter unten, direkt
> nach diesem Einleitungsblock. Ergänzt/aktualisiert die Aussagen zu Abschnitt 2
> (Artikelliste) und 8 (Reader) unten um konkrete, code-belegte Detailpunkte.

> **Aktuelles Follow-up:** Das Audit vom 2026-07-15 hat mehrere Abweichungen
> zwischen dem hier beschriebenen Zielbild und dem aktuellen Produktpfad
> gefunden: festes 500er-Listenlimit ohne Pagination, Sortierung erst nach dem
> SQL-Limit, synchroner GRDB-Read im Main-Actor-Loader sowie unvollständige
> Feature-Verdrahtung. Der priorisierte Bericht liegt unter
> `docs/performance/feedivo-performance-feature-integration-audit-2026-07-15.md`.
> Die dort priorisierten Pflichtlücken wurden anschließend am selben Tag
> umgesetzt; offen bleibt der Messnachweis für das 100'000-Artikel-Ziel.
> Die Kernaussage dieses Vergleichs bleibt bestehen: Feedivos Datenmodell ist
> NetNewsWire-nah; die größten Lücken liegen heute an Ausführungs- und
> Integrationsgrenzen.

Diese Notiz hält die Erkenntnisse aus dem Codevergleich zwischen NetNewsWire
(`/Users/martinfelder/Developer/NetNewsWire-main`) und Feedivo fest. Es geht
nicht um Design, sondern um Mechanik: Feed-Verwaltung, Refresh, Persistenz,
Artikelliste, Suche und Reader.

## Update 2026-07-28: Render-/Lade-Performance-Vergleich

Auslöser: Nutzer-Eindruck, dass Laden/Rendern von Artikeln in NetNewsWire
spürbar schneller wirkt als in Feedivo. Zwei parallele Codevergleiche (Feedivo
Produktpfad + NetNewsWire-Klon) ergaben folgendes Bild — Kurzfazit vorweg:
Feedivo ist inzwischen solide (Pagination, async Reads, CTE-Fixes,
Reader-Cache), NetNewsWire gewinnt vor allem durch **native
AppKit-Zellwiederverwendung mit fester Zeilenhöhe** und **mehrschichtiges
In-Memory-Caching**, das SwiftUIs deklarativen Neu-Render-Reflex komplett
umgeht.

### Vergleichstabelle

| Bereich | Feedivo (aktuell) | NetNewsWire | Auswirkung |
|---|---|---|---|
| Artikelliste-UI | SwiftUI `List`, variable Zeilenhöhe (Auto-Layout pro Zeile) | `NSTableView`, **eine feste, einmalig berechnete Zeilenhöhe** für die ganze Tabelle | Größter Einzelfaktor — NNW muss beim Scrollen nie Text-Layout neu berechnen |
| Reload-Granularität bei Statusänderung | Globaler `bumpStatusVersion()`-Zähler → **jede** offene Liste macht vollen SQL-Reload (200er-Page) | Diff-Check (`representSameArticlesInSameOrder`) → bei unveränderter Reihenfolge nur `reloadVisibleCells()`, sonst gezieltes Zell-Reload | Feedivo re-queried bei jedem einzelnen "gelesen markiert" den ganzen sichtbaren Scope |
| Article-Objekt-Caching | Keins — jede Query baut frische `ArticleListSnapshot`-Structs aus SQL | In-Memory `articlesCache`/`StatusCache` (thread-safe, `OSAllocatedUnfairLock`) pro Account | NNW vermeidet wiederholtes Parsen/Alloc identischer Artikel über mehrere Reloads |
| Ungelesen-Zähler | Live-CTE-Aggregation bei jedem Sidebar-Reload (aktuell ~26ms bei 500 Feeds, skaliert mit `feed_logs`-Größe) | Denormalisiert im Speicher (`[feedID: Int]`-Dictionary), gezielt inkrementell aktualisiert | NNW: O(1) Lesezugriff statt SQL-Query pro Sidebar-Refresh |
| Reader-HTML (Web-Modus) | WKWebView wiederverwendet ✓ (bereits wie NNW) | WKWebView wiederverwendet + **statisch gecachtes Template/CSS**, nur Body-Platzhalter ausgetauscht | Feedivo lädt bei jedem Artikel serialisiertes HTML neu zusammen statt Template-Substitution |
| Favicon-Prefetch | Lazy pro sichtbarer Zeile via `CachedRemoteImageView.task` | Aktiver **Prefetch für die gesamte neue Artikelmenge**, sobald `articles` gesetzt wird | NNW hat Icons schon im Cache, bevor die Zelle sichtbar wird |
| DB-Journal-Mode | `DatabaseQueue` + `PRAGMA synchronous=NORMAL` (seit 2026-07-27) ✓ | `DatabaseQueue` + `PRAGMA synchronous=NORMAL`, **plus `setShouldCacheStatements(true)`** | Feedivo fehlt Statement-Caching (SQL wird bei jedem Call neu geparst) |
| Refresh-Throttling | 9-Min-Minimum via `FeedRefreshThrottle` (seit 2026-07-27, ungepusht) ✓ | 9-Min-Minimum + Cache-Control-Header + **Content-Hash-Vergleich nach 200 OK** + Reddit-Sonderfall + Bad-Host-Liste | Feedivo prüft nach 200 OK nicht, ob der Body inhaltlich identisch zum letzten Mal ist |
| Sortierung großer Listen | In SQL (`ORDER BY` vor `LIMIT`) ✓ | Größtenteils **in Swift nach dem Fetch** (`sortedByDate`) | Kein Nachteil für Feedivo — SQL-seitig ist strukturell eher vorteilhaft |

### Kern-Belege (Feedivo)

- Pagination: `ArticleFetchLimits.mainArticlePage = 200` (`Feedivo/Extensions/ArticleFetchLimits.swift:11`), Nachladen via `SQLiteFeedArticleListState.loadMore()` (`Feedivo/ViewModels/SQLiteFeedArticleListState.swift:248-284`).
- Globaler Invalidierungs-Zähler: `SQLiteDataInvalidation.bumpStatusVersion()` (`Feedivo/Database/SQLiteDataInvalidation.swift:3-12`), **44 Aufrufstellen** app-weit; jeder Bump triggert `.task(id: loadToken)` in jeder offenen `SQLiteFeedArticleListView` (Zeile 173-175, 533-557) sowie einen vollen Sidebar-Reload in `ContentView.swift:245-248, 484-495`.
- Kein Article-Objekt-Cache: `ArticleListSnapshot`/`ArticleListItemSnapshot` werden bei jedem Reload frisch aus SQL gebaut (`ArticleListSQL.swift:8-31`, `ArticleListItemSnapshot.swift:1-29`).
- Sidebar-Ungelesen-Zähler: `FeedStore.sidebarFeeds()` (`Feedivo/Stores/FeedStore.swift:280-321`) rechnet per CTE live aus `article_statuses`, obwohl `feeds.unreadCount` als denormalisierte Spalte bereits existiert und gepflegt wird (an anderer Stelle genutzt, nicht hier). Aufruf erfolgt zudem **synchron** (`database.read{}`, nicht `readAsync`) in `ContentView.reloadFeedSnapshots()` (`ContentView.swift:483-495`) — MainActor-Jank-Risiko bei großem `feed_logs`-Bestand, da die `latest_feed_logs`-CTE die komplette Tabelle scannt.
- Reader-Caching bereits vorhanden: `ReaderPreparedArticleCache` (24 Einträge, Fingerprint-Key, `ReaderPreparedArticle.swift:108-180`), Parsing läuft in `Task.detached` (`SQLiteReaderState.swift:60-64`) — kein MainActor-Blocking. WKWebView wird bereits über Artikelwechsel hinweg wiederverwendet (`WebContentView.swift`, Kommentar Zeile 5-9, Commit `eca556f93`).
- Favicon-/Bild-Cache: zweistufig (`NSCache` + Disk, SHA256-Dateinamen), gedrosselt auf 4 parallele Downloads, `Task.detached` für Disk-I/O (`ImageCacheService.swift:30-31, 57-60, 127-167, 237-252`) — aber Laden ist lazy pro sichtbarer Zeile, kein Prefetch beim Scope-Wechsel.

### Kern-Belege (NetNewsWire)

- Feste Zeilenhöhe: `calculateRowHeight()` mit Lorem-Ipsum-Prototyp, einmalig gesetzt via `tableView.rowHeight` (`TimelineViewController.swift:804-818, 897-901`) — kein Auto-Layout-Pass pro sichtbarer Zeile beim Scrollen.
- Diff-optimiertes Reload: `representSameArticlesInSameOrder`-Check vor jedem Listen-Update, bei Gleichheit nur `reloadVisibleCells()` statt vollem `reloadData()` (`TimelineViewController.swift:117-153`).
- In-Memory-Objekt-Caches: `articlesCache`/`StatusCache`, beide `OSAllocatedUnfairLock`-geschützt (`ArticlesTable.swift:25`, `StatusesTable.swift:246-279`).
- Ungelesen-Zähler denormalisiert im Speicher: `Account.unreadCounts: [String: Int]` (`Account.swift:247`), adaptive Batch-Strategie beim initialen Befüllen (`Account.swift:1332-1349`), inkrementelle Updates statt Live-Aggregation.
- Reader-Template-Caching: `ArticleRenderer.defaultTemplate`/`defaultStyleSheet` als `static let`, nur Body-Platzhalter wird pro Artikel ersetzt (`ArticleRenderer.swift:154-191`); eine WKWebView-Instanz lebt über die gesamte Session (`DetailWebViewController.swift:94, 280-321`).
- Aktiver Favicon-Prefetch beim Setzen der Artikelmenge: `IconImageCache.prefetchImagesForArticles(articles)` (`IconImageCache.swift:61-89`, Aufruf `TimelineViewController.swift:151`).
- Refresh-Throttling inkl. Content-Hash-Dedupe nach 200 OK: `LocalAccountRefresher.swift:283-290, 464-598`.
- `setShouldCacheStatements(true)` + `PRAGMA synchronous=1`, `journal_mode=DELETE` (bewusst kein WAL bei Single-Connection): `DatabaseQueue.swift:138-145`.

### Priorisierte Empfehlungen für Feedivo

**Schnell, hoher Impact:**

1. **Gezielte statt globale Reload-Invalidierung.** `stickyRowSnapshots` mildert nur das Symptom (Verschwinden), löst aber nicht das Grundproblem: `bumpStatusVersion()` ist ein einziger globaler Zähler für alle Mutationsarten. Feinere Granularität (getrennte Versionszähler pro Scope-Kategorie, oder ein direktes "diese ID hat sich geändert"-Signal) würde den Rebuild-Rhythmus stark reduzieren — analog zu NNWs `representSameArticlesInSameOrder`-Check vor dem Reload.
   **Teilweise umgesetzt (2026-07-28), Großumbau bewusst verworfen:** Vollständige Payload-basierte Invalidierung (~41 Aufrufstellen von `bumpStatusVersion()`) wurde zugunsten dreier gezielter, risikoarmer Fixes zurückgestellt (Design-Doc: `docs/superpowers/specs/2026-07-28-gezielte-reload-invalidierung-design.md`). (a) Geprüft und **widerlegt**: die Annahme, `startLoad(_:)`s unbedingte `self.rows = result.rows`-Zuweisung löse bei inhaltlich identischem Ergebnis unnötige Re-Renders aus — per Standalone-Kontrolltest verifiziert, dass Swifts `@Observable`-Makro bereits selbst auf Gleichheit prüft, bevor es Beobachter benachrichtigt (kein Codefix nötig, nur als Regressionstest dokumentiert). (b) Neue Debounce-Zwischenstufe `debouncedStatusVersion` in `SQLiteFeedArticleListView` bündelt mehrere Bumps innerhalb 200ms zu einem Reload (`SearchDebounce.wait(milliseconds:)`, additiv erweitert statt einer dritten Debounce-Implementierung); mit Sonderbehandlung für den allerersten Aufruf (kein Warten), sonst hätte jede neu geöffnete Liste einen unnötigen Extra-Reload 200ms nach dem Erscheinen bekommen. (c) Bugfix gefunden und behoben: `toggleStarred`/`toggleArchived` befüllten `stickyRowSnapshots` nicht, im Unterschied zu `toggleRead` — Artikel verschwanden beim Entsternen/Archivieren in gefilterten Smart Folders sofort ohne Karenzzeit. Scope bewusst auf `SQLiteFeedArticleListView` begrenzt, andere Konsumenten (Sidebar, Suchfenster, Reader, Menubar) unangetastet.
2. **GRDB-Statement-Caching prüfen/erzwingen** als Äquivalent zu `setShouldCacheStatements(true)`, insbesondere für die Hot-Path-Queries (Timeline, Sidebar-CTE).
3. **Content-Hash-Vergleich nach 200 OK** ergänzen/verifizieren — Feedivo hat laut CLAUDE.md bereits `lastBodyHash` als Feld; prüfen, ob es beim Refresh tatsächlich zum Skip-Parse genutzt wird oder nur gespeichert.

**Mittlerer Aufwand, spürbarer Effekt:**

4. **Feste/vorab berechnete Zeilenhöhe statt Auto-Layout pro Zeile** in `ArticleRowView`, falls die Zeilenhöhe ohnehin meist uniform sein kann. Vermutlich größter Einzelhebel (NNWs Faktor 1), aber erst prüfen, ob Feedivos variable Thumbnail-Größen/2-3-zeilige Summaries (Feature 19.1) eine feste Höhe optisch zulassen.
   **Umgesetzt (2026-07-28):** Brainstorming ergab Nutzer-Zustimmung zum Leerraum-Trade-off (kurze Titel/Summaries schmiegen sich nicht mehr eng an, sondern lassen Platz bis zur festen Höhe). Neue, reine Funktion `ArticleRowHeightMetrics.height(interfaceTextSize:imagePosition:summaryLineCount:)` (`Feedivo/Views/ArticleList/ArticleRowHeightMetrics.swift`) berechnet die Höhe ausschließlich aus den drei app-weiten Anzeige-Einstellungen — nie aus Artikelinhalt — über `NSLayoutManager().defaultLineHeight(for:)` (Titel immer 2 Zeilen, Metadaten-Zeile immer 1 Zeile reserviert, Summary 0–3 Zeilen je Einstellung) plus Bildhöhe als Untergrenze, VStack-Spacing, Padding und 4pt-Sicherheitspuffer gegen `NSFont`/SwiftUI-`Text`-Metrik-Abweichungen. `ArticleRowView` wendet das Ergebnis über `.frame(height:, alignment: .top)` auf die äußere `HStack` an; die rechte Spalte (Stern-Button) nutzt dieselbe (Inhalts-)Höhe statt der bisherigen hartcodierten, nicht textgrößen-skalierten `76`. TDD (4 neue Tests, `ArticleRowHeightMetricsTests.swift`), Build grün. Design-Doc: `docs/superpowers/specs/2026-07-28-artikelliste-feste-zeilenhoehe-design.md`. Ansatz B (gemessener Off-Screen-Prototyp wie NetNewsWire) wurde diskutiert und zugunsten der reinen, testbaren Funktion verworfen (Risiko: `NSHostingView.fittingSize`-Fallstricke). **Ausstehend:** manuelle Live-Verifikation (verschiedene Textgrößen-/Summary-Einstellungen, kein Clipping des Stern-Buttons) — kein computer-use für native macOS-Apps in dieser Umgebung verfügbar.
5. **Denormalisierte, im Speicher gehaltene Ungelesen-Zähler statt Live-CTE für die Sidebar.** ~~`feeds.unreadCount` existiert bereits und wird gepflegt, wird aber von `sidebarFeeds()` nicht gelesen. Falls die Pflege wirklich konsistent ist, könnte die Sidebar direkt daraus lesen statt der CTE.~~
   **Umgesetzt und wieder verworfen (2026-07-28):** Vor dem Umstieg wurde die tatsächliche Pflege von `feeds.unreadCount` app-weit auditiert (Memory `feed-unread-count-invariant.md` war veraltet/SwiftData-Ära und daher nicht verlässlich) — dabei fanden sich drei echte Lücken: `SQLiteFeedArticleListState.deleteArticle()`, `CloudSyncArticleStatusMapping.applyIncoming(...)` und `.applyIncomingDeletion(...)` aktualisierten die Spalte nicht. Alle drei wurden gefixt (TDD, je ein Regressionstest). Der eigentliche Umstieg von `sidebarFeeds()` auf die Spalte wurde danach implementiert, testgetrieben — und durch einen bereits bestehenden Test wieder verworfen: `SQLiteSidebarStateTests.loadIgnoresStaleFeedUnreadCountCache()` verlangt explizit, dass ein veralteter `feeds.unreadCount`-Wert ignoriert wird und die Sidebar live aus `article_statuses` rechnet — exakt die Absicherung, die der Architektur-Kommentar in `SQLiteUnreadCountService.swift` beschreibt ("damit ein veralteter `feeds.unreadCount`-Cache keine falschen Badges anzeigen kann"). Das ist ein bewusster Korrektheit-vor-Performance-Trade-off des Projekts, kein Versehen — die Live-CTE bleibt seit dem 2026-07-16-Fix mit ~26ms bei 500 Feeds ohnehin schnell genug. `sidebarFeeds()` liest deshalb weiterhin live; die drei Pflege-Fixes bleiben trotzdem bestehen, da `feeds.unreadCount` auch von anderen Konsumenten (Refresh-Ergebnis, potenzielle künftige Nutzung) korrekt sein muss.
6. **`ContentView.reloadFeedSnapshots()` auf `readAsync` umstellen** — einer der wenigen verbliebenen synchronen MainActor-DB-Reads im Hot-Path. **Umgesetzt (2026-07-28):** neue `FeedStore.sidebarFeedsAsync()` (nutzt GRDBs `readAsync`), `ContentView.reloadFeedSnapshots()` ruft sie jetzt statt der synchronen `sidebarFeeds()` auf.

**Größer, eher optional:**

7. **HTML-Template-Caching für den nativen Reader** — Feedivos `ReaderPreparedArticleCache` deckt Re-Navigation bereits ab; ein NNW-artiges Template-System wäre eher für den WKWebView-Pfad relevant, aber Feedivo nutzt standardmäßig den nativen SwiftUI-Renderer — Konzept nicht 1:1 übertragbar.
8. **Aktiver Favicon-Prefetch beim Scope-Wechsel** statt lazy pro Zeile — glättet das erste Aufpoppen von Favicons, reiner Wahrnehmungs-Polish, kein Kern-Performance-Thema.

**Bewusst NICHT von NetNewsWire übernehmen:**

- Verzicht auf Pagination — Feedivos 200er-Seiten + Nachladen sind für sehr große Feeds der bessere Ansatz.
- Direkter Umstieg auf `NSTableView`/AppKit — wäre ein Architekturbruch gegen ADR-004/005 (SwiftUI-first); Punkt 4 (feste Zeilenhöhe) kann den Großteil des Effekts vermutlich auch innerhalb von SwiftUI erreichen.

## Aktualisierte Momentaufnahme nach SQLite-Feed-/Artikel-Umbau

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
`FeedSidebarSnapshot`, Tags und Smart Folders lesen SQLite-Snapshots.
Seit 2026-07-05 bündelt `SQLiteUnreadCountService` die NetNewsWire-artige
Unread-Count-Schicht: Feed-Unread-Counts, Feed-Count-Rebuilds, Sidebar-
Gesamtsumme und Smart-Folder-Badges laufen über dieselbe SQL-Logik.
`ArticleStatusStore` schreibt weiterhin Statuszeilen, delegiert die
Count-Korrektur bei Read-/Hidden-Änderungen aber an diesen Service.

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
Feed-Handling-Block ist für den produktiven UI-Pfad ebenfalls SQLite-first:

- [x] Sidebar-Anzeige und Artikellisten-Routing weg von `@Query [Feed]` —
  Sidebar nutzt SQLite-Snapshots, `ContentView` hält `FeedSidebarSnapshot`s aus
  `FeedStore.sidebarFeeds()` und routet ausgewählte Feeds per SQLite-Feed-ID in
  `SQLiteFeedArticleListView`.
- [x] Feed-Auswahl vollständig über SQLite-Feed-ID: `SidebarSelection.feed`
  trägt `FeedRecord.id` (String); Artikelliste bekommt `init(feedID:)`.
- [x] `FeedRowView` rendert aus `FeedSidebarSnapshot`; `FeedPropertiesView`/
  `FeedRenameView` laden `FeedRecord` via `FeedStore.feed(id:)`.
- [x] Timeline-Loads laufen über eine cancellable latest-wins
  Queue/Operation-Schicht.
- [x] Listen- und Suchfenster-Suche laufen über SQLite/FTS.
- [x] First-Run-Entscheidung, Feed-Menü, Refresh-All, Delete und Dock-Badge
  nutzen im Hauptfenster SQLite-Snapshots/Stores statt `@Query [Feed]`.
- [x] NetNewsWire-artige Wiedererkennung alter Artikel ist grundlegend
  umgesetzt: `article_identity_history` bewahrt Status-/Seen-Metadaten über
  gelöschte Artikel hinaus.
- [ ] temporäre SwiftData-Feed-Bridge entfernen — SwiftData `Feed` ist noch
  Übergangsbackend für Legacy-Relationships und isolierte alte Pfade, aber nicht
  mehr Feed-Identität des produktiven Hauptfensters.
- [ ] alte SwiftData-Fallbacks löschen oder hart isolieren, sobald die
  Brücken-Relationships nicht mehr produktiv gebraucht werden.
- [ ] `FeedViewModel` weiter verschlanken, sodass Feed-Abo, Refresh und
  Artikelstore stärker in dedizierten Services liegen.

Kurzfassung: **Artikel-Handling ist größtenteils SQLite-/NetNewsWire-artig.
Feed-Navigationsidentität ist SQLite-only (Feed-ID). Offen ist vor allem das
Entfernen der verbliebenen SwiftData-Brücke für Legacy-Relationships/Fallbacks,
die Verschlankung von `FeedViewModel` und späteres Profiling der SwiftUI-Liste.**

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
  Feedivo hat dafür inzwischen `article_identity_history`; offen sind nur noch
  Ablauf-/Debug-/Heuristik-Feinschliffe.
- NetNewsWire hat eine Account-Schicht für lokale und Sync-Accounts; Feedivo ist
  aktuell lokal SQLite-first und hält Sync bewusst zurück.
- Feedivo nutzt noch SwiftData als Übergangsbackend für alte Models und
  Legacy-Relationships, nicht mehr als produktive Feed-/Artikelquelle.

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
`ArticleStatusStore` aktualisiert kleine Statuszeilen und ruft für
Read-/Hidden-Änderungen `SQLiteUnreadCountService` auf. Der Service korrigiert
`feeds.unreadCount`; danach bump't `ArticleStatusStore`
`SQLiteDataInvalidation.statusVersion`, damit Sidebar und Listen gezielt neu
laden.

### Möglicher nächster Schritt

Status-Separierung und grundlegende Langzeit-Wiedererkennung sind erledigt.
NetNewsWire-artige Restarbeit wäre eher Pflege der Historie: Ablaufpolitik,
Debug-/Wartungsansicht und strengere Heuristik für Titel-Hash-Fallbacks.

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
- SwiftData bleibt noch Übergangsbackend für Legacy-Relationships und alte
  Modelle, nicht mehr Hauptpersistenz der heißen Feed-/Artikeldaten.

### Auswirkung

Feedivo hat die Kontrolle über Joins, Indizes, FTS/Suche und gezielte
Status-Updates inzwischen in SQLite verlagert. Der verbleibende Unterschied ist
nicht mehr die Artikelpersistenz, sondern die noch nicht vollständig entfernte
SwiftData-Brücke in Legacy-Relationships und alten Fallbackpfaden.

### Möglicher nächster Schritt

Nächster Schritt ist die restliche Bridge-Reduktion: produktive UI-Pfade nutzen
bereits SQLite-Snapshots, aber alte SwiftData-Modelle und Relationship-Brücken
sollen weiter isoliert oder entfernt werden.

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

### 1. SwiftData-Bridge weiter reduzieren

Nächster Architekturblock. Ziel:

- produktive Pfade bleiben SQLite-only und bekommen keine neuen SwiftData-Reads.
- `SQLiteFeedSubscriptionService` soll die temporäre SwiftData-
  Feed-Übergangsidentität nur noch schreiben, solange Legacy-Relationships sie
  wirklich brauchen.
- alte SwiftData-Fallbacks in `FeedViewModel`, Retention und historischen Views
  weiter isolieren oder löschen.
- SwiftData-Container erst entfernen, wenn keine produktiven alten Models mehr
  gebraucht werden.

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

## Stand nach SQLite Final Closure

Feedivo entspricht NetNewsWire strukturell in den relevanten Feed-/Artikelpunkten:

- Artikelinhalt und Status getrennt (`articles` vs. `article_statuses`).
- Listen laden leichte Snapshots (`TimelineStore`/`ArticleStore`), keine
  SwiftData-`@Query`-Materialisierung im produktiven Pfad.
- Suche läuft über SQLite/FTS (`ArticleStore.searchArticles`).
- Counts kommen aus SQLite (`feeds.unreadCount`, `article_statuses`,
  `SmartFolderSidebarBadgeSnapshot`).
- Refresh schreibt in SQLite (`SQLiteFeedRefreshCoordinator`/`SQLiteFeedRefreshService`),
  Regeln liegen in `SQLiteRuleStore` und werden als Snapshots angewendet.
- Sidebar, Tags, SmartFolders, FeedFolders und OPML-Import/Export sind SQLite-first.

Bewusst anders:

- UI bleibt SwiftUI statt NSTableView, solange Performance-Tests grün bleiben.
- SwiftData-Legacy-Code (`@Model`-Klassen, einige ViewModels, Backfill-Services)
  liegt noch als Migrationshistorie im Repo, ist aber nicht produktive Quelle.
  Die produktiven Aufrufe erfolgen ausschließlich gegen SQLite-Stores; die
  SwiftData-Bridge ist standardmäßig ausgeschaltet (`SwiftDataBridgeSettings.defaultIsEnabled = false`).
- Legacy-Views (`LegacyArticleListView`, `LegacyReaderView`) sind ohne
  Typealias erreichbar und damit nicht mehr versehentlich produktiv nutzbar.
