# NetNewsWire SQLite Structure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Feedivo soll für Feed-/Artikelhandling strukturell möglichst nah an NetNewsWire liegen: eine klare SQLite/GRDB-Datenbankschicht als einzige produktive Quelle, SwiftData nur noch solange als isolierte Alt-/Bridge-Schicht, bis es komplett entfernt werden kann.

**Architecture:** Feedivo bleibt optisch und in der SwiftUI-Oberfläche Feedivo, aber die fachliche Datenhaltung wird NetNewsWire-artig: Stores/Facades sprechen mit SQLite, Views sprechen mit Snapshots/States, Status- und Seen-Daten bleiben von Artikelinhalt getrennt. Bestehende SQLite-Stores werden fertiggezogen; SwiftData-Modelle werden nicht in einem großen Schnitt gelöscht, sondern pro Slice aus produktiven Pfaden entfernt.

**Tech Stack:** Swift 6, SwiftUI, GRDB/SQLite, Swift Testing, bestehende `FeedivoDatabaseMigrator`, bestehende Stores (`ArticleStore`, `FeedStore`, `TagStore`, `SQLiteRuleStore`, `SQLiteSmartFolderStore`, `TimelineStore`).

---

## Zielbild nach NetNewsWire-Vorbild

Produktive Datenquellen:

- `feeds`, `feed_folders`, `feed_logs`
- `articles`, `article_statuses`, `article_identity_history`
- `article_search` FTS
- `tags`, `article_tags`, `feed_tags`
- `rules`, `rule_conditions`
- `smart_folders`, `smart_folder_conditions`
- `article_offline`

Produktive API-Grenzen:

- `ArticleDatabase` für Artikel, Status, Timeline, Suche, Reader, Counts
- `FeedStore`/später optional `FeedDatabase` für Feedverwaltung, Sidebar-Snapshots, Refresh-Metadaten
- `TagStore` für Tags und Tag-Zuordnungen
- `SQLiteRuleStore` und `SQLiteRuleEvaluationStore` für Regeln
- `SQLiteSmartFolderStore` und `TimelineStore` für intelligente Ordner
- `SQLiteFeedRefreshService` und ein kleiner Refresh-Koordinator für Refresh-All

Nicht-Ziele:

- Keine UI-Umgestaltung.
- Kein Sync-/Account-System wie NetNewsWire als Feature.
- Kein sofortiger `NSTableView`-Umbau ohne Messwerte.
- UserDefaults/AppStorage für kleine UI-Settings dürfen bleiben.

---

## Phase 1: SwiftData-Nutzung kartieren und gegen Rückfälle absichern

**Files:**
- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`
- Create: `docs/performance/sqlite-only-audit.md`

- [x] **Step 1: Audit-Dokument anlegen**

Erstelle `docs/performance/sqlite-only-audit.md` mit diesen Rubriken:

```markdown
# SQLite-only Audit

Stand: 2026-07-03

## Produktiver SQLite-Pfad

- Sidebar/ContentView: SQLite-Snapshots
- Artikelliste: SQLiteFeedArticleListView
- Reader: SQLiteReaderView
- Feed add/import/refresh: SQLiteFeedSubscriptionService/SQLiteFeedRefreshService
- Tags/Rules/SmartFolders: SQLite-Stores vorhanden, SwiftData-Reste separat prüfen

## Erlaubte SwiftData-Reste während der Migration

- Bridge-Write für `Feed`, solange Legacy-Relationships `Article.feed` und `Tag.feeds` existieren.
- Backfills von alten SwiftData-Daten nach SQLite.
- Legacy-Views, solange nicht aus produktiver Navigation erreichbar.

## Nicht mehr erlaubte neue SwiftData-Abhängigkeiten

