# SwiftData vollständig entfernen — Phase 3 Design

## Ziel

Phase 1 hat 13 komplett tote SwiftData-Dateien gelöscht. Phase 2 hat 6 Dateien mit gemischtem
toten/aktiven Code methodengenau bereinigt, dabei aber bewusst die 9 `@Model`-Klassen selbst
unangetastet gelassen. Phase 3 entfernt SwiftData vollständig: alle verbleibenden toten
`@Model`-Verwendungen in Produktionscode und Tests, und am Ende die 9 `@Model`-Klassen selbst.

## Verifizierte Grundlage

Bereits vor Phase 3 bestätigt (Phase 1/2-Recherche): kein `ModelContainer`/`ModelContext` wird
irgendwo in der laufenden App instanziiert, `.modelContainer(...)` als Scene-Modifier existiert
nirgends. Das SwiftData-Persistenz-Stack ist zur Laufzeit vollständig inert.

Für Phase 3 zusätzlich verifiziert: In `FeedViewModel.swift` sind alle SwiftData-Bridge-Methoden
entweder explizit `@available(*, deprecated, ...)` markiert oder (ein Fall: `importOPMLFeeds`)
strukturell tot, weil beide Produktions-Aufrufer immer den SQLite-Zweig nehmen.
`SwiftDataBridgeSettings.defaultIsEnabled` ist `false` — der eine Schalter, der den Bridge-Pfad
reaktivieren könnte, ist per Produktions-Default aus.

Die 9 `@Model`-Klassen: `Article`, `Feed`, `FeedFolder`, `FeedLogEntry`, `Rule`, `RuleCondition`,
`SmartFolder`, `SmartFolderCondition`, `Tag` (je eine Datei unter `Feedivo/Models/`).

## Verifizierte Fakten pro Datei

### Komplett tote Produktionsdateien (löschen, wie Phase 1)

- **`Feedivo/Services/SmartFolderEngine.swift`** — `SmartFolderEngine` (alle static funcs) und
  `SmartFolderPreparedMatcher` haben 0 Referenzen außerhalb der eigenen Datei.
- **`Feedivo/Services/OfflineDownloadService.swift`** — `OfflineDownloadService` wird nur
  innerhalb der eigenen Datei konstruiert (0 externe Aufrufer von `saveForOffline`/
  `archiveForOffline`/`removeArchive`/`removeOfflineContent`/`summary(for:)`/
  `removeOfflineCopies(from:)`); abgelöst durch `SQLiteOfflineDownloadService`
  (`Feedivo/Stores/SQLiteOfflineStore.swift:146`), das dieselbe `OfflineArticleStorageSummary`
  nutzt.

### Produktionsdateien mit gemischtem toten/aktiven Code (methodengenau bereinigen, wie Phase 2)

- **Korrektur nach Task-2-Implementierung:** `Feedivo/Views/Sidebar/SmartFilter.swift` wurde
  ursprünglich fälschlich als komplett tot eingestuft. Tatsächlich ist NUR die Methode
  `includes(_ article: Article, now:calendar:)` tot (0 Aufrufer). Das Enum selbst
  (`SmartFilter` mit den Cases `.allArticles`/`.unread`/`.starred`/`.today`/`.hidden`, plus
  `.title`, `.systemImage`, `.iconColor`, `.id`) ist ein lebendiger Navigations-/Auswahltyp,
  verifiziert genutzt in `SQLiteFeedArticleListState.swift` (`case smartFilter(SmartFilter)`),
  `Stores/TimelineStore.swift` (`case smartFilter(SmartFilter)`),
  `Views/ContentView.swift` (`selectedSmartFilter: SmartFilter?`),
  `Views/Sidebar/SidebarSelection.swift` (`case smartFilter(SmartFilter)`),
  `Views/ArticleList/SQLiteFeedArticleListView.swift` (mehrere `SmartFilter`-Parameter/Cases).
  `SmartFilterIconColor` bleibt ebenfalls vollständig (genutzt von `.iconColor`). Diese Datei
  gehört daher in diesen Abschnitt (gemischt, methodengenau bereinigen), nicht in den Abschnitt
  "komplett tot".
