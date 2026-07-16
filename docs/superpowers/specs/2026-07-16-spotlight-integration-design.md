# Spec: Spotlight-Integration (Feature 9.3)

**Datum:** 2026-07-16
**Status:** Genehmigt, bereit für Implementierung

## Problem

Artikel in Feedivo sind aktuell nur über die App selbst durchsuchbar (Volltextsuche, Suchfenster).
macOS Spotlight kennt sie nicht. FEATURES.md 9.3 verlangt:
- Artikel als Core Spotlight Items indexieren via `CSSearchableItem`
- Klick auf Spotlight-Resultat öffnet Feedivo direkt beim Artikel (Deep Link)
- Einstellungen → Toggle "Artikel in Spotlight indexieren" (an/aus)

## Architektur-Entscheidung

**Direkte Hooks an den bestehenden Insert-/Delete-Stellen**, statt eines zentralen Coordinators
(scheitert daran, dass `SQLiteDataInvalidation`-Statusbumps nicht verraten, *was* sich geändert
hat) oder eines periodischen Hintergrundabgleichs (bräuchte eine eigene "was wurde indexiert"-
Tracking-Tabelle, verzögerte Sichtbarkeit neuer Artikel). Die direkten Hooks sind punktgenau und
sofort wirksam.

## Neue Dateien

### `Feedivo/Services/SpotlightIndexingSettings.swift`
Nach Vorbild von `NotificationSettings.swift`:
- `isEnabledKey = "spotlight.isEnabled"`, Default `true`
- `hasBackfilledKey = "spotlight.hasBackfilled"`, Default `false`
- `isEnabled(in:)` / `hasBackfilled(in:)` mit sicherem `object(forKey:) != nil`-Guard (gleiches
  Muster wie `NotificationSettings.isMasterEnabled(in:)`, verhindert den bekannten
  UserDefaults-Default-Bug)
- `setHasBackfilled(_:in:)` Setter

### `Feedivo/Services/SpotlightIndexingService.swift`
Dünner Wrapper um `CSSearchableIndex.default()`:
- `static let domainIdentifier = "ch.martin.Feedivo.articles"`
- `indexArticles(_ articles: [ArticleRecord], feedTitlesByID: [String: String], userDefaults:)` —
  no-op wenn `SpotlightIndexingSettings.isEnabled == false`. Baut pro Artikel ein
  `CSSearchableItem`:
  - `uniqueIdentifier` = `article.id` (bereits ein UUID-String — identisch zu dem, was
    `feedivo://article?id=` erwartet)
  - `domainIdentifier` = obige Konstante
  - `CSSearchableItemAttributeSet(contentType: .text)`: `title` = `article.title`,
    `contentDescription` = `article.summary?.trimmedNonEmpty ?? article.title`, `kind` =
    `feedTitlesByID[article.feedID]`
  - Ruft `indexSearchableItems(_:completionHandler:)`, Fehler → `AppLogger.dataAccess.error(...)`
- `deindexArticles(ids: [String])` — `deleteSearchableItems(withIdentifiers:)`
- `deindexAll(userDefaults:)` — `deleteAllSearchableItems()`, setzt danach
  `SpotlightIndexingSettings.setHasBackfilled(false, in: userDefaults)`
- `ensureBackfillIfNeeded(database:, userDefaults:)` — läuft nur, wenn `isEnabled == true` UND
  `hasBackfilled == false`. Lädt alle Artikel batchweise aus SQLite (bestehender
  `ArticleStore`-Zugriff, kein neuer Query-Typ nötig — einfacher `SELECT * FROM articles` in
  Chunks von z. B. 500), ruft `indexArticles` je Batch auf, setzt danach
  `setHasBackfilled(true, in: userDefaults)`

## Indexierung neuer Artikel (Insert-Pfad)

Nach `ArticleStore.upsert(_ inputs:)`:
- `SQLiteFeedRefreshService.swift:120`
- `SQLiteFeedSubscriptionService.swift:94`