- keine neuen `@Query [Feed]`
- keine neue produktive Artikelliste über `@Query Article`
- keine neuen Feed-Refreshes, die SwiftData-Artikel schreiben
- keine neuen Tag-/Rule-/SmartFolder-Verwaltungen, die SwiftData als Quelle nutzen
```

- [x] **Step 2: Regressionstest für produktive Navigation ergänzen**

In `FeedivoTests/FeedivoAppSceneConfigurationTests.swift` ergänzen:

```swift
@Test func produktiveFeedArtikelNavigationBleibtSQLiteOnly() throws {
    let projectRoot = try Self.projectRoot()
    let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)
    let compactContent = contentSource.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

    #expect(!contentSource.contains("@Query(sort: \\Feed.title)"))
    #expect(compactContent.contains("@StateprivatevarfeedSnapshots:[FeedSidebarSnapshot]=[]"))
    #expect(compactContent.contains("FeedStore(database:database).sidebarFeeds()"))
    #expect(compactContent.contains("SQLiteFeedArticleListView(feedID:feedID"))
    #expect(compactContent.contains("SQLiteReaderView("))
}
```

- [x] **Step 3: Test ausführen**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests
```

Expected: PASS.

- [x] **Step 4: Commit**

```bash
git add FeedivoTests/FeedivoAppSceneConfigurationTests.swift docs/performance/sqlite-only-audit.md
git commit -m "Dokumentiere SQLite-only Zielstruktur"
```

---

## Phase 2: Tags vollständig SQLite-only machen

**Files:**
- Modify: `Feedivo/Views/ArticleList/ArticleSearchWindowView.swift`
- Modify: `Feedivo/Views/Reader/ArticleMetadataInspectorView.swift`
- Modify: `Feedivo/Views/Reader/SQLiteReaderView.swift`
- Modify: `Feedivo/ViewModels/TagViewModel.swift`
- Test: `FeedivoTests/SQLiteTagStoreTests.swift`
- Test: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

Ziel: Keine produktive View lädt Tags mehr per SwiftData-`@Query`.

- [x] **Step 1: Failing Source-Test für Tag-Queries schreiben**

In `FeedivoTests/FeedivoAppSceneConfigurationTests.swift` ergänzen:

```swift
@Test func produktiveTagOberflaechenNutzenSQLiteTagStore() throws {
    let projectRoot = try Self.projectRoot()
    let searchSource = try source(at: "Feedivo/Views/ArticleList/ArticleSearchWindowView.swift", projectRoot: projectRoot)
    let inspectorSource = try source(at: "Feedivo/Views/Reader/ArticleMetadataInspectorView.swift", projectRoot: projectRoot)
    let sqliteReaderSource = try source(at: "Feedivo/Views/Reader/SQLiteReaderView.swift", projectRoot: projectRoot)

    #expect(!searchSource.contains("@Query(sort: \\Tag.name)"))
    #expect(searchSource.contains("TagStore(database: database).tags()"))
    #expect(!inspectorSource.contains("@Query(sort: \\Tag.name)"))
    #expect(inspectorSource.contains("TagStore(database: database).tags()"))
    #expect(sqliteReaderSource.contains("TagStore(database: database)"))
}
```

- [x] **Step 2: `ArticleSearchWindowView` auf SQLite-Tags umstellen**

Ersetze den SwiftData-Tag-Query-State durch:

```swift
@State private var tags: [TagRecord] = []
```

und lade Tags zusammen mit Feeds:

```swift
private func loadTags() {
    guard let database else {
        tags = []
        return
    }
    tags = (try? TagStore(database: database).tags()) ?? []
}
```

Im `.task(id: sqliteStatusVersion)`:

```swift
.task(id: sqliteStatusVersion) {
    loadFeeds()
    loadTags()
}
```

Der Picker soll `UUID(uuidString: tag.id)` taggen, bis `ArticleSearchWindowState` auf String-IDs umgestellt wird:

```swift
ForEach(tags) { tag in
    Text(tag.name).tag(UUID(uuidString: tag.id))
}
```

- [x] **Step 3: Inspector-Tags auf `TagStore` umstellen**

`ArticleMetadataInspectorView` soll für den SQLite-Reader keine `@Query Tag` mehr brauchen. Lade `TagRecord`s über `TagStore` und mappe UI-Aktionen auf SQLite-Zuordnungen. Falls Legacy-`Article`-Inspector noch gebraucht wird, trenne ihn in einen deutlich benannten Legacy-Typ, z.B. `LegacyArticleMetadataInspectorView`.