- **`Feedivo/Views/Sidebar/SmartFilter.swift`** — Tot: nur `includes(_ article: Article,
  now:calendar:)`. Lebendig: der gesamte Rest der Datei (Enum-Cases, `.title`, `.systemImage`,
  `.iconColor`, `.id`, `SmartFilterIconColor`) — siehe Korrektur oben.
- **`Feedivo/Services/RuleEngine.swift`** — Tot: `applyRules(_:to:feed:)`,
  `applyRulesWithNotifications(_:to:feed:)` (Einzelartikel- und `[Article]`-Overload),
  `snapshots(from:)`, `applyRulesToExistingArticles(_:articles:)`,
  `matchingArticleCount(conditionDrafts:matchMode:articles:[Article])`, plus private Helfer
  (`applyPreparedRulesWithNotifications`, `synchronizeUnreadCount`, `preparedRules([Rule])`,
  `sortedRules([Rule])`, `normalizedConditions(for:Rule)`, `matches(...feed:Feed)`,
  `fieldValue(...feed:Feed)`, `notificationResult`/`notificationMessage` für `Rule`). Einziger
  Aufrufer der `[Article]`-Overload war `FeedViewModel.refreshFeedContents` (selbst nur aus
  deprecated Methoden erreichbar — verifiziert). Lebendig: `applySQLiteRules(...)`,
  `matchingArticleCount(...[ArticleRuleSnapshot])`, alle Snapshot-typisierten privaten Helfer —
  aufgerufen von `SQLiteRuleEvaluationStore.swift`, `SQLiteFeedRefreshService.swift`.
- **`Feedivo/Views/SmartFolders/SmartFolderFormatter.swift`** — Tot:
  `conditionSummary(for:SmartFolder)`, `includesHiddenStatus`, `showsReadArticlesByDefault`,
  `systemImage(for:SmartFolder)`, `color(for:SmartFolder)`, `drafts(for:SmartFolder)`,
  `sortedConditions(for:SmartFolder)`, `conditionDescription(_:SmartFolderCondition)`. Lebendig:
  die gleichnamigen `SmartFolderRecord`/`SmartFolderConditionRecord`-Overloads, aufgerufen von
  `SmartFolderSettingsView.swift`, `SmartFolderEditorView.swift`, `SQLiteSmartFolderSnapshot.swift`.
- **`Feedivo/Views/ArticleList/ArticleFilterOption.swift`** — Tot: `filtered(_:[Article])`,
  `includes(_:Article...)`. Lebendig: `.allCases`, `.storageKey`, `.resolved(from:)` (genutzt von
  `SQLiteFeedArticleListView.swift`).
- **`Feedivo/Views/ArticleList/ArticleMarkReadOption.swift`** — Tot:
  `matchingArticles(in:[Article])`, `includes(_:Article...)`, private `isArticle(_:Article...)`.
  Lebendig: `.allCases` (Menü in `SQLiteFeedArticleListView.swift`); die eigentliche
  Mark-as-read-Logik läuft über einen separaten SQLite-Row-Pfad.
- **`Feedivo/Views/ArticleList/ArticleSortOption.swift`** — Tot: `sorted(_:[Article])` + private
  Helfer, die nur davon aufgerufen werden (`newestFirst`/`oldestFirst`/`readingMinutes(for:Article)`
  sowie deren generische Sub-Helfer, sobald `sorted(_:)` weg ist). Lebendig: `.storageKey`,
  `.allCases`, `.resolved(from:)` (`ViewCommands.swift`, `SQLiteFeedArticleListView.swift`); das
  eigentliche Row-Sortieren läuft über einen eigenen Comparator in
  `SQLiteFeedArticleListView.swift:286`, nicht über diesen Enum.
