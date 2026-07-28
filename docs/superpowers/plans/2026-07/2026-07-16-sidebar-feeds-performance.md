# FeedStore.sidebarFeeds() Performance-Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die zwei korrelierten Pro-Feed-Subqueries in `FeedStore.sidebarFeeds()`
(Ungelesen-Zähler, letzter Feed-Log-Fehler) durch je einen einmalig
gruppierten/gefensterten SQL-Durchlauf ersetzen, um den gemessenen
10,9-Sekunden-Flaschenhals bei 500 Feeds zu beheben.

**Architecture:** Reine SQL-Restrukturierung innerhalb einer bestehenden
Methode — zwei `WITH`-CTEs (`unread_counts` per `GROUP BY`, `latest_feed_logs`
per `ROW_NUMBER() OVER (PARTITION BY feedID ...)`) ersetzen die korrelierten
Subqueries. Keine Schema-Änderung, `FeedSidebarSnapshot`-Decoding bleibt
identisch.

**Tech Stack:** Swift, GRDB (raw SQL via `fetchAll(db, sql:)`), SQLite Window
Functions, Swift Testing.

## Global Constraints

- Kommentare im Code auf Deutsch.
- Direktes Committen auf `main` (kein Feature-Branch/Worktree).
- `xcodebuild build` muss grün sein.
- Keine Schema-/Migrationsänderung.
- `FeedSidebarSnapshot` (Struct + Decoding) bleibt unverändert — nur die
  SQL-Query, die sie befüllt, ändert sich.
- Bestehende Store-Tests (`SQLiteFeedStoreTests.swift`) müssen unverändert
  grün bleiben.

---

### Task 1: Query-Umbau + Verifikation

**Files:**
- Modify: `Feedivo/Stores/FeedStore.swift:250-293` (Methode `sidebarFeeds()`)
- Verify (keine Änderung erwartet): `FeedivoTests/SQLiteFeedStoreTests.swift`
- Verify + ggf. anpassen: `FeedivoTests/SQLiteLargeDatasetPerformanceTests.swift`
  (zwei `withKnownIssue`-Blöcke, Zeilen 182-186 und 296-300)
- Modify: `docs/performance/sqlite-large-dataset-results.md` (neuer
  Ergebnis-Abschnitt anhängen)

**Interfaces:**
- Konsumiert: `FeedSidebarSnapshot` (unverändert, aus
  `Feedivo/Snapshots/FeedSidebarSnapshot.swift` — Felder `id, title, url,
  faviconURL, folderName, sortIndex, unreadCount, hasRecentError`).
- Erzeugt: keine neuen öffentlichen Interfaces — `sidebarFeeds()` behält
  Signatur `func sidebarFeeds() throws -> [FeedSidebarSnapshot]`.

- [ ] **Step 1: Aktuellen Stand von `sidebarFeeds()` lesen und Zeilenbereich bestätigen**

Run: `grep -n "func sidebarFeeds" -A 45 Feedivo/Stores/FeedStore.swift`

Erwartung: Die Methode beginnt bei Zeile 250 mit
`func sidebarFeeds() throws -> [FeedSidebarSnapshot] {` und endet bei Zeile
293 mit der schließenden `}` nach dem `snapshots.sorted { ... }`-Block. Falls
sich die Zeilennummern seit Erstellung dieses Plans verschoben haben sollen,
anhand des exakten Textes (nicht der Zeilennummer) die Stelle im nächsten
Schritt identifizieren.

- [ ] **Step 2: SQL-Query ersetzen**

Ersetze in `Feedivo/Stores/FeedStore.swift` den kompletten SQL-String
innerhalb von `sidebarFeeds()`:

Alt (aktueller Code, Zeilen ca. 252-280):