- [x] **Step 4: Alte `TagViewModel`-SwiftData-Pfade isolieren**

Benennen oder markieren:

```swift
// Legacy SwiftData: nur noch für alte Tests/Views. Produktive Tag-Verwaltung nutzt TagStore.
```

Neue produktive Tag-Aktionen gehen direkt über `TagStore`.

- [x] **Step 5: Tests ausführen**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteTagStoreTests -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests
```

Expected: PASS.

- [x] **Step 6: Commit**

```bash
git add Feedivo/Views/ArticleList/ArticleSearchWindowView.swift Feedivo/Views/Reader/ArticleMetadataInspectorView.swift Feedivo/Views/Reader/SQLiteReaderView.swift Feedivo/ViewModels/TagViewModel.swift FeedivoTests
git commit -m "Migriere produktive Tag-Pfade auf SQLite"
```

---

## Phase 3: Rules SQLite-only machen

**Files:**
- Modify: `Feedivo/Views/Rules/RuleSettingsView.swift`
- Modify: `Feedivo/Views/Rules/RuleWizardView.swift`
- Modify: `Feedivo/ViewModels/RuleViewModel.swift`
- Modify: `Feedivo/ViewModels/FeedViewModel.swift`
- Test: `FeedivoTests/SQLiteRuleEvaluationStoreTests.swift`
- Test: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

Ziel: Regeln werden produktiv aus `SQLiteRuleStore` gelesen und geschrieben. `Rule`/`RuleCondition` bleiben nur noch Migrations-/Legacy-Modelle.

- [x] **Step 1: Failing Source-Test schreiben**

```swift
@Test func regelVerwaltungIstSQLiteOnly() throws {
    let projectRoot = try Self.projectRoot()
    let settingsSource = try source(at: "Feedivo/Views/Rules/RuleSettingsView.swift", projectRoot: projectRoot)
    let wizardSource = try source(at: "Feedivo/Views/Rules/RuleWizardView.swift", projectRoot: projectRoot)
    let viewModelSource = try source(at: "Feedivo/ViewModels/RuleViewModel.swift", projectRoot: projectRoot)

    #expect(settingsSource.contains("SQLiteRuleStore(database: database)"))
    #expect(wizardSource.contains("SQLiteRuleStore(database: database)"))
    #expect(!settingsSource.contains("@Query"))
    #expect(!wizardSource.contains("@Query"))
    #expect(viewModelSource.contains("Legacy SwiftData"))
}
```

- [x] **Step 2: `SQLiteRuleStore` als Schreibquelle verwenden**

Alle Erstellen/Bearbeiten/Duplizieren/Löschen-Aktionen in Settings/Wizard sollen `SQLiteRuleStore` verwenden. Falls Store-Methoden fehlen, ergänzen:

```swift
func save(_ rule: RuleRecord, conditions: [RuleConditionRecord]) throws
func delete(id: String) throws
func duplicate(id: String, newName: String) throws -> String
func reorder(ids: [String]) throws
```

- [x] **Step 3: Refresh-Regeln aus SQLite lesen**

In `FeedViewModel.refreshFeed(feedID:context:sqliteDatabase:)` und `refreshAllFeeds(sqliteDatabase:modelContainer:)` sollen Rule-Snapshots aus `SQLiteRuleStore` kommen:

```swift
let rules = (try? SQLiteRuleStore(database: sqliteDatabase).ruleSnapshots()) ?? []
```

SwiftData-`Rule`-Fetches bleiben nur im Legacy-Refresh ohne SQLite-Datenbank.

- [x] **Step 4: Tests ausführen**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteRuleEvaluationStoreTests -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests -only-testing:FeedivoTests/SQLiteFeedRefreshServiceTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add Feedivo/Views/Rules Feedivo/ViewModels/RuleViewModel.swift Feedivo/ViewModels/FeedViewModel.swift Feedivo/Stores FeedivoTests
git commit -m "Migriere Regeln auf SQLite"
```

---

## Phase 4: SmartFolders und FeedFolders SQLite-only finalisieren

