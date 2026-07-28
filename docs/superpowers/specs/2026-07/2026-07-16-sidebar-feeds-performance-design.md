# Design: FeedStore.sidebarFeeds() Performance-Fix (Sidebar-Ungelesen-Zähler + Fehlerstatus)

**Datum:** 2026-07-16
**Status:** Zur Review

## Kontext

Der Performance-Lasttest vom 2026-07-15
(`docs/performance/sqlite-large-dataset-results.md`) hat einen Flaschenhals in
`FeedStore.sidebarFeeds()` (`Feedivo/Stores/FeedStore.swift:250-293`)
gefunden: Bei 500 Feeds / 100'000 Artikeln braucht die Methode ~10,9 Sekunden.

Root Cause (per Instruments-Zeitprofil verifiziert): Die Query berechnet den
Ungelesen-Zähler pro Feed als **korrelierte Subquery**
(`SELECT COUNT(*) FROM articles a JOIN article_statuses s ... WHERE a.feedID = f.id ...`),
die bei 500 Feed-Zeilen 500-mal einzeln ausgeführt wird, statt einmal
gruppiert. Der zweite korrelierte Lookup (`hasRecentError`, letzter
`feed_logs`-Eintrag pro Feed) ist strukturell dasselbe Muster
(Top-1-pro-Gruppe statt Aggregat), aktuell aber laut Bericht nicht der
dominante Anteil der Messung, da bereits ein passender Index
(`feed_logs(feedID, createdAt)`) existiert.

Bestehende Indizes, die dieser Fix nutzt:
- `article_statuses(isHidden, isRead)` (Migration v11/v13)
- `articles(feedID, publishedAt)` (`idx_articles_feed_published`)
- `article_statuses.articleID` = Primary Key
- `feed_logs(feedID, createdAt)` (`idx_feed_logs_feed_created`)

Randnotiz (im Brainstorming geklärt, kein offener Punkt mehr): Es gibt eine
denormalisierte `feeds.unreadCount`-Spalte, die theoretisch anstelle einer
Neuberechnung gelesen werden könnte. Bewusste Entscheidung: **nicht**
verwenden — `sidebarFeeds()` bleibt semantisch unverändert live aus
`articles`/`article_statuses` berechnet, um nicht von der Korrektheit der
6 Pflege-Stellen + Backfill-Resync dieser Spalte abhängig zu werden. Die
zwei früher dazu dokumentierten Testfehlschläge in
`SQLiteFeedStoreTests.swift` sind bereits am 2026-07-15 durch korrigierte
Test-Fixtures behoben (kein Zusammenhang mehr mit dieser Änderung).

## Ziel

Beide korrelierten Pro-Feed-Lookups durch je einen einmalig gruppierten/
gefensterten Durchlauf ersetzen, ohne die Ergebnis-Semantik zu ändern.

## Nicht-Ziele

- Keine Nutzung der denormalisierten `feeds.unreadCount`-Spalte.
- Keine Schema-Änderung, keine neue Migration.
- Keine Änderung an `FeedSidebarSnapshot` (Spaltennamen/-typen bleiben
  identisch, nur die Query-Struktur ändert sich).
- Kein Wechsel von SwiftUI `List` zu `NSTableView` (laut Bericht durch die
  Messung nicht begründet).

## Neue Query

Ersetzt den Body von `FeedStore.sidebarFeeds()`
(`Feedivo/Stores/FeedStore.swift:250-293`):

