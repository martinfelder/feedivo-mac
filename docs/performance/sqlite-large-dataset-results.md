# SQLite Large Dataset Performance – Lasttest Ergebnis

## Stand 2026-07-15: Zielbestand 500 Feeds / 100'000 Artikel

### Ziel und Messumgebung

Gemessen wurde der produktive GRDB-/SQLite-Lesepfad mit dem in Feature 26.2
definierten Zielbestand:

- 500 Feeds
- 100'000 Artikel, davon 50 % gelesen
- 200 Artikel pro Feed
- 200er-Seiten wie in der produktiven Artikelliste
- MacBook Pro `Mac16,7`, Apple M4 Pro, 48 GB RAM
- macOS 26.5.2, Xcode 26

Der Datensatz wird innerhalb einer Transaktion erzeugt. Der Seed ist kein
Produktivitätsziel; er stellt lediglich sicher, dass die nachfolgenden Reads
gegen den vollständigen Bestand laufen. Der Test schreibt seine Einzelwerte als
Swift-Testing-Attachment in das `.xcresult`.

### Gemessene Werte

| Vorgang | Debug-Testprofil | Optimiertes Release-Testprofil |
|---|---:|---:|
| Seed 500 / 100'000 | 9'428 ms | 4'792 ms |
| Timeline, erste 200, neueste zuerst | 57.7 ms | 57.8 ms |
| Timeline, `OFFSET 50'000` | 96.2 ms | 96.2 ms |
| Timeline, `OFFSET 99'800` | 109.3 ms | 110.3 ms |
| Titel-Sortierung, `OFFSET 99'800` | 131.1 ms | 132.7 ms |
| FTS-Suche | 5.3 ms | 4.5 ms |
| Gesamtzahl 100'000 Artikel | 48.5 ms | 47.8 ms |
| Sidebar-Snapshots für 500 Feeds | **10'910 ms** | **10'904 ms** |

Die nahezu identischen Read-Zeiten in Debug und Release zeigen, dass die
SQLite-Abfragen und nicht Swift-Optimierungsunterschiede die Ergebnisse prägen.

### Instruments-Befund

Ein 15-sekündiger Time-Profiler-Lauf wurde an den optimierten Testprozess
angehängt. Nach dem Seed und den schnellen Timeline-Abfragen verbringt der
Prozess den verbleibenden Messzeitraum in `sqlite3VdbeExec`, aufgerufen aus
`FeedStore.sidebarFeeds()` (`FeedStore.swift`, Query ab Zeile 252).

Die Query berechnet den Ungelesen-Zähler derzeit als korrelierte Unterabfrage
pro Feed. Bei 500 Feeds führt der gewählte SQLite-Abfrageplan dadurch zu stark
wiederholter Arbeit über `articles` und `article_statuses`. Der zweite
korrelierte Lookup für den letzten Feed-Fehler ist strukturell ähnlich, bei
einem Bestand ohne Feed-Logs aber nicht der dominante Anteil dieser Messung.

### Bewertung

- Die Timeline-Pagination ist auch auf der tiefsten möglichen 200er-Seite mit
  rund 110 ms schnell. **Keyset-Pagination ist für 100'000 Artikel aktuell
  nicht erforderlich.**
- Alle produktnah gemessenen Timeline-/Such-/Count-Pfade liegen deutlich
  unter einer Sekunde.
- Das Qualitätsziel ist insgesamt **noch nicht erfüllt**, weil ein Sidebar-
  Reload bei 500 Feeds rund 10,9 Sekunden blockiert.
- Ein Wechsel von SwiftUI `List` zu `NSTableView` ist durch diese Messung nicht
  begründet. Der aktuelle Engpass liegt vor dem Rendering in SQL.

### Nächste Maßnahme