**Files:**
- Modify: `Feedivo/Views/SmartFolders/SmartFolderSettingsView.swift`
- Modify: `Feedivo/Views/SmartFolders/SmartFolderEditorView.swift`
- Modify: `Feedivo/ViewModels/SmartFolderViewModel.swift`
- Modify: `Feedivo/Views/Reader/ArticleMetadataInspectorView.swift`
- Test: `FeedivoTests/SQLiteAdminStoreTests.swift`
- Test: `FeedivoTests/SQLiteTimelineStoreTests.swift`

Ziel: Intelligente Ordner und Feed-Ordner sind produktiv nur noch SQLite-Records.

- [x] **Step 1: Source-Test schreiben**

```swift
@Test func smartFolderUndFeedFolderVerwaltungIstSQLiteOnly() throws {
    let projectRoot = try Self.projectRoot()
    let settingsSource = try source(at: "Feedivo/Views/SmartFolders/SmartFolderSettingsView.swift", projectRoot: projectRoot)
    let editorSource = try source(at: "Feedivo/Views/SmartFolders/SmartFolderEditorView.swift", projectRoot: projectRoot)
    let inspectorSource = try source(at: "Feedivo/Views/Reader/ArticleMetadataInspectorView.swift", projectRoot: projectRoot)

    #expect(settingsSource.contains("SQLiteSmartFolderStore(database: database)"))
    #expect(editorSource.contains("SQLiteSmartFolderStore(database: database)"))
    #expect(!settingsSource.contains("@Query"))
    #expect(!editorSource.contains("@Query"))
    #expect(inspectorSource.contains("FeedFolderStore(database: database)"))
}
```

- [x] **Step 2: SmartFolderViewModel als Legacy markieren oder entfernen**

Produktive Views sollen `SQLiteSmartFolderStore` direkt oder über einen neuen kleinen State verwenden:

```swift
@Observable
final class SQLiteSmartFolderSettingsState {
    var folders: [SQLiteSmartFolderSnapshot] = []

    func load(database: FeedivoDatabase) {
        folders = (try? SQLiteSmartFolderStore(database: database).sidebarSnapshots(includeHidden: true)) ?? []
    }
}
```

- [x] **Step 3: FeedFolder-Picker auf `FeedFolderStore` umstellen**

Keine produktive View soll `@Query(sort: \FeedFolder.name)` verwenden. Lade:

```swift
let folders = (try? FeedFolderStore(database: database).folders()) ?? []
```

- [x] **Step 4: Tests ausführen**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteAdminStoreTests -only-testing:FeedivoTests/SQLiteTimelineStoreTests -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add Feedivo/Views/SmartFolders Feedivo/ViewModels/SmartFolderViewModel.swift Feedivo/Views/Reader/ArticleMetadataInspectorView.swift FeedivoTests
git commit -m "Migriere Smart Folders und Feed-Ordner auf SQLite"
```

---

## Phase 5: Legacy Article/Reader-Pfade entfernen oder hart isolieren

**Files:**
- Modify or delete: `Feedivo/Views/ArticleList/ArticleListView.swift`
- Modify or delete: `Feedivo/Views/ArticleList/ArticleListQuery.swift`
- Modify or delete: `Feedivo/Views/Reader/ReaderView.swift`
- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

Ziel: Es gibt keine versehentliche produktive Route mehr zu SwiftData-Artikelviews.

- [x] **Step 1: Source-Test gegen Legacy-Routing schreiben**

```swift
@Test func produktiverBuildRoutetNichtMehrInSwiftDataArtikelViews() throws {
    let projectRoot = try Self.projectRoot()
    let contentSource = try source(at: "Feedivo/Views/ContentView.swift", projectRoot: projectRoot)
    let appSource = try source(at: "Feedivo/App/FeedivoApp.swift", projectRoot: projectRoot)

    #expect(!contentSource.contains("ArticleListView("))
    #expect(!contentSource.contains("ReaderView("))
    #expect(appSource.contains("SQLiteReaderView") || contentSource.contains("SQLiteReaderView("))
}
```

- [x] **Step 2: Legacy-Dateien umbenennen oder mit Build-Flag isolieren**

Bevorzugt löschen, wenn keine Tests/Views sie brauchen. Falls noch nötig:

```swift
// Legacy SwiftData: nicht im produktiven Navigationspfad verwenden.
```

und Dateinamen klar machen:

- `LegacyArticleListView.swift`
- `LegacyReaderView.swift`
- `LegacyArticleListQuery.swift`

- [x] **Step 3: Tests ausführen**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests -only-testing:FeedivoTests/SQLiteReaderStateTests
```