- **`Feedivo/Views/Sidebar/FeedPropertiesFormatter.swift`** — Tot: `latestArticle(in:[Article])`,
  `recentArticleCount(in:[Article])`, `latestLogEntries(_:[FeedLogEntry])`,
  `latestLogEntryCount(_:[FeedLogEntry])`. Lebendig: `linkURL(_:)`, `copyableXMLAddress(_:)`,
  `nextRefreshDate(lastRefreshed:intervalMinutes:)` — aufgerufen von `FeedPropertiesView.swift`.
- **`Feedivo/Views/Sidebar/FeedFolderOrganizer.swift`** — Tot: `folderNames(in:[Feed],
  folders:[FeedFolder])`, `feedsWithoutFolder(from:[Feed])`, `visibleFeeds(from:[Feed])` (0
  Aufrufer überhaupt), `feeds(in:from:[Feed])` (0 Aufrufer überhaupt),
  `feedsByFolderName(in:[Feed], folders:[FeedFolder])`, private `sortedFeeds(_:[Feed])`. Lebendig:
  `folderNames(feedFolderNames:explicitFolderNames:)` (String-basiert),
  `feedsWithoutFolder(from:[FeedSidebarSnapshot])`,
  `feedsByFolderName(in:[FeedSidebarSnapshot], folders:[FeedFolderRecord])`,
  `normalizedFolderName` — aufgerufen von `SidebarView.swift`, `FeedStore.swift`,
  `SQLiteReaderView.swift`, `ArticleMetadataInspectorView.swift`,
  `SQLiteFeedSubscriptionService.swift`.
- **`Feedivo/Snapshots/ArticleReaderSnapshot.swift`** — Tot: `ReaderArticleTagMetadata.init(tag:
  Tag)`. Lebendig: `init(record: TagRecord)`, der Rest der Datei.
- **`Feedivo/Snapshots/SQLiteSmartFolderSnapshot.swift`** — Tot:
  `SQLiteSmartFolderSnapshot.init(folder: SmartFolder)`,
  `SQLiteSmartFolderConditionSnapshot.init?(condition: SmartFolderCondition)`. Lebendig:
  memberwise init, `init(id:name:matchMode:conditionDrafts:)`, `init(folder: SmartFolderRecord,
  conditions:)`, `init?(condition: SmartFolderConditionRecord)`.
- **`Feedivo/Views/Sidebar/SidebarUnreadCount.swift`** — Tot:
  `SmartFolderSidebarBadgeKind.init?(folder: SmartFolder)`. Lebendig:
  `init?(folder: SQLiteSmartFolderSnapshot)` (einziger Aufrufer: `SidebarView.swift:481`),
  `SidebarUnreadCount.badgeText`, `SmartFolderSidebarBadge.badgeText/badgeCount`,
  `SidebarBadgeInvalidation` (unangetastet lassen, siehe Phase-2-Constraint). Nach Entfernen des
  toten Inits `import SwiftData` auf Notwendigkeit prüfen.
- **`Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift`** — Tot:
  `availableFolders(existingFeeds: [Feed])` (0 Aufrufer). Lebendig:
  `availableFolders(existingFolderNames:)` (aufgerufen von `FirstRunWizardView.swift:681`,
  `OPMLImportReviewView.swift:332`).
