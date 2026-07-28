# SQLite Feed Subscription Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Feed hinzufügen, OPML-Import und First-Run-Wizard legen neue Feeds SQLite-first an und behalten nur eine minimale SwiftData-Feed-Zeile als Übergangsidentität.

**Architecture:** Ein neuer `SQLiteFeedSubscriptionService` kapselt Feed-Anlage, OPML-Batch-Import, SQLite-Duplikatprüfung, Ordner-/Tag-Persistenz, optionalen Erst-Refresh und SwiftData-Bridge. `FeedViewModel` delegiert seine bestehenden Add-/Import-Methoden an diesen Service, wenn eine SQLite-Datenbank vorhanden ist; ohne SQLite bleibt der aktuelle Legacy-Pfad nur als Fallback für Tests und Übergang erhalten.

**Tech Stack:** Swift 6, SwiftData, GRDB, Swift Testing, bestehende Feedivo Stores (`FeedStore`, `FeedFolderStore`, `TagStore`, `FeedLogStore`, `SQLiteFeedRefreshService`).

---

## File Structure

- Create: `Feedivo/Services/SQLiteFeedSubscriptionService.swift`
  - Ergebnis- und Fehler-Typen für SQLite-first Feed-Anlage und OPML-Import.
  - Speichert `FeedRecord`, Ordner und Feed-Tags in SQLite.
  - Legt minimale SwiftData-`Feed`-Bridge-Zeilen mit derselben ID an.
  - Startet optional `SQLiteFeedRefreshService`.
- Create: `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift`
  - Isolierte Tests für Einzel-Feed, Duplikate, OPML-Ordner, OPML-Tags und Refresh-Teilfehler.
- Modify: `Feedivo/ViewModels/FeedViewModel.swift`
  - `addFeed(... sqliteDatabase:)` nutzt SQLite-first Service.
  - `importOPMLFeeds(... sqliteDatabase:)` nutzt SQLite-first Service.
  - `opmlImportPreviewRows` erhält optional SQLite-Existing-URLs oder eine neue SQLite-spezifische Hilfsmethode.
- Modify: `Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift`
  - Preview-Methoden nehmen optional `FeedivoDatabase` an und prüfen Duplikate gegen SQLite.
- Modify: `Feedivo/Views/OPMLImport/OPMLImportReviewView.swift`
  - Übergibt `feedivoDatabase` an den PreviewController.
- Modify: `Feedivo/Views/FirstRun/FirstRunWizardView.swift`
  - Übergibt `feedivoDatabase` an Einzel-Feed- und OPML-Preview.
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift`
  - `AddFeedSheet` bleibt optisch gleich; nach erfolgreichem SQLite-first Add bleibt der bestehende Dismiss-Pfad.
- Modify: `FeedivoTests/FeedViewModelTests.swift`
  - Alte Spiegel-Tests werden auf SQLite-first Verhalten angepasst: SwiftData enthält Feed-Bridge, Artikel liegen in SQLite.
- Modify: `FeedivoTests/OPMLImportPreviewControllerTests.swift`
  - Preview-Duplikate über SQLite ergänzen.
- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`
  - Charakterisierung aktualisieren: Add/Import/FirstRun reichen SQLite-Datenbank an Preview und Mutator weiter.
- Modify: `AGENTS.md`, `FEATURES.md`
  - Status dokumentieren: Feed hinzufügen, OPML-Import und First-Run-Wizard sind SQLite-first mit temporärer SwiftData-Feed-Bridge.

## Task 1: Service API testgetrieben einführen

**Files:**
- Create: `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift`
- Create: `Feedivo/Services/SQLiteFeedSubscriptionService.swift`

- [ ] **Step 1: Write the failing test**

Add this first test file:

```swift
import Foundation
import SwiftData
import Testing
@testable import Feedivo

@Suite(.serialized)
struct SQLiteFeedSubscriptionServiceTests {
    @MainActor
    @Test func addFeedSpeichertSQLiteFeedUndSwiftDataBridgeOhneSwiftDataArtikel() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            RuleCondition.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { url in
                ParsedFeed(
                    sourceURL: url,
                    title: "Example Feed",
                    description: "Beschreibung",
                    siteURL: "https://example.com",
                    articles: [
                        ParsedArticle(
                            title: "Erster Artikel",
                            sourceID: "artikel-1",
                            link: "https://example.com/1",
                            summary: "Kurz",
                            content: "Lang",
                            publishedAt: Date(timeIntervalSince1970: 100),
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in "https://example.com/favicon.ico" }
        )

        let result = try await service.addFeed(
            urlString: "https://example.com/feed.xml",
            refreshIntervalMinutes: 60,
            context: context
        )

        let sqliteFeed = try #require(try FeedStore(database: database).feed(id: result.feedID))
        let swiftDataFeeds = try context.fetch(FetchDescriptor<Feed>())
        let swiftDataArticles = try context.fetch(FetchDescriptor<Article>())
        let timelineRows = try TimelineStore(database: database).articles(
            scope: .feed(result.feedID),
            includeRead: true,
            includeHidden: false,
            limit: 10
        )

        #expect(sqliteFeed.title == "Example Feed")
        #expect(sqliteFeed.url == "https://example.com/feed.xml")
        #expect(sqliteFeed.websiteURL == "https://example.com")
        #expect(sqliteFeed.faviconURL == "https://example.com/favicon.ico")
        #expect(sqliteFeed.refreshIntervalMinutes == 60)
        #expect(timelineRows.map(\.title) == ["Erster Artikel"])
        #expect(swiftDataFeeds.count == 1)
        #expect(swiftDataFeeds[0].id.uuidString == result.feedID)
        #expect(swiftDataFeeds[0].title == "Example Feed")
        #expect(swiftDataArticles.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests/addFeedSpeichertSQLiteFeedUndSwiftDataBridgeOhneSwiftDataArtikel
```

Expected: FAIL because `SQLiteFeedSubscriptionService` is not defined.

- [ ] **Step 3: Implement the minimal service**

Create `Feedivo/Services/SQLiteFeedSubscriptionService.swift`:

```swift
import Foundation
import SwiftData

struct SQLiteFeedSubscriptionResult: Equatable, Sendable {
    var feedID: String
    var importedCount: Int
    var skippedDuplicateCount: Int
    var failedFeedTitles: [String]
}

enum SQLiteFeedSubscriptionError: LocalizedError, Equatable {
    case emptyURL
    case duplicateFeed

    var errorDescription: String? {
        switch self {
        case .emptyURL:
            L10n.feedErrorEmptyURL
        case .duplicateFeed:
            L10n.feedErrorDuplicate
        }
    }
}

@MainActor
struct SQLiteFeedSubscriptionService {
    typealias FeedFetcher = (String) async throws -> ParsedFeed
    typealias FaviconFetcher = (URL) async -> String?

    private let database: FeedivoDatabase
    private let fetchFeed: FeedFetcher
    private let discoverFaviconURL: FaviconFetcher

    init(
        database: FeedivoDatabase,
        fetchFeed: @escaping FeedFetcher = FeedService.fetchFeed,
        discoverFaviconURL: @escaping FaviconFetcher = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        }
    ) {
        self.database = database
        self.fetchFeed = fetchFeed
        self.discoverFaviconURL = discoverFaviconURL
    }

    func addFeed(
        urlString: String,
        refreshIntervalMinutes: Int = BackgroundRefreshSettings.defaultIntervalMinutes,
        context: ModelContext
    ) async throws -> SQLiteFeedSubscriptionResult {
        let cleanedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedURL.isEmpty else {
            throw SQLiteFeedSubscriptionError.emptyURL
        }

        let parsedFeed = try await fetchFeed(cleanedURL)
        let normalizedURL = FeedViewModel.normalizedFeedURL(parsedFeed.sourceURL)
        let feedStore = FeedStore(database: database)
        let existingFeeds = try feedStore.feeds()
        guard !existingFeeds.contains(where: { FeedViewModel.normalizedFeedURL($0.url) == normalizedURL }) else {
            throw SQLiteFeedSubscriptionError.duplicateFeed
        }

        let now = Date()
        let feedID = UUID().uuidString
        let faviconURL = await faviconURL(for: parsedFeed)
        let feedRecord = FeedRecord(
            id: feedID,
            url: parsedFeed.sourceURL,
            title: parsedFeed.title,
            originalTitle: parsedFeed.title,
            websiteURL: parsedFeed.siteURL,
            faviconURL: faviconURL,
            refreshIntervalMinutes: BackgroundRefreshSettings.clampedIntervalMinutes(refreshIntervalMinutes),
            createdAt: now,
            updatedAt: now
        )
        try feedStore.save(feedRecord)
        try ArticleStore(database: database).upsert(parsedFeed.articles.map { article in
            ArticleUpsertInput(
                feedID: feedID,
                sourceID: article.sourceID,
                link: article.link,
                title: article.title,
                summary: article.summary,
                content: article.content,
                imageURL: article.imageURL,
                publishedAt: article.publishedAt,
                arrivedAt: now
            )
        })
        let unreadCount = try ArticleStatusStore(database: database).unreadCount(feedID: feedID)
        try feedStore.setUnreadCount(unreadCount, feedID: feedID)
        try FeedLogStore(database: database).append(FeedLogRecord(
            feedID: feedID,
            createdAt: now,
            level: "info",
            message: L10n.feedLogAdded,
            httpStatusCode: nil,
            newArticleCount: parsedFeed.articles.count
        ))
        try saveSwiftDataBridge(feedRecord, context: context)

        return SQLiteFeedSubscriptionResult(
            feedID: feedID,
            importedCount: 1,
            skippedDuplicateCount: 0,
            failedFeedTitles: []
        )
    }

    private func faviconURL(for parsedFeed: ParsedFeed) async -> String? {
        guard let siteURL = parsedFeed.siteURL.flatMap(URL.init(string:)) else {
            return nil
        }
        return await discoverFaviconURL(siteURL)
    }

    private func saveSwiftDataBridge(_ feedRecord: FeedRecord, context: ModelContext) throws {
        let descriptor = FetchDescriptor<Feed>(
            predicate: #Predicate { $0.id.uuidString == feedRecord.id }
        )
        let feed = try context.fetch(descriptor).first ?? Feed(
            id: UUID(uuidString: feedRecord.id) ?? UUID(),
            url: feedRecord.url,
            title: feedRecord.title,
            feedDescription: nil,
            faviconURL: feedRecord.faviconURL,
            siteURL: feedRecord.websiteURL,
            followedAt: feedRecord.createdAt,
            lastRefreshed: feedRecord.lastRefreshedAt,
            folderName: feedRecord.folderName,
            refreshIntervalMinutes: feedRecord.refreshIntervalMinutes
        )
        feed.url = feedRecord.url
        feed.title = feedRecord.title
        feed.originalTitle = feedRecord.originalTitle
        feed.faviconURL = feedRecord.faviconURL
        feed.siteURL = feedRecord.websiteURL
        feed.folderName = feedRecord.folderName
        feed.refreshIntervalMinutes = feedRecord.refreshIntervalMinutes
        feed.unreadCount = feedRecord.unreadCount
        if feed.modelContext == nil {
            context.insert(feed)
        }
        try context.save()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the same `xcodebuild test ... -only-testing:...addFeed...` command.

Expected: PASS.

## Task 2: OPML-Batch-Import mit Ordnern, Tags und Teilfehlern

**Files:**
- Modify: `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift`
- Modify: `Feedivo/Services/SQLiteFeedSubscriptionService.swift`

- [ ] **Step 1: Write failing OPML tests**

Append tests covering OPML import:

```swift
@MainActor
@Test func importOPMLSpeichertOrdnerTagsUndUeberspringtDuplikate() async throws {
    let database = try FeedivoDatabase.inMemoryForTests()
    let container = try ModelContainer(
        for: Feed.self, Article.self, Tag.self, Rule.self, RuleCondition.self, FeedLogEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    try FeedStore(database: database).save(FeedRecord(url: "https://example.com/existing.xml", title: "Schon da"))

    let service = SQLiteFeedSubscriptionService(database: database) { url in
        ParsedFeed(sourceURL: url, title: "Parsed \(url)", description: nil, siteURL: nil, articles: [])
    } discoverFaviconURL: { _ in nil }

    let result = try await service.importOPMLFeeds(
        [
            OPMLFeed(title: "Neu", xmlURL: "https://example.com/new.xml", htmlURL: "https://example.com", folderName: "News", tagNames: ["Swift", "Mac"]),
            OPMLFeed(title: "Duplikat", xmlURL: "https://example.com/existing.xml", htmlURL: nil, folderName: "News", tagNames: ["Swift"])
        ],
        allowsDuplicates: false,
        refreshAfterImport: false,
        refreshIntervalMinutes: 120,
        context: context
    )

    let feeds = try FeedStore(database: database).feeds()
    let folders = try FeedFolderStore(database: database).folders()
    let tags = try TagStore(database: database).tags()
    let bridgeFeeds = try context.fetch(FetchDescriptor<Feed>())

    #expect(result.imported == 1)
    #expect(result.skippedDuplicates == 1)
    #expect(feeds.contains { $0.url == "https://example.com/new.xml" })
    #expect(folders.map(\.name) == ["News"])
    #expect(tags.map(\.name).sorted() == ["Mac", "Swift"])
    #expect(bridgeFeeds.count == 1)
    #expect(bridgeFeeds[0].refreshIntervalMinutes == 120)
}

@MainActor
@Test func importOPMLMeldetRefreshFehlerAlsTeilproblem() async throws {
    let database = try FeedivoDatabase.inMemoryForTests()
    let container = try ModelContainer(
        for: Feed.self, Article.self, Tag.self, Rule.self, RuleCondition.self, FeedLogEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)

    let service = SQLiteFeedSubscriptionService(database: database) { _ in
        throw FeedServiceError.httpError(500)
    } discoverFaviconURL: { _ in nil }

    let result = try await service.importOPMLFeeds(
        [OPMLFeed(title: "Kaputt", xmlURL: "https://example.com/broken.xml", htmlURL: nil, folderName: nil)],
        allowsDuplicates: false,
        refreshAfterImport: true,
        refreshIntervalMinutes: 60,
        context: context
    )

    let feeds = try FeedStore(database: database).feeds()
    let logs = try FeedLogStore(database: database).logs(feedID: feeds[0].id, limit: 5)

    #expect(result.imported == 1)
    #expect(result.failedFeedTitles == ["Kaputt"])
    #expect(feeds.map(\.url) == ["https://example.com/broken.xml"])
    #expect(logs.first?.level == "error")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests
```

Expected: FAIL because `importOPMLFeeds` and OPML result fields are not implemented.

- [ ] **Step 3: Implement OPML import**

Extend the service with:

```swift
struct SQLiteOPMLImportResult: Equatable, Sendable {
    var total: Int
    var imported: Int
    var skippedDuplicates: Int
    var failedFeedTitles: [String]
}

extension SQLiteFeedSubscriptionService {
    func importOPMLFeeds(
        _ opmlFeeds: [OPMLFeed],
        allowsDuplicates: Bool,
        refreshAfterImport: Bool,
        refreshIntervalMinutes: Int,
        context: ModelContext
    ) async throws -> SQLiteOPMLImportResult {
        var knownURLs = Set(try FeedStore(database: database).feeds().map { FeedViewModel.normalizedFeedURL($0.url) })
        var imported = 0
        var skippedDuplicates = 0
        var failedFeedTitles: [String] = []

        for opmlFeed in opmlFeeds {
            let cleanedURL = opmlFeed.xmlURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedURL.isEmpty else { continue }
            let normalizedURL = FeedViewModel.normalizedFeedURL(cleanedURL)
            guard allowsDuplicates || knownURLs.insert(normalizedURL).inserted else {
                skippedDuplicates += 1
                continue
            }

            let now = Date()
            let feedID = UUID().uuidString
            let folderName = FeedFolderOrganizer.normalizedFolderName(opmlFeed.folderName)
            if let folderName {
                try FeedFolderStore(database: database).save(FeedFolderRecord(name: folderName))
            }

            let feedRecord = FeedRecord(
                id: feedID,
                url: cleanedURL,
                title: opmlFeed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cleanedURL : opmlFeed.title,
                originalTitle: opmlFeed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cleanedURL : opmlFeed.title,
                websiteURL: opmlFeed.htmlURL,
                folderName: folderName,
                refreshIntervalMinutes: BackgroundRefreshSettings.clampedIntervalMinutes(refreshIntervalMinutes),
                createdAt: now,
                updatedAt: now
            )
            try FeedStore(database: database).save(feedRecord)
            try saveTags(opmlFeed.tagNames, feedID: feedID, createdAt: now)
            try FeedLogStore(database: database).append(FeedLogRecord(
                feedID: feedID,
                createdAt: now,
                level: "info",
                message: L10n.feedLogImportedFromOPML,
                httpStatusCode: nil,
                newArticleCount: 0
            ))
            try saveSwiftDataBridge(feedRecord, context: context)
            imported += 1

            if refreshAfterImport {
                do {
                    _ = try await SQLiteFeedRefreshService(database: database) { [fetchFeed] url, _ in
                        .updated(try await fetchFeed(url), FeedHTTPValidators())
                    }.refresh(feedID: feedID)
                } catch {
                    failedFeedTitles.append(feedRecord.title)
                }
            }
        }

        return SQLiteOPMLImportResult(
            total: opmlFeeds.count,
            imported: imported,
            skippedDuplicates: skippedDuplicates,
            failedFeedTitles: failedFeedTitles
        )
    }

    private func saveTags(_ tagNames: [String], feedID: String, createdAt: Date) throws {
        let tagStore = TagStore(database: database)
        for tagName in tagNames.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !tagName.isEmpty {
            let existingTag = try tagStore.tags().first { $0.name.caseInsensitiveCompare(tagName) == .orderedSame }
            let tag = existingTag ?? TagRecord(name: tagName, createdAt: createdAt, updatedAt: createdAt)
            try tagStore.save(tag)
            try tagStore.assignTag(tagID: tag.id, toFeedID: feedID, at: createdAt)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests
```

Expected: PASS.

## Task 3: FeedViewModel auf den Service verdrahten

**Files:**
- Modify: `Feedivo/ViewModels/FeedViewModel.swift`
- Modify: `FeedivoTests/FeedViewModelTests.swift`

- [ ] **Step 1: Write/adjust failing FeedViewModel tests**

Update existing SQLite tests so they expect no SwiftData articles:

```swift
@MainActor
@Test func addFeedMitSQLiteDatabaseLegtArtikelNurInSQLiteAn() async throws {
    let container = try ModelContainer(
        for: Feed.self, Article.self, Tag.self, Rule.self, RuleCondition.self, FeedLogEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let sqliteDatabase = try FeedivoDatabase.inMemoryForTests()
    let viewModel = makeViewModel(
        fetchFeed: { url in
            ParsedFeed(
                sourceURL: url,
                title: "Example",
                description: nil,
                siteURL: nil,
                articles: [ParsedArticle(title: "SQLite Artikel", sourceID: "a1")]
            )
        },
        discoverFaviconURL: { _ in nil },
        enrichArticleImages: { articles in articles }
    )

    await viewModel.addFeed(
        urlString: "https://example.com/feed.xml",
        context: context,
        sqliteDatabase: sqliteDatabase
    )

    let sqliteFeed = try #require(try FeedStore(database: sqliteDatabase).feed(url: "https://example.com/feed.xml"))
    let rows = try TimelineStore(database: sqliteDatabase).articles(
        scope: .feed(sqliteFeed.id),
        includeRead: true,
        includeHidden: false,
        limit: 10
    )

    #expect(viewModel.errorMessage == nil)
    #expect(try context.fetch(FetchDescriptor<Feed>()).count == 1)
    #expect(try context.fetch(FetchDescriptor<Article>()).isEmpty)
    #expect(rows.map(\.title) == ["SQLite Artikel"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedViewModelTests/addFeedMitSQLiteDatabaseLegtArtikelNurInSQLiteAn
```

Expected: FAIL because current `addFeed` still creates SwiftData articles before mirroring.

- [ ] **Step 3: Delegate SQLite path**

At the start of `FeedViewModel.addFeed(urlString:context:sqliteDatabase:)`, after validation and `isLoading` guard, add:

```swift
if let sqliteDatabase {
    do {
        let service = SQLiteFeedSubscriptionService(
            database: sqliteDatabase,
            fetchFeed: fetchFeed,
            discoverFaviconURL: discoverFaviconURL
        )
        _ = try await service.addFeed(
            urlString: cleanedURL,
            refreshIntervalMinutes: BackgroundRefreshSettings.defaultIntervalMinutes,
            context: context
        )
    } catch let error as LocalizedError {
        errorMessage = error.errorDescription ?? L10n.feedErrorAddFailed
    } catch {
        errorMessage = L10n.feedErrorAddFailed
    }
    isLoading = false
    return
}
```

In `importOPMLFeeds`, before the SwiftData creation phase, add the SQLite branch:

```swift
if let sqliteDatabase {
    let service = SQLiteFeedSubscriptionService(
        database: sqliteDatabase,
        fetchFeed: fetchFeed,
        discoverFaviconURL: discoverFaviconURL
    )
    let sqliteResult = try await service.importOPMLFeeds(
        opmlFeeds,
        allowsDuplicates: allowsDuplicates,
        refreshAfterImport: refreshAfterImport,
        refreshIntervalMinutes: refreshIntervalMinutes,
        context: context
    )
    if !sqliteResult.failedFeedTitles.isEmpty {
        errorMessage = L10n.feedErrorRefreshAllPartial(
            sqliteResult.failedFeedTitles.count,
            feedTitles: sqliteResult.failedFeedTitles.joined(separator: ", ")
        )
    }
    return OPMLImportResult(
        total: sqliteResult.total,
        imported: sqliteResult.imported,
        skippedDuplicates: sqliteResult.skippedDuplicates
    )
}
```

- [ ] **Step 4: Run FeedViewModel SQLite tests**

Run:

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedViewModelTests/addFeedMitSQLiteDatabaseLegtArtikelNurInSQLiteAn -only-testing:FeedivoTests/FeedViewModelTests/importOPMLFeedsSpiegeltNeueFeedsNachSQLite
```

Expected: PASS after updating old expectations that assumed SwiftData article import.

## Task 4: OPML preview checks SQLite duplicates

**Files:**
- Modify: `Feedivo/ViewModels/FeedViewModel.swift`
- Modify: `Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift`
- Modify: `Feedivo/Views/OPMLImport/OPMLImportReviewView.swift`
- Modify: `Feedivo/Views/FirstRun/FirstRunWizardView.swift`
- Modify: `FeedivoTests/OPMLImportPreviewControllerTests.swift`

- [ ] **Step 1: Write failing preview test**

Add a controller or view-model test:

```swift
@MainActor
@Test func opmlPreviewMarkiertSQLiteFeedAlsDuplikat() async throws {
    let database = try FeedivoDatabase.inMemoryForTests()
    try FeedStore(database: database).save(
        FeedRecord(url: "https://example.com/existing.xml", title: "Schon da")
    )
    let viewModel = FeedViewModel(fetchFeed: { url in
        ParsedFeed(sourceURL: url, title: "Preview", description: nil, siteURL: nil, articles: [])
    })

    let rows = await viewModel.opmlImportPreviewRows(
        for: [OPMLFeed(title: "Schon da", xmlURL: "https://example.com/existing.xml", htmlURL: nil, folderName: nil)],
        existingFeeds: [],
        sqliteDatabase: database
    )

    #expect(rows.map(\.status) == [.duplicate])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/OPMLImportPreviewControllerTests/opmlPreviewMarkiertSQLiteFeedAlsDuplikat
```

Expected: FAIL because `opmlImportPreviewRows` has no `sqliteDatabase` parameter.

- [ ] **Step 3: Add SQLite duplicate source**

Change `FeedViewModel.opmlImportPreviewRows` signature to:

```swift
func opmlImportPreviewRows(
    for opmlFeeds: [OPMLFeed],
    existingFeeds: [Feed],
    sqliteDatabase: FeedivoDatabase? = nil,
    onProgress: @escaping (OPMLImportPreviewProgress) -> Void = { _ in }
) async -> [OPMLImportPreviewRow]
```

Inside it, build known URLs with:

```swift
let sqliteURLs = (try? sqliteDatabase.map { try FeedStore(database: $0).feeds().map(\.url) }) ?? []
let knownFeedURLs = Set((existingFeeds.map(\.url) + sqliteURLs).map { normalizedFeedURL($0) })
```

Update `OPMLImportPreviewController.loadOPML`, `preparePreview`, and `handleDroppedFiles` to accept `sqliteDatabase: FeedivoDatabase? = nil` and pass it to `feedViewModel.opmlImportPreviewRows`.

Update callers:

```swift
previewController.loadOPML(
    from: result,
    existingFeeds: feeds,
    sqliteDatabase: feedivoDatabase,
    feedViewModel: feedViewModel
)
```

and equivalent FirstRun calls.

- [ ] **Step 4: Run preview tests**

Run:

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/OPMLImportPreviewControllerTests -only-testing:FeedivoTests/FeedViewModelTests/opmlImportPreviewMarkiertDuplikateUndNichtErreichbareFeeds
```

Expected: PASS.

## Task 5: App wiring characterization and docs

**Files:**
- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`
- Modify: `AGENTS.md`
- Modify: `FEATURES.md`

- [ ] **Step 1: Add/adjust characterization tests**

Add source-inspection tests:

```swift
@Test func opmlImportUndFirstRunPreviewNutzenSQLiteDatabase() throws {
    let opmlImport = try source("Feedivo/Views/OPMLImport/OPMLImportReviewView.swift")
    let firstRun = try source("Feedivo/Views/FirstRun/FirstRunWizardView.swift")

    #expect(opmlImport.contains("sqliteDatabase: feedivoDatabase"))
    #expect(firstRun.contains("sqliteDatabase: feedivoDatabase"))
}

@Test func feedSubscriptionServiceDokumentiertSwiftDataBridgeAlsUebergang() throws {
    let source = try source("Feedivo/Services/SQLiteFeedSubscriptionService.swift")

    #expect(source.contains("Übergangsidentität"))
    #expect(source.contains("SwiftData"))
}
```

- [ ] **Step 2: Run characterization tests to verify failure**

Run:

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/opmlImportUndFirstRunPreviewNutzenSQLiteDatabase -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/feedSubscriptionServiceDokumentiertSwiftDataBridgeAlsUebergang
```

Expected: first test fails until view calls are updated; second fails until the service has the bridge comment.

- [ ] **Step 3: Update docs**

In `AGENTS.md` and `FEATURES.md`, add/update the SQLite migration notes:

```markdown
- Feed hinzufügen, OPML-Import und First-Run-Wizard legen neue Feeds SQLite-first an.
- SwiftData speichert in diesem Pfad nur noch eine minimale Feed-Übergangsidentität,
  damit die bestehende Sidebar-/ContentView-Auswahl bis zum finalen FeedRecord-
  Umbau stabil bleibt.
- Neue Artikel aus Add-/Import-Flows werden in SQLite gespeichert.
```

- [ ] **Step 4: Run docs/source tests**

Run:

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests
```

Expected: PASS.

## Task 6: Full verification and commit

**Files:**
- All modified files from Tasks 1-5.

- [ ] **Step 1: Run focused test suites**

Run:

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests -only-testing:FeedivoTests/FeedViewModelTests -only-testing:FeedivoTests/OPMLImportPreviewControllerTests -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests
```

Expected: PASS.

- [ ] **Step 2: Run app build**

Run:

```bash
xcodebuild build -scheme Feedivo -destination 'platform=macOS'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run whitespace check**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 4: Commit**

Run:

```bash
git status --short
git add Feedivo/Services/SQLiteFeedSubscriptionService.swift Feedivo/ViewModels/FeedViewModel.swift Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift Feedivo/Views/OPMLImport/OPMLImportReviewView.swift Feedivo/Views/FirstRun/FirstRunWizardView.swift FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift FeedivoTests/FeedViewModelTests.swift FeedivoTests/OPMLImportPreviewControllerTests.swift FeedivoTests/FeedivoAppSceneConfigurationTests.swift AGENTS.md FEATURES.md docs/superpowers/plans/2026-07-03-sqlite-feed-subscription-import.md
git commit -m "Feed Import SQLite-first umstellen"
```

Expected: commit succeeds and excludes local Xcode user state.

## Self-Review

- Spec coverage: Feed hinzufügen, OPML-Import, First-Run-Wizard, SQLite-Duplikate, Ordner, Tags, Erst-Refresh, Teilfehler und SwiftData-Bridge sind in Tasks 1-5 abgedeckt.
- Placeholder scan: Keine TBD/TODO-Platzhalter; alle Schritte enthalten konkrete Dateien, Codeformen und Kommandos.
- Type consistency: `SQLiteFeedSubscriptionService`, `SQLiteOPMLImportResult`, `FeedivoDatabase?`, `OPMLFeed`, `FeedRecord` und bestehende Store-Typen werden konsistent verwendet.
- Scope: Sidebar/ContentView-Umstellung auf `FeedRecord` bleibt ausdrücklich außerhalb dieses Plans.
