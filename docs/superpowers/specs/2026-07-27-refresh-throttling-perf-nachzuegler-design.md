# Refresh-Throttling + zwei Perf-Nachzügler (NetNewsWire-Vergleich) — Design

Stand: 2026-07-27

## Kontext und Motivation

Im NetNewsWire-Vergleich vom 2026-07-27 (siehe Chat-Verlauf, aufbauend auf
`docs/performance/netnewswire-feedivo-mechanik-vergleich.md` und
`docs/performance/feedivo-performance-feature-integration-audit-2026-07-15.md`)
wurden fünf konkrete Punkte identifiziert. Zwei davon (`PRAGMA synchronous =
NORMAL`, RuleEngine-Persistenz in einer Transaktion) sind bereits umgesetzt
(Commit `e789eb6`). Dieses Dokument deckt die drei verbleibenden Punkte ab:

1. Refresh-Throttling (Mindestabstand pro Feed beim Refresh-All)
2. `SQLiteUnreadCountService.rebuildAllFeedUnreadCounts()` auf gruppierte CTE
   umstellen
3. Favicon-Single-Flight-Dedup

Alle drei sind unabhängig voneinander umsetzbar und werden hier als ein
gemeinsamer, aber intern klar getrennter Plan behandelt.

## 1. Refresh-Throttling

### Problem

`SQLiteFeedRefreshCoordinator.refreshAllFeeds` hat aktuell keinerlei Schutz
gegen zu häufiges Refreshen desselben Feeds. NetNewsWire (`LocalAccountRefresher.
swift`) schützt sich dagegen über `minimumTimeBetweenChecks = 9 * 60`
Sekunden pro Feed, basierend auf `feed.lastCheckDate` — einem Zeitstempel, der
bei **jedem** Abrufversuch gesetzt wird, auch bei Fehlern (`downloadDidComplete`/
`httpError`-Callbacks in `LocalAccountRefresher.swift`).

### Warum nicht `FeedRecord.lastRefreshedAt`

Dieses Feld wird in Feedivo nur bei **erfolgreichem** Abschluss eines Refreshs
gesetzt (`SQLiteFeedRefreshService.refresh` ruft `feedStore.updateAfterRefresh`
nur in den `.notModified`/`.updated`-Zweigen auf, nicht im `catch`-Block). Es
wird außerdem in der UI als „Zuletzt aktualisiert: …" angezeigt (Feature
„Feed-Status-Zeile im Artikellisten-Header", 2026-07-12). Würde man dieses
Feld auch bei fehlgeschlagenen Versuchen setzen, um es fürs Throttling zu
nutzen, würde die UI einen fehlgeschlagenen Versuch fälschlich als
erfolgreiches Update anzeigen. Deshalb wird eine andere, bereits vorhandene
Quelle genutzt.

### Lösung: `feed_logs` als Attempt-Zeitstempel-Quelle

`SQLiteFeedRefreshService.refresh` schreibt bereits in **allen drei** Zweigen
(`.notModified`, `.updated`, `catch`) einen `FeedLogRecord` mit
`createdAt: refreshedAt` — das ist exakt „Zeitpunkt des letzten
Abrufversuchs", unabhängig vom Ergebnis. Keine neue Migration/Spalte nötig.

**Neue Bausteine:**

- `FeedLogStore.latestAttemptTimes() throws -> [String: Date]` — eine
  gruppierte Query (`SELECT feedID, MAX(createdAt) FROM feed_logs GROUP BY
  feedID`), analog zur `latest_feed_logs`-CTE in `FeedStore.sidebarFeeds()`.
  Eine einzige Abfrage für alle Feeds statt N Einzelabfragen im Batch-Loop.
- `enum FeedRefreshThrottle` (neue Datei `Feedivo/Services/
  FeedRefreshThrottle.swift`) mit reiner, isoliert testbarer Funktion:
  ```swift
  static func shouldSkip(
      lastAttemptAt: Date?,
      now: Date,
      minimumInterval: TimeInterval = 9 * 60
  ) -> Bool
  ```
  `lastAttemptAt == nil` (noch nie versucht) → nie überspringen.

### Integration in `SQLiteFeedRefreshCoordinator.refreshAllFeeds`

Vor dem Batching wird `FeedLogStore(database:).latestAttemptTimes()` einmal
geladen. Für jeden `FeedRefreshSnapshot` in der Schleife:

- `FeedRefreshThrottle.shouldSkip(...)` prüfen.
- Bei `true`: **kein** Task wird für diesen Feed gestartet, **kein**
  `feed_logs`-Eintrag wird geschrieben (wichtig — sonst würde jedes weitere,
  schnell aufeinanderfolgende Refresh-All das Zeitfenster immer wieder nach
  vorne verschieben und der Feed könnte bei sehr häufigem manuellem
  Refresh-All faktisch nie mehr drankommen), keine Notification, kein
  Fehlereintrag.
- Neues Feld `skippedFeedIDs: [UUID]` in `SQLiteFeedRefreshCoordinatorSummary`
  — rein intern/testbar, keine UI-Oberfläche in diesem Schritt (YAGNI,
  analog zur Host-Blockliste-Entscheidung).

**Scope-Entscheidung (bestätigt):** Throttling gilt nur für `refreshAllFeeds`
(automatischer Hintergrund-Zyklus **und** manuelles „Alle aktualisieren").
Ein gezielter Einzel-Feed-Refresh über das Kontextmenü (`SQLiteFeedRefreshService.
refresh(feedID:)` direkt aufgerufen, nicht über den Coordinator) bleibt
davon unberührt und liefert immer einen echten Versuch.

**Schwellwert:** fest 9 Minuten (wie NetNewsWire), kein neuer
Einstellungen-Eintrag. Keine Host-Blockliste (YAGNI ohne belegten Bedarf für
Feedivo, siehe Entscheidung im Chat).

### Testing

- `FeedRefreshThrottle.shouldSkip` — reine Unit-Tests (nil-Fall, knapp
  unter/über der Schwelle, exakt an der Schwelle).
- `FeedLogStore.latestAttemptTimes()` — gegen eine In-Memory-DB mit mehreren
  Feeds/mehreren Log-Zeilen pro Feed, erwartet den jeweils neuesten
  Zeitstempel.
- `SQLiteFeedRefreshCoordinator.refreshAllFeeds` — Regressionstest: Feed mit
  einem `feed_logs`-Eintrag vor < 9 Minuten wird übersprungen (kein Fetcher-
  Aufruf, per Spy-Fetcher verifiziert, der `fatalError`/Flag setzt, falls
  aufgerufen), Feed mit Eintrag vor > 9 Minuten wird normal refresht, Feed
  ganz ohne Eintrag wird normal refresht.

## 2. `rebuildAllFeedUnreadCounts()` — gruppierte CTE

### Problem

`SQLiteUnreadCountService.rebuildAllFeedUnreadCounts()` läuft zwar bereits in
einer einzigen Transaktion, ruft aber intern für jeden Feed einzeln
`unreadCount(feedID:db:)` auf — eine korrelierte Subquery pro Feed
(`unreadCountSQL`, gefiltert über `WHERE a.feedID = ?`). Bei vielen Feeds
skaliert das linear mit der Feed-Zahl (exakt dasselbe Muster, das bei
`sidebarFeeds()` vor dem Fix vom 2026-07-16 zu 10,9s bei 500 Feeds führte,
hier bislang nur nicht im Direktpfad gemessen, da nur beim seltenen
Backfill-/Resync-Pfad genutzt).

### Lösung

Neue gruppierte Query, analog zur bereits bewährten
`unread_counts`-CTE aus `FeedStore.sidebarFeeds()`:

```sql
SELECT a.feedID, COUNT(*) AS unreadCount
FROM article_statuses s
JOIN articles a ON a.id = s.articleID
WHERE s.isRead = 0 AND s.isHidden = 0
GROUP BY a.feedID
```

`rebuildAllFeedUnreadCounts()` lädt diese Map einmal, iteriert dann über
`SELECT id FROM feeds` (wie bisher) und schreibt pro Feed ein `UPDATE feeds
SET unreadCount = ?, updatedAt = ? WHERE id = ?` mit dem Wert aus der Map
(Default `0`, falls der Feed nicht in der Map vorkommt — keine ungelesenen
Artikel). Die einzelnen `UPDATE`s bleiben bestehen (sie sind PK-indiziert und
günstig; der Engpass war ausschließlich die vorgeschaltete `COUNT`-Subquery
pro Feed, nicht das `UPDATE`).

`rebuildFeedUnreadCount(feedID:)` (Einzelfeed-Variante, z. B. nach dem
Lesen/Sternen eines einzelnen Artikels) bleibt unverändert — dort ist eine
einzelne indizierte Subquery bereits optimal, eine gruppierte Query würde
dort nur unnötig mehr Zeilen laden.

### Testing

Regressionstest analog zum bestehenden `sidebarFeeds()`-Performance-Test:
mehrere Feeds mit unterschiedlichen Ungelesen-Zahlen seeden,
`rebuildAllFeedUnreadCounts()` aufrufen, erwartete Zählungen je Feed
verifizieren (Verhaltenstest, kein neuer Lasttest nötig — das Muster ist
durch den bestehenden `sidebarFeeds()`-Lasttest bereits als schnell belegt).

## 3. Favicon-Single-Flight-Dedup

### Problem

`SQLiteFeedRefreshCoordinator.refreshAllFeeds` refresht bis zu
`maxConcurrentFeedRefreshes` (6) Feeds gleichzeitig. Teilen sich mehrere
gleichzeitig refreshte Feeds dieselbe `siteURL` (z. B. mehrere Feeds
derselben Blog-Plattform), ruft `SQLiteFeedRefreshService.
faviconURLIfNeeded` für jeden davon unabhängig `FaviconService.
discoverFaviconURL(siteURL:)` auf — mehrfache, redundante HTML-Fetches für
dieselbe Seite innerhalb desselben Batches.

### Lösung

`FaviconService` bleibt bewusst ein zustandsloser `enum` (rein, gut testbar).
Neuer, separater Baustein für die Deduplizierung:

```swift
actor FaviconDiscoveryCoordinator {
    private var inFlight: [String: Task<String?, Never>] = [:]

    func discover(
        siteURL: URL,
        using discover: @escaping (URL) async -> String? = { url in
            await FaviconService.discoverFaviconURL(siteURL: url)
        }
    ) async -> String? {
        let key = siteURL.absoluteString
        if let existing = inFlight[key] {
            return await existing.value
        }
        let task = Task { await discover(siteURL) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }
}
```

Kein Langzeit-Cache — Einträge werden direkt nach Abschluss entfernt, dedupt
also ausschließlich *gleichzeitig* laufende Anfragen innerhalb desselben
Batches, kein Stale-Data-Risiko bei später geänderten Favicons.

### Integration

`SQLiteFeedRefreshCoordinator` erhält ein neues privates Property
`private let faviconDiscoveryCoordinator = FaviconDiscoveryCoordinator()`
(eine Instanz pro Coordinator-Aufruf/`refreshAllFeeds`-Batch). Beim
Erzeugen jeder `SQLiteFeedRefreshService`-Instanz innerhalb der
Batch-Schleife wird der bereits bestehende `discoverFaviconURL`-
Konstruktorparameter (bisher ungenutzter Default) auf
`{ [faviconDiscoveryCoordinator] siteURL in await
faviconDiscoveryCoordinator.discover(siteURL: siteURL) }` gesetzt. Keine
neue öffentliche API auf `SQLiteFeedRefreshCoordinator` nötig — die
Deduplizierung ist für Aufrufer transparent.

### Testing

- `FaviconDiscoveryCoordinator` — Unit-Test mit zwei gleichzeitigen Aufrufen
  für dieselbe `siteURL` und einem Spy-`discover`-Closure, der die
  Aufrufzahl zählt: erwartet genau 1 Aufruf trotz 2 gleichzeitiger
  `discover(siteURL:)`-Aufrufe, aber beide erhalten das korrekte Ergebnis.
  Zusätzlich: zwei verschiedene `siteURL`s lösen 2 unabhängige Aufrufe aus.
- `SQLiteFeedRefreshCoordinator` — Regressionstest mit zwei Feeds derselben
  `siteURL`, Spy-Favicon-Fetcher zählt Aufrufe, erwartet 1 statt 2.

## Nicht-Ziele

- Keine Host-Blockliste (siehe Entscheidung oben).
- Keine neue Einstellungen-UI für den Throttling-Schwellwert.
- Kein Langzeit-Cache für Favicon-Discovery (nur Batch-interne
  Deduplizierung).
- `WAL`/`DatabasePool`-Wechsel bleibt weiterhin bewusst nicht verfolgt
  (bereits in Commit `e789eb6` begründet).