- **`Feedivo/ViewModels/FeedViewModel.swift`** (größter Task) — Tot: 6
  `@available(*, deprecated)`-Methoden (`renameFeed(_:displayTitle:context:)`,
  `restoreOriginalFeedTitle(_:context:)`, `addFeed(urlString:context:sqliteDatabase:)`,
  `refreshFeed(_:context:sqliteDatabase:)`, `refreshAllFeeds(_:context:sqliteDatabase:)`,
  `deleteFeed(_:context:)`), plus die unmarkierte, aber tote SwiftData-Hälfte von
  `importOPMLFeeds(...context:sqliteDatabase:)` (beide Produktions-Aufrufer übergeben immer
  `sqliteDatabase` und nie `context`, sodass der SwiftData-Zweig nie erreicht wird), plus 6 private
  Helfer, die ausschließlich diesen toten Pfaden dienen (`mirrorFeedToSQLite`,
  `articlesForSQLiteMirror`, `refreshFeedContents`, `existingArticlesByIdentity`, `appendLog`,
  `pruneLogEntries`). Lebendig: die SQLite-first-Overloads mit denselben Basisnamen
  (`addFeed(urlString:sqliteDatabase:)`, `refreshFeed(feedID:sqliteDatabase:)`,
  `refreshAllFeeds(sqliteDatabase:)`, `deleteFeed(feedID:sqliteDatabase:)`).
- **`Feedivo/Services/ArticleRetentionCleanupService.swift`** — Tot: der vestigiale, unbenannte
  `in _: ModelContext? = nil`-Parameter auf `removeExpiredSQLiteArticles` (nie im Funktionskörper
  gelesen, immer nil).
- **`Feedivo/Services/SQLiteFeedSubscriptionService.swift`** — Tot: `context: ModelContext? =
  nil`-Parameter auf `addFeed`/`importOPMLFeeds`, private `shouldUseSwiftDataBridge(context:)`,
  `saveSwiftDataBridge(_:context:)`. Alle Produktions-Aufrufer übergeben `context: nil`.

### Testdateien

**Komplett löschen:** `RuleConditionTests.swift`, `SmartFolderConditionTests.swift`,
`SmartFolderEngineTests.swift` (alle 7 Tests treiben das komplett tote `SmartFolderEngine.swift`),
`SmartFilterTests.swift` (alle 6 Tests treiben das komplett tote `SmartFilter.swift`),
`OfflineDownloadServiceTests.swift` (alle 13 Tests treiben das komplett tote
`OfflineDownloadService.swift`).

**Teilweise bereinigen** (tote Tests raus, lebendige/schon-SQLite-native Tests bleiben
unverändert): `FeedViewModelTests.swift` (~28 tote `context:`-basierte Tests von ~53 gesamt),
`RuleEngineTests.swift` (~11 tote `applyRules`/`applyRulesToExistingArticles`-Tests von 17 gesamt;
1 Test nutzt bereits `ArticleRuleSnapshot` und bleibt unverändert; die 4
`previewMatchingArticleCount`-Tests werden erneut geprüft — falls sie den lebendigen
Snapshot-Overload testen bleiben sie, falls den toten `[Article]`-Overload werden sie gelöscht),
`SQLiteFeedSubscriptionServiceTests.swift` (~12 tote Bridge-Tests von ~18 gesamt),
`ArticleListQueryTests.swift` (3 Tests brauchen Fixture-Migration statt Löschung, siehe unten),
`FeedivoTests.swift` (2 tote Default-Werte-Tests von ~52 gesamt), `AppIconBadgeServiceTests.swift`
(1 toter Test von 6), `SQLiteAdminStoreTests.swift` (nur der unbenutzte private
`testContext()`-Helfer entfernen, alle 6 echten Tests bleiben unverändert),
`FeedivoAppSceneConfigurationTests.swift` (1 Test, der Model-Dateien per Pfad liest, wird
gegenstandslos und muss entfernt werden — der Rest der Datei bleibt), `FeedFolderOrganizerTests.swift`
(alle 7 Tests treiben die toten `[Feed]`/`[FeedFolder]`-Overloads — löschen, nicht migrieren, da
diese Methoden komplett verschwinden), `FeedPropertiesFormatterTests.swift` (4 von 6 Tests treiben
tote Methoden — löschen), `ArticleSortOptionTests.swift` (alle 7 Tests treiben die tote
`sorted([Article])`-Methode — löschen, nicht migrieren, da diese Methode komplett verschwindet).