```swift
            let snapshots = try FeedSidebarSnapshot.fetchAll(db, sql: """
                SELECT
                    f.id,
                    f.title,
                    f.url,
                    f.faviconURL,
                    f.folderName,
                    f.sortIndex,
                    (
                        SELECT COUNT(*)
                        FROM articles a
                        JOIN article_statuses s ON s.articleID = a.id
                        WHERE a.feedID = f.id
                            AND s.isRead = 0
                            AND s.isHidden = 0
                    ) AS unreadCount,
                    COALESCE(
                        (
                            SELECT level = 'error'
                            FROM feed_logs
                            WHERE feedID = f.id
                            ORDER BY createdAt DESC
                            LIMIT 1
                        ),
                        0
                    ) AS hasRecentError
                FROM feeds f
                ORDER BY f.sortIndex, f.title COLLATE NOCASE, f.id COLLATE NOCASE
                """)
```

Neu:

```swift
            let snapshots = try FeedSidebarSnapshot.fetchAll(db, sql: """
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
                """)
```

Der restliche Methodenkörper (das `return snapshots.sorted { ... }` danach)
bleibt unverändert — nur der SQL-String innerhalb von `fetchAll(db, sql:
...)` wird ersetzt.

- [ ] **Step 2b: Fact-Forcing-Gate-Hinweis (falls dieser Editor-Lauf ihn auslöst)**

Vor dem ersten Edit an `FeedStore.swift` in dieser Session: Importer/Caller
sind `SQLiteSidebarState` (lädt die Sidebar-Snapshots für die UI) und
`FeedivoTests/SQLiteFeedStoreTests.swift` (Store-Tests). Kein Datenschema
betroffen (reine Query-Restrukturierung, `FeedSidebarSnapshot` unverändert).
Nutzerinstruktion: Plan Task 1 Step 2, exakter SQL-Text wie oben.

- [ ] **Step 3: Build verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Bestehende Store-Tests grün verifizieren**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedStoreTests -parallel-testing-enabled NO`
Expected: Alle 18 Tests bestehen (insbesondere
`sidebarSnapshotsAreSortedByTitle`, `sidebarSnapshotsCanHideReadFeeds`,
`sidebarFeedsSortiertNachSortIndexNichtNachTitel`,
`sidebarSnapshotsOhneLogEintraegeSindNichtFehlerhaft`,
`hasRecentErrorLiefertStatusFuerEinzelnenFeed`,
`hasRecentErrorLiefertFalseFuerUnbekannteFeedID`). Falls ein Test fehlschlägt:
NICHT weitermachen, sondern die Abweichung zur alten Query-Semantik
identifizieren (z. B. NULL-Handling bei `COALESCE`) und beheben, bevor mit
Step 5 fortgefahren wird.

- [ ] **Step 5: Lasttest-Benchmark mit optimiertem Release-Profil ausführen**

Run:
```bash
xcodebuild test \
  -project Feedivo.xcodeproj \
  -scheme Feedivo \
  -configuration Release \
  ENABLE_TESTABILITY=YES \
  -destination 'platform=macOS' \
  -only-testing:'FeedivoTests/SQLiteLargeDatasetPerformanceTests' \
  -parallel-testing-enabled NO
```

Aus der Konsolenausgabe die `PERF_METRIC`-Zeile für `sidebar_500_feeds`
notieren (Millisekunden-Wert) sowie das Test-Ergebnis (PASS/FAIL) für beide
`@Test`-Funktionen `zielbestandMitTieferPaginationBleibtReaktionsschnell` und
`sidebarUndArtikelCountsLassenSichSchnellBerechnen`. Bei Swift Testing wird
ein `withKnownIssue`-Block, dessen innere Erwartung jetzt tatsächlich erfüllt
ist, als "Known issue was expected to fail, but succeeded" (unerwarteter
Erfolg) markiert und lässt den Gesamttest fehlschlagen — das ist in diesem
Schritt das erwartete Signal dafür, dass der jeweilige Marker entfernt werden
darf (siehe Step 6).

- [ ] **Step 6: `withKnownIssue`-Marker bedingt entfernen**

**Nur für Marker, deren zugehörige Erwartung laut Step-5-Ausgabe jetzt
tatsächlich erfüllt ist:**

Marker 1 (`FeedivoTests/SQLiteLargeDatasetPerformanceTests.swift:182-186`,
Erwartung `sidebarMeasurement.milliseconds < 1_000`):

```swift
        #expect(sidebarFeeds.count == 500)
        withKnownIssue(
            "Sidebar-Counts verwenden noch eine korrelierte Unterabfrage pro Feed; siehe Performance-Bericht vom 2026-07-15."
        ) {
            #expect(sidebarMeasurement.milliseconds < 1_000)
        }