Expected: PASS.

- [x] **Step 4: Commit**

```bash
git add Feedivo/Views/ArticleList Feedivo/Views/Reader FeedivoTests/FeedivoAppSceneConfigurationTests.swift
git commit -m "Isoliere SwiftData Artikel-Legacy-Views"
```

---

## Phase 6: FeedViewModel in NetNewsWire-artige Services schneiden

**Files:**
- Create: `Feedivo/Services/SQLiteFeedRefreshCoordinator.swift`
- Modify: `Feedivo/ViewModels/FeedViewModel.swift`
- Modify: `Feedivo/Services/BackgroundRefreshService.swift`
- Modify: `Feedivo/Services/FeedBackgroundRefreshService.swift`
- Test: `FeedivoTests/SQLiteFeedRefreshServiceTests.swift`
- Test: `FeedivoTests/FeedViewModelTests.swift`

Ziel: `FeedViewModel` ist nicht mehr Mischort für alte SwiftData- und neue SQLite-Logik.

- [x] **Step 1: Coordinator-Test schreiben**

```swift
@Test func sqliteRefreshCoordinatorLaedtFeedsAusSQLiteUndRefreshtJedenFeed() async throws {
    let database = try makeTemporaryFeedivoDatabase()
    try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/1.xml", title: "Feed 1"))

    let coordinator = SQLiteFeedRefreshCoordinator(
        database: database,
        refreshServiceFactory: { database, _ in
            SQLiteFeedRefreshService(database: database) { _, _ in
                .updated(ParsedFeed(title: "Feed 1", sourceURL: "https://example.com/1.xml", articles: []), FeedHTTPValidators())
            }
        }
    )

    let summary = await coordinator.refreshAllFeeds(ruleSnapshots: [])
    #expect(summary.totalFeedCount == 1)
    #expect(summary.failedFeedCount == 0)
}
```

- [x] **Step 2: Coordinator einführen**

`SQLiteFeedRefreshCoordinator` kapselt:

- Feed-Snapshots aus `FeedStore.refreshSnapshots()`
- Parallelisierung mit `FeedViewModel.maxConcurrentFeedRefreshes`
- `SQLiteFeedRefreshService.refresh(feedID:)`
- Fortschrittsitems
- Benachrichtigungsergebnisse

- [x] **Step 3: FeedViewModel verschlanken**

`FeedViewModel.refreshAllFeeds(sqliteDatabase:modelContainer:)` delegiert an den Coordinator und enthält nur noch UI-State:

```swift
let coordinator = SQLiteFeedRefreshCoordinator(database: sqliteDatabase)
let summary = await coordinator.refreshAllFeeds(ruleSnapshots: rules)
recentRefreshStatus = summary.statusSummary
```

- [x] **Step 4: Legacy-Refresh deutlich markieren**

Alte SwiftData-Refresh-Methoden in `FeedViewModel` bekommen:

```swift
// Legacy SwiftData Refresh: nur Fallback, nicht produktiver SQLite-Pfad.
```