wird `upsertResult.insertedArticleIDs` per bestehendem `fetchArticles(articleIDs:)`-Helper zu
vollen `ArticleRecord`s aufgelöst, zugehörige Feed-Titel per `FeedStore` nachgeladen, dann
`SpotlightIndexingService.indexArticles(...)` aufgerufen.

## Deindexierung

An beiden bestehenden Lösch-Stellen wird direkt nach dem erfolgreichen SQL-`DELETE` mit den
betroffenen IDs `deindexArticles(ids:)` aufgerufen:
- `SQLiteFeedArticleListState.swift:384` (Einzelartikel löschen)
- `ArticleRetentionCleanupService.swift:231` (Bulk-Bereinigung)

Feed-Löschung (`FeedStore.delete(id:)`) kaskadiert schon heute nicht auf Artikel — dieses
Bestandsverhalten wird durch dieses Feature nicht verändert, also auch kein Deindexierungs-Hook
dort.

## Backfill & Toggle-Verhalten

- **App-Start:** `ensureSpotlightBackfillIfNeeded()` reiht sich in `FeedivoApp.swift`s
  bestehenden Start-`.task`-Block ein, gleiches Muster wie `trimImageCacheToSelectedLimit()`.
- **Toggle AN→AUS:** sofort `deindexAll()` (setzt `hasBackfilled` zurück).
- **Toggle AUS→AN:** sofort `ensureBackfillIfNeeded()` — läuft garantiert erneut, da
  `hasBackfilled` durch das vorherige Ausschalten zurückgesetzt wurde.
- Angebunden über `.onChange(of: spotlightIsEnabled)` in `FeedivoApp.swift`, analog zum
  bestehenden `.onChange(of: articleRetentionIsEnabled)`-Muster.

## Spotlight-Klick → App (Deep Link)

`FeedivoAppDelegate` bekommt eine neue Methode:

```swift
func application(_ application: NSApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool
```

Bei `userActivity.activityType == CSSearchableItemActionType` wird
`userActivity.userInfo?[CSSearchableItemActivityIdentifier]` als String gelesen, als `UUID`
geparst und `pendingURLSchemeAction.action = .openArticle(articleID:)` gesetzt — nutzt exakt
denselben, bereits bestehenden Konsum-Pfad wie `feedivo://article?id=` (`ContentView.swift:334`).
Kein neuer Zustands-Container nötig.

## Settings-UI

Neuer Toggle "Artikel in Spotlight indexieren" im bestehenden `GeneralSettingsView`
(`Feedivo/Views/Settings/SettingsView.swift`) — kein neuer Settings-Tab. `@AppStorage` gebunden an
`SpotlightIndexingSettings.isEnabledKey`, Default `true` (stimmt mit dem Guard-Getter überein).
Neue L10n-Keys nach Schema `settings.spotlight.*`.

## Neue L10n-Keys

- `settings.spotlight.toggle.title` — "Artikel in Spotlight indexieren"
- `settings.spotlight.toggle.description` — Kurzbeschreibung (rein lokale Indexierung, kein
  Cloud-Upload)

## Out of Scope

- Keine Thumbnails/Bilder im Spotlight-Eintrag (nicht in FEATURES.md gefordert)
- Kein HTML-Stripping von `content` — nutzt `summary` mit Title-Fallback für `contentDescription`
- Keine Änderung am bestehenden Verhalten, dass Feed-Löschung ihre Artikel nicht kaskadiert
  entfernt
- Kein `updatedArticleIDs`-Re-Indexing bei Artikel-Updates (nur neue Artikel werden indexiert;
  bestehende Einträge, deren Titel/Summary sich durch einen erneuten Feed-Fetch ändern, werden
  nicht aktiv aktualisiert — Edge Case, in der Praxis selten und für Spotlight-Auffindbarkeit
  nicht kritisch)
