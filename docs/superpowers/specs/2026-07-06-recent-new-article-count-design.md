# "Neu"-Zähler nur für kürzlich veröffentlichte Artikel Design

## Ziel

Der "X neu"-Status-Pill in `ContentView` (sowie System-Benachrichtigungen und Log-Einträge, die denselben
Wert verwenden) zeigte nach einem Refresh "2'558 neu" an. Direkt in der SQLite-Datenbank verifiziert: Zwei
Feeds ("OpenAI News", "Microsoft Support – Windows 11") liefern ihr komplettes historisches Archiv
(1028 bzw. 1000 Artikel, Veröffentlichungsdaten von 2016 bzw. Oktober 2024 bis heute) statt nur aktueller
Einträge. Diese wurden beim Import 1:1 als "neu" gezählt, obwohl sie teils Jahre alt sind.

## Design

### Prinzip

`insertedArticleIDs` (alle neu in die lokale Datenbank eingefügten Artikel-IDs) bleibt unverändert — wird
weiterhin für Regelanwendung (`applyRules`) und Ungelesen-Zählung genutzt, da dort jede neue Zeile
unabhängig vom Veröffentlichungsdatum verarbeitet werden muss.

Zusätzlich wird ein neuer, gefilterter Zähler eingeführt: nur Artikel mit `publishedAt` innerhalb der
letzten **48 Stunden** gelten als "neu" im Sinne der Nutzer-Anzeige (Status-Pill, System-Benachrichtigungen,
Log-Einträge). Feste Schwelle, kein neues Nutzer-Setting.

### Betroffene Komponenten (aktiver SQLite-Refresh-Pfad)

- `Feedivo/Stores/ArticleStore.swift`: neue Methode
  `func recentlyPublishedCount(articleIDs: [String], since: Date) throws -> Int` — zählt per SQL, wie viele
  der übergebenen IDs ein `publishedAt >= since` haben (NULL-`publishedAt` zählt nicht als "neu").
- `Feedivo/Services/SQLiteFeedRefreshService.swift`: `SQLiteFeedRefreshResult` bekommt ein neues Feld
  `newArticleCount: Int` (getrennt von `insertedArticleIDs.count`). In `refresh(feedID:)` wird dieser Wert
  direkt nach dem Upsert berechnet (`recencyCutoff = now().addingTimeInterval(-48 * 3600)`) und sowohl für
  das neue Feld als auch für den bestehenden `FeedLogRecord.newArticleCount`-Parameter verwendet
  (statt `upsertResult.insertedArticleIDs.count`).
- `Feedivo/Services/SQLiteFeedRefreshCoordinator.swift`: `FeedRefreshNotificationResult(newArticleCount:)`
  wird aus `result.newArticleCount` (neues Feld) statt `result.insertedArticleIDs.count` befüllt. Da
  System-Benachrichtigungen (`FeedNotificationService`) und der Status-Pill (`ContentView`,
  `FeedRefreshStatusSummary`) beide aus `FeedRefreshNotificationResult`/den daraus summierten Werten
  gespeist werden, korrigiert diese eine Änderung alle drei Anzeigeorte gleichzeitig.

### Nicht Teil dieses Designs

- `Feedivo/Services/FeedBackgroundRefreshService.swift` (Legacy-Pfad, im SQLite-only-Setup nicht mehr
  erreichbar) wird nicht angepasst.
- Kein neues Nutzer-Setting für die 48h-Schwelle.
- Keine rückwirkende Korrektur bereits als "neu" gezählter/benachrichtigter Artikel — nur zukünftige
  Refreshs sind betroffen.

## Tests

`recentlyPublishedCount` und die angepasste `newArticleCount`-Berechnung in `SQLiteFeedRefreshService`
bekommen Unit-Tests: ein Refresh mit gemischten alten/neuen `publishedAt`-Werten muss nur die kürzlich
veröffentlichten zählen, während `insertedArticleIDs`/Regelanwendung weiterhin alle neuen Zeilen umfasst.
Ein Artikel ohne `publishedAt` (NULL) darf nicht als "neu" gezählt werden.