- [x] **Step 5: Tests ausführen**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedRefreshServiceTests -only-testing:FeedivoTests/FeedViewModelTests -only-testing:FeedivoTests/BackgroundRefreshServiceTests
```

Expected: PASS.

- [x] **Step 6: Commit**

```bash
git add Feedivo/Services/SQLiteFeedRefreshCoordinator.swift Feedivo/ViewModels/FeedViewModel.swift Feedivo/Services/BackgroundRefreshService.swift Feedivo/Services/FeedBackgroundRefreshService.swift FeedivoTests
git commit -m "Extrahiere SQLite Refresh Coordinator"
```

---

## Phase 7: SwiftData-Backfills abschließen und Legacy-Brücke abschaltbar machen

**Files:**
- Modify: `Feedivo/Services/SQLiteFeedSubscriptionService.swift`
- Modify: `Feedivo/App/FeedivoApp.swift`
- Modify: `Feedivo/App/FeedivoModelContainerFactory.swift`
- Test: `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift`
- Test: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

Ziel: SwiftData-Bridge ist nicht mehr selbstverständlich, sondern explizit alte Migration.

- [x] **Step 1: Feature-Flag für Bridge einführen**

In einem kleinen enum:

```swift
enum SwiftDataBridgeSettings {
    static let isEnabledKey = "swiftDataBridge.isEnabled"
    static let defaultIsEnabled = true
}
```

- [x] **Step 2: Subscription-Bridge nur noch unter Flag schreiben**

In `SQLiteFeedSubscriptionService.saveSwiftDataBridge` vor dem Fetch:

```swift
guard UserDefaults.standard.object(forKey: SwiftDataBridgeSettings.isEnabledKey) as? Bool ?? SwiftDataBridgeSettings.defaultIsEnabled else {
    return
}
```

- [x] **Step 3: Tests für abschaltbare Bridge schreiben**

```swift
@Test func addFeedKannOhneSwiftDataBridgeLaufen() async throws {
    let defaults = UserDefaults.standard
    defaults.set(false, forKey: SwiftDataBridgeSettings.isEnabledKey)
    defer { defaults.removeObject(forKey: SwiftDataBridgeSettings.isEnabledKey) }

    let database = try makeTemporaryFeedivoDatabase()
    let container = try makeInMemoryModelContainer()
    let context = ModelContext(container)
    let service = SQLiteFeedSubscriptionService(database: database, fetchFeed: stubFeedFetcher)

    let result = try await service.addFeed(urlString: "https://example.com/feed.xml", context: context)
    #expect(try FeedStore(database: database).feed(id: result.feedID) != nil)
    #expect((try context.fetch(FetchDescriptor<Feed>())).isEmpty)
}
```

- [x] **Step 4: Tests ausführen**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add Feedivo/Services/SQLiteFeedSubscriptionService.swift Feedivo/App FeedivoTests
git commit -m "Mache SwiftData Bridge abschaltbar"
```

---

## Phase 8: SwiftData-Container entfernen, wenn keine produktiven Abhängigkeiten bleiben

**Files:**
- Modify: `Feedivo/App/FeedivoApp.swift`
- Modify: `Feedivo/App/FeedivoModelContainerFactory.swift`
- Delete: unused SwiftData model files if no longer referenced
- Modify: `Feedivo.xcodeproj/project.pbxproj`
- Test: whole test suite

Ziel: Feedivo startet ohne SwiftData-`ModelContainer`, sobald alle produktiven und Bridge-Pfade SQLite-only sind.

- [x] **Step 1: Blocker-Scan ausführen**

Run:

```bash
rg -n 'import SwiftData|@Model|@Query|ModelContext|ModelContainer|FetchDescriptor<' Feedivo -g '*.swift'
```

Expected: Nur explizit archivierte Legacy-Dateien oder gar keine Treffer. Wenn produktive Treffer bleiben, Phase 8 stoppen und diese Treffer als eigene Phase behandeln.

- [x] **Step 2: App-Start auf SQLite-only umstellen**

`FeedivoApp` soll nur noch `FeedivoDatabase` öffnen und per Environment injizieren:

```swift
private let feedivoDatabase: FeedivoDatabase
```

Entfernen:

- `private let modelContainer: ModelContainer`
- `.modelContainer(modelContainer)`
- `FeedivoModelContainerFactory`
- SwiftData-Fallback-Alert, sofern nur SwiftData betrifft