```sql
WITH unread_counts AS (
    SELECT a.feedID AS feedID, COUNT(*) AS unreadCount
    FROM articles a
    JOIN article_statuses s ON s.articleID = a.id
    WHERE s.isRead = 0 AND s.isHidden = 0
    GROUP BY a.feedID
),
latest_feed_logs AS (
    SELECT feedID, level,
           ROW_NUMBER() OVER (PARTITION BY feedID ORDER BY createdAt DESC) AS rn
    FROM feed_logs
)
SELECT
    f.id,
    f.title,
    f.url,
    f.faviconURL,
    f.folderName,
    f.sortIndex,
    COALESCE(uc.unreadCount, 0) AS unreadCount,
    COALESCE(ll.level = 'error', 0) AS hasRecentError
FROM feeds f
LEFT JOIN unread_counts uc ON uc.feedID = f.id
LEFT JOIN latest_feed_logs ll ON ll.feedID = f.id AND ll.rn = 1
ORDER BY f.sortIndex, f.title COLLATE NOCASE, f.id COLLATE NOCASE
```

Erläuterung:
- `unread_counts`: ein gruppierter Durchlauf über die (bereits gefilterten,
  index-gestützten) `article_statuses`-Zeilen statt 500 Einzelausführungen.
- `latest_feed_logs`: `ROW_NUMBER() OVER (PARTITION BY feedID ORDER BY
  createdAt DESC)` ersetzt `ORDER BY createdAt DESC LIMIT 1` pro Feed.
  SQLite unterstützt Window Functions seit 3.25 — das System-SQLite ab
  macOS 14 (Mindestversion des Projekts) erfüllt das, GRDB nutzt hier keine
  eigene, ältere SQLite-Version.
- Beide `LEFT JOIN` + `COALESCE(..., 0)` erhalten das bestehende Verhalten
  für Feeds ohne Artikel bzw. ohne Log-Einträge unverändert (0 bzw.
  `false`).
- Tie-Break bei exakt identischem `createdAt` zwischen zwei Log-Einträgen
  bleibt wie bisher nicht deterministisch garantiert (war beim alten
  `LIMIT 1` genauso der Fall — keine Verhaltensänderung).
- `sidebarFeeds(showsReadFeeds:)` (Zeile 310) und die nachgelagerte
  Swift-seitige Sortierung (`snapshots.sorted { ... }`) bleiben
  unverändert — sie arbeiten bereits nur mit dem Ergebnis von
  `sidebarFeeds()`, nicht mit der Query-Struktur selbst.

## Tests

- Bestehende `SQLiteFeedStoreTests.swift`-Tests (u. a.
  `sidebarSnapshotsAreSortedByTitle`, `sidebarSnapshotsCanHideReadFeeds`,
  `sidebarFeedsSortiertNachSortIndexNichtNachTitel`,
  `sidebarSnapshotsOhneLogEintraegeSindNichtFehlerhaft`) müssen unverändert
  grün bleiben — reine Query-Restrukturierung ohne Semantikänderung, kein
  neuer Test nötig für die Kernlogik.
- Die beiden mit `withKnownIssue` markierten Performance-Schwellen in
  `SQLiteLargeDatasetPerformanceTests` (`sidebarFeeds()` bei 500 Feeds sowie
  100 einzelne Feed-Counts im historischen Test) werden entfernt, sobald
  der Benchmark nach dem Fix wieder unter der Zielzeit liegt.
- Denselben Lasttest-Benchmark
  (`SQLiteLargeDatasetPerformanceTests.zielbestandMitTieferPaginationBleibtReaktionsschnell`)
  erneut mit dem optimierten Release-Testprofil ausführen und die neue Zeit
  in `docs/performance/sqlite-large-dataset-results.md` dokumentieren
  (ergänzender Abschnitt, bestehende Messung bleibt als historischer
  Vergleichswert stehen).

## Risiken / offene Punkte

- Keine Schema-Änderung, kein Migrationsrisiko.
- Window-Function-Abhängigkeit ist durch die Mindest-macOS-Version (14.0)
  gedeckt — keine Kompatibilitätslücke zu erwarten.
- Tatsächliche neue Laufzeit erst nach Implementierung per Benchmark zu
  bestätigen (erwartet: von ~10,9s auf niedrigen einstelligen
  Millisekundenbereich, analog zu den bereits schnellen Timeline-Queries im
  selben Bericht).