```

ersetzen durch:

```swift
        #expect(sidebarFeeds.count == 500)
        #expect(sidebarMeasurement.milliseconds < 1_000)
```

Marker 2 (`FeedivoTests/SQLiteLargeDatasetPerformanceTests.swift:296-300`,
Erwartung `countElapsed < 1.5`):

```swift
        #expect(totalUnread > 0)
        withKnownIssue(
            "Per-Feed-Counts verwenden noch wiederholte Einzelabfragen; siehe Performance-Bericht vom 2026-07-15."
        ) {
            #expect(countElapsed < 1.5)
        }
```

ersetzen durch:

```swift
        #expect(totalUnread > 0)
        #expect(countElapsed < 1.5)
```

**Wichtig:** Marker 2 misst zusätzlich zu `sidebarFeeds()` auch 100
sequenzielle Einzelaufrufe von `TimelineStore.unreadCount(feedID:)` (eine
andere Methode, außerhalb des Scopes dieses Plans). Falls Marker 1 nach dem
Fix erfüllt ist, Marker 2 aber weiterhin fehlschlägt: **nur Marker 1
entfernen**, Marker 2 unverändert lassen und diesen Fund am Ende dem Nutzer
explizit melden (separater, nicht in diesem Plan behobener Bottleneck in
`TimelineStore.unreadCount`) — nicht selbständig weitere Änderungen an
`TimelineStore` vornehmen.

- [ ] **Step 7: Performance-Bericht ergänzen**

In `docs/performance/sqlite-large-dataset-results.md` nach dem bestehenden
Abschnitt `### Nächste Maßnahme` (vor `## Reproduzierbare Ausführung`) einen
neuen Abschnitt anhängen:

```markdown
### Nachmessung nach Query-Umbau (2026-07-16)

`FeedStore.sidebarFeeds()` verwendet seit Commit <COMMIT_HASH> zwei
gruppierte/gefensterte CTEs (`unread_counts` via `GROUP BY`,
`latest_feed_logs` via `ROW_NUMBER() OVER PARTITION BY`) statt der beiden
korrelierten Pro-Feed-Subqueries. Neue Messung (optimiertes
Release-Testprofil, gleicher Zielbestand 500 Feeds / 100'000 Artikel):

| Vorgang | Vorher (2026-07-15) | Nachher (2026-07-16) |
|---|---:|---:|
| Sidebar-Snapshots für 500 Feeds | 10'904 ms | <NEUER_WERT> ms |

Design-Spec:
`docs/superpowers/specs/2026-07-16-sidebar-feeds-performance-design.md`.
```

`<COMMIT_HASH>` und `<NEUER_WERT>` mit den tatsächlichen Werten aus Step 5/6
ersetzen (Commit-Hash erst nach Step 8 bekannt — in diesem Fall den
Platzhalter-Text vor dem Commit durch den Hash des unmittelbar bevorstehenden
Commits ersetzen, z. B. durch Nachtragen direkt vor `git commit`, oder den
Bericht in einem zweiten kleinen Folge-Commit mit dem Hash ergänzen, falls
das einfacher ist).

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Stores/FeedStore.swift \
  FeedivoTests/SQLiteLargeDatasetPerformanceTests.swift \
  docs/performance/sqlite-large-dataset-results.md
git commit -m "Fix: FeedStore.sidebarFeeds() nutzt gruppierte CTEs statt korrelierter Pro-Feed-Subqueries"
```

(Falls in Step 6 einer der beiden Marker aus dem oben genannten Grund
NICHT entfernt wurde, das im Commit-Body kurz vermerken.)

---

## Abschließende manuelle Live-Verifikation (nicht automatisierbar)

Keine — reine Store-/Performance-Änderung ohne UI-Auswirkung. Die
Benchmark-Zahlen aus Step 5 sind der Wirksamkeitsnachweis.