`FeedStore.sidebarFeeds()` soll die Ungelesen-Zähler einmal gruppiert nach
`feedID` berechnen und das Ergebnis an `feeds` joinen, statt dieselbe
Statusmenge in einer korrelierten Unterabfrage pro Feed auszuwerten. Danach ist
derselbe Benchmark erneut auszuführen. Erst wenn der Store-Pfad grün ist, lohnt
sich eine separate UI-Messung von Start, Sidebar-Reload und Scrollen mit einem
persistenten Zielbestand.

Die beiden betroffenen Schwellen im Test (`sidebarFeeds()` bei 500 Feeds sowie
100 einzelne Feed-Counts im historischen Test) sind bis zu dieser Korrektur mit
`withKnownIssue` markiert. Sie bleiben dadurch im Testreport sichtbar, ohne die
übrigen Performance-Regressionen zu verdecken.

### Nachmessung nach Query-Umbau (2026-07-16)

`FeedStore.sidebarFeeds()` verwendet seit Commit `656c9b046` zwei
gruppierte/gefensterte CTEs (`unread_counts` via `GROUP BY`,
`latest_feed_logs` via `ROW_NUMBER() OVER PARTITION BY`) statt der beiden
korrelierten Pro-Feed-Subqueries. Neue Messung (optimiertes
Release-Testprofil, gleicher Zielbestand 500 Feeds / 100'000 Artikel):

| Vorgang | Vorher (2026-07-15) | Nachher (2026-07-16) |
|---|---:|---:|
| Sidebar-Snapshots für 500 Feeds | 10'904 ms | 26 ms |

Beide `withKnownIssue`-Marker aus dem vorigen Abschnitt sind entfernt worden:
Der Marker für `sidebarMeasurement.milliseconds < 1_000` (Zielbestandstest)
ist jetzt weit unterschritten (~26 ms statt der geforderten <1'000 ms). Der
zweite Marker (`countElapsed < 1.5` im 100-Feed-Test
`sidebarUndArtikelCountsLassenSichSchnellBerechnen`) war ebenfalls
unerwartet erfüllt — dieser Test misst zusätzlich 100 sequenzielle Aufrufe
von `TimelineStore.unreadCount(feedID:)` (eine andere, weiterhin
unoptimierte Methode außerhalb des Scopes dieser Korrektur), bleibt bei nur
100 Feeds aber auch mit dieser separaten korrelierten Unterabfrage klar
unter der 1,5-Sekunden-Schwelle. `TimelineStore.unreadCount` selbst wurde
nicht angefasst — ein analoger Bottleneck bei größerem Zielbestand (z. B.
500+ Feeds) ist damit nicht ausgeschlossen und bliebe ein möglicher Kandidat
für eine künftige, separate Maßnahme.

Design-Spec:
`docs/superpowers/specs/2026-07-16-sidebar-feeds-performance-design.md`.

## Reproduzierbare Ausführung

Optimierter Messlauf:

```bash
xcodebuild test \
  -project Feedivo.xcodeproj \
  -scheme Feedivo \
  -configuration Release \
  ENABLE_TESTABILITY=YES \
  -destination 'platform=macOS' \
  -only-testing:'FeedivoTests/SQLiteLargeDatasetPerformanceTests/zielbestandMitTieferPaginationBleibtReaktionsschnell()'
```

Time Profiler gegen denselben Testprozess:

```bash
xcrun xctrace record \
  --template 'Time Profiler' \
  --attach <Feedivo-Testprozess-PID> \
  --time-limit 15s \
  --output /tmp/FeedivoPerformance.trace
```

## Historischer Lauf 2026-07-04

Der frühere Testbestand umfasste 100 Feeds und 60'000 Artikel. Seine drei
Tests waren unter den damaligen groben Schwellwerten grün, protokollierten aber
keine Einzelwerte und prüften weder 500 Feeds noch tiefe Pagination. Der neue
Benchmark ersetzt diesen Lauf als maßgeblichen Nachweis für Feature 26.2; die
kleineren Regressionstests bleiben zusätzlich erhalten.
