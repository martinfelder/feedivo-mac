# GRDB-Statement-Caching für Hot-Path-Queries — Design

Stand: 2026-07-28

## Ausgangspunkt

Punkt 2 des NetNewsWire-Performance-Vergleichs: NetNewsWire setzt
`setShouldCacheStatements(true)` (FMDB) — jede wiederholt ausgeführte SQL-
Query wird nur einmal geparst/kompiliert, danach wiederverwendet. Für
Feedivo/GRDB unklar, ob ein Äquivalent aktiv ist.

## Befund (verifiziert im lokalen GRDB-SPM-Checkout, nicht geraten)

`FetchableRecord.fetchAll(db, sql:...)`/`Row.fetchAll(db, sql:...)` — von
Feedivo überall verwendet — routen intern über
`SQLRequest(sql:arguments:adapter:cached: Bool = false)`. Das `cached`-Flag
ist standardmäßig `false`, und die SQL-String-Convenience-Overloads
exponieren diesen Parameter nicht nach außen. `db.execute(sql:...)`
(Schreibpfad) hat dasselbe Verhalten. `grep -rn "cached: true\|cachedStatement"
Feedivo/` ergab **null Treffer** — GRDBs Statement-Cache wird in Feedivo an
keiner einzigen Stelle genutzt; jede Query wird bei jedem Aufruf frisch
geparst/kompiliert.

Die Kandidaten-Queries (Timeline-Artikelliste, Sidebar-CTE) binden Werte
bereits korrekt über `?`-Platzhalter/`StatementArguments`, nicht per
String-Interpolation — Caching ist dort sicher anwendbar (gleiche SQL-
Textform bei unterschiedlichen gebundenen Werten, genau der vorgesehene
Anwendungsfall für einen Statement-Cache).

## Umsetzung

Gezielt auf die beiden explizit genannten Hot-Path-Queries beschränkt
(keine der ~100+ übrigen SQL-Stellen app-weit angefasst):

- `TimelineStore.articles(...)`/`.articlesAsync(...)` (Haupt-Ladepfad der
  Artikelliste, jeder Scope-Wechsel/jede Pagination/jede Suche) —
  `ArticleListSnapshot.fetchAll(db, sql:...)` → `SQLRequest<ArticleListSnapshot>
  (sql:..., cached: true).fetchAll(db)`.
- `FeedStore.querySidebarFeeds(_:)` (Sidebar-CTE, bei jedem Sidebar-Reload) —
  analog auf `SQLRequest<FeedSidebarSnapshot>(sql:..., cached: true).fetchAll(db)`
  umgestellt.

## Unerwarteter Compile-Fallstrick

Beide Umstellungen scheiterten zunächst mit „main actor-isolated
conformance of '...' to 'FetchableRecord' cannot satisfy conformance
requirement for a 'Sendable' type parameter". Ursache: das App-Target setzt
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (bereits als Gotcha in
CLAUDE.md dokumentiert, dort bisher nur für synchrone Read-Funktionen
relevant) — dadurch war die `FetchableRecord`-Konformität von
`ArticleListSnapshot`/`FeedSidebarSnapshot` implizit MainActor-isoliert.
Die bisherige `fetchAll(db, sql:...)`-Convenience-Methode störte das nicht,
`SQLRequest<T>`s generischer `FetchRequest`-Pfad verlangt aber Sendable-
Kompatibilität, die eine MainActor-isolierte Konformität nicht erfüllt.
Fix: `init(row: Row) throws` in beiden `FetchableRecord`-Extensions
explizit `nonisolated` markiert.

## Testing

Kein neues Testverhalten (Query-Ergebnisse bleiben identisch, nur der
Ausführungspfad ändert sich) — bestehende Suiten dienen als
Regressionsschutz: `SQLiteTimelineStoreTests`, `SQLiteFeedStoreTests`,
`SQLiteFeedArticleListStateTests`, `SQLiteArticleDatabaseTests`,
`SQLiteSidebarStateTests`, `MenubarStatusItemControllerTests` — alle grün
nach der Umstellung (ein Fehlschlag im ersten Lauf war die bereits
dokumentierte Last-Flakiness von `waitForLoad`, isoliert erneut grün
bestätigt). Build (Debug) grün.

## Offene Punkte

- Kein direkter Vorher-/Nachher-Benchmark durchgeführt (wie schon bei
  Punkt 1 dokumentiert: architektureller Aufräumpunkt, kein zuvor
  gemessener Flaschenhals) — der Nutzen ist durch die GRDB-Quellcode-
  Verifikation begründet, nicht durch eine eigene Zeitmessung.
- Weitere, seltener aufgerufene SQL-Stellen (z. B. `ArticleDatabase.
  fetchArticles(feedID:)`, `SQLiteUnreadCountService`) bewusst nicht
  angefasst — nur die beiden explizit als Hot-Path benannten Stellen.