**Fixture-Migration** (Test bleibt, `Article(...)`/`Feed(...)`-Konstruktion wechselt auf
SQLite-native Typen wie `ArticleReaderSnapshot`/`FeedRecord`): `ArticleExportServiceTests.swift`
(~25 von 27 Tests — ein Test, `sqliteExportSnapshotNutztOfflineVolltextUndTags`, nutzt bereits das
Zielmuster und dient als Vorlage), `SQLiteSidebarStateTests.swift` (1 Test,
`visibleSnapshotsFollowSQLiteVisibility`, nutzt `Feed(url:...)` nur um an eine `.id.uuidString` zu
kommen — trivial durch eine rohe UUID-Zeichenkette ersetzbar),
`ArticleRetentionCleanupServiceTests.swift` (die 5 verbleibenden `sqliteCleanup...`-Tests nutzen
einen `testContext()`-Helfer, der einen echten `ModelContainer` aufbaut, nur um an ein `Feed`-Objekt
für den vestigialen `ModelContext?`-Parameter zu kommen — sobald dieser Parameter in der
Produktionsdatei entfernt ist, entfällt auch dieser Helfer und der Parameter im Testaufruf),
`OPMLImportPreviewControllerTests.swift` (1 Test, `availableFoldersFasstExistingPreviewUndCustomZusammenUndSortiert`,
muss auf `availableFolders(existingFolderNames:)` umgestellt werden, da der `existingFeeds:
[Feed]`-Overload verschwindet).

### Model-Löschung (letzter Task)

Alle 9 Dateien unter `Feedivo/Models/` löschen, sobald alle obigen Tasks abgeschlossen sind:
`Article.swift`, `Feed.swift`, `FeedFolder.swift`, `FeedLogEntry.swift`, `Rule.swift`,
`RuleCondition.swift`, `SmartFolder.swift`, `SmartFolderCondition.swift`, `Tag.swift`. Danach
verbleibende `import SwiftData`-Vorkommen final prüfen und entfernen (erwartet: keine mehr
außerhalb der bereits in dieser Phase bereinigten Dateien).

## Vorgehen

Wie Phase 1/2: ein Plan mit allen Tasks in der oben beschriebenen Reihenfolge (Produktionsdateien
→ Testdateien → Model-Löschung als letzter Task), Subagent-Driven-Development-Ausführung,
Task-Review nach jedem Task, finaler Whole-Branch-Review. Jeder Implementierer verifiziert vor dem
Löschen erneut per `grep`, genau wie in Phase 1/2 etabliert — insbesondere bei den als "komplett
tot" eingestuften Dateien und bei den in diesem Dokument explizit offen gelassenen
Verifikationspunkten (`opmlFeedsForExport(from: [Feed])` in `FeedViewModel.swift`/
`FeedViewModelTests.swift`; die 4 `previewMatchingArticleCount`-Tests in `RuleEngineTests.swift`).

Fixture-Migration nutzt durchgängig bereits existierende SQLite-native Typen (keine neuen
Test-only-Typen).

## Nicht Teil dieser Phase

- Keine funktionale Verhaltensänderung an lebendigem Code.
- Kein CloudKit/iCloud-Sync-Bezug (war laut Projektdokumentation nie aktiviert, bleibt so).

## Tests

Kein neuer Testcode nötig — reine Lösch-/Migrations-Operation. Erfolgskriterium: Build bleibt
grün, bestehende gescopte Tests bleiben grün (volle ungefilterte Suite hängt weiterhin
nachweislich, gescopte `-only-testing:`-Läufe nutzen). Bekannte vorbestehende Fehlschläge (5 in
`FeedivoAppSceneConfigurationTests`, 3 in `SQLiteReaderStateTests`) bleiben unverändert und sind
nicht Teil dieser Phase.