- [ ] **Step 3: Tests ausführen** *(ausgeführt, aber bestehende Legacy-FeedViewModel-/Performance-Tests sind außerhalb des Produktpfads noch fehlerhaft – siehe unten)*

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
```

Expected: PASS.

- [ ] **Step 4: App bauen**

Run:

```bash
xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
```

Expected: BUILD SUCCEEDED.

- [x] **Step 5: Commit**

```bash
git add Feedivo FeedivoTests Feedivo.xcodeproj/project.pbxproj
git commit -m "Entferne SwiftData Container"
```

---

## Phase 9: Performance-Verifikation wie NetNewsWire

**Files:**
- Create: `FeedivoTests/SQLiteLargeDatasetPerformanceTests.swift`
- Modify: `FeedivoTests/SQLitePerformanceSmokeTests.swift`

Ziel: Bevor AppKit/NSTableView diskutiert wird, messen wir den SwiftUI-Snapshot-Pfad mit großen SQLite-Daten.

- [x] **Step 1: Testdaten-Helper schreiben**

```swift
func seedLargeSQLiteDataset(
    database: FeedivoDatabase,
    feedCount: Int,
    articlesPerFeed: Int
) throws {
    let feedStore = FeedStore(database: database)
    let articleStore = ArticleStore(database: database)
    for feedIndex in 0..<feedCount {
        let feedID = "feed-\(feedIndex)"
        try feedStore.save(FeedRecord(id: feedID, url: "https://example.com/\(feedIndex).xml", title: "Feed \(feedIndex)"))
        let inputs = (0..<articlesPerFeed).map { articleIndex in
            ArticleUpsertInput(
                feedID: feedID,
                sourceID: "\(feedID)-\(articleIndex)",
                link: "https://example.com/\(feedIndex)/\(articleIndex)",
                title: "Artikel \(feedIndex)-\(articleIndex)",
                summary: "Summary \(articleIndex)",
                publishedAt: Date().addingTimeInterval(TimeInterval(-articleIndex * 60))
            )
        }
        _ = try articleStore.upsert(inputs)
    }
}
```

- [x] **Step 2: Performance-Tests ergänzen**

Messfälle:

- `TimelineStore.articles(scope: .all, limit: 500)`
- `TimelineStore.articles(scope: .feed(feedID), limit: 500)`
- FTS-Suche mit Trefferlimit
- `ArticleStatusStore.setRead` plus Timeline-Reload
- Sidebar-Snapshots mit Counts

- [x] **Step 3: Tests ausführen**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteLargeDatasetPerformanceTests
```

Expected: PASS. Zeiten dokumentieren in `docs/performance/sqlite-large-dataset-results.md`.

- [x] **Step 4: Entscheidung dokumentieren**

Wenn SwiftUI-Snapshot-Liste schnell genug ist, `NSTableView` weiterhin zurückstellen. Wenn nicht, separaten Plan für AppKit-Timeline schreiben.

- [x] **Step 5: Commit**

```bash
git add FeedivoTests/SQLiteLargeDatasetPerformanceTests.swift docs/performance/sqlite-large-dataset-results.md
git commit -m "Ergänze SQLite Lasttests"
```

---

## Empfohlene Reihenfolge

1. Phase 1: Audit/Regression-Schutz.
2. Phase 2: Tags SQLite-only.
3. Phase 3: Rules SQLite-only.
4. Phase 4: SmartFolders/FeedFolders SQLite-only.
5. Phase 5: Legacy Article/Reader isolieren.
6. Phase 6: FeedViewModel/Refresh-Koordinator.
7. Phase 7: SwiftData-Bridge abschaltbar.
8. Phase 9: Performance-Verifikation.
9. Phase 8: SwiftData-Container entfernen.

Phase 8 absichtlich nach den Lasttests: Solange noch unerwartete Legacy-Abhängigkeiten auftauchen, ist ein abschaltbarer Bridge-Modus sicherer als ein harter Abriss.

---

## Definition of Done

- Produktive Feed-/Artikel-/Tag-/Rule-/SmartFolder-Pfade lesen und schreiben ausschließlich SQLite.
- `rg -n 'import SwiftData|@Model|@Query|ModelContext|ModelContainer|FetchDescriptor<' Feedivo -g '*.swift'` zeigt keine produktiven Treffer mehr.
- `FeedivoApp` startet ohne SwiftData-`ModelContainer`.
- Alle Tests laufen grün.
- `docs/performance/netnewswire-feedivo-mechanik-vergleich.md` ist aktualisiert.
- `docs/performance/sqlite-only-audit.md` zeigt keine offenen produktiven SwiftData-Abhängigkeiten.
