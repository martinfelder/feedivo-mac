import Foundation
import GRDB
import SwiftData
import Testing
@testable import Feedivo

@Suite(.serialized)
struct SQLiteFeedSubscriptionServiceTests {
    enum CleanupFailure: Error, Equatable {
        case articleUpsertFailed
        case afterArticleUpsertFailed
        case afterOPMLFeedSaveFailed
    }

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
        let logs = try FeedLogStore(database: database).logs(feedID: result.feedID, limit: 5)
        let firstLog = try #require(logs.first)

        #expect(sqliteFeed.title == "Example Feed")
        #expect(sqliteFeed.url == "https://example.com/feed.xml")
        #expect(sqliteFeed.websiteURL == "https://example.com")
        #expect(sqliteFeed.faviconURL == "https://example.com/favicon.ico")
        #expect(sqliteFeed.refreshIntervalMinutes == 60)
        #expect(sqliteFeed.unreadCount == 1)
        #expect(timelineRows.map(\.title) == ["Erster Artikel"])
        #expect(firstLog.feedID == result.feedID)
        #expect(firstLog.level == "info")
        #expect(firstLog.message == L10n.feedLogAdded)
        #expect(firstLog.newArticleCount == 1)
        #expect(swiftDataFeeds.count == 1)
        #expect(swiftDataFeeds[0].id.uuidString == result.feedID)
        #expect(swiftDataFeeds[0].title == "Example Feed")
        #expect(swiftDataArticles.isEmpty)
    }

    @MainActor
    @Test func addFeedKannOhneSwiftDataBridgeLaufen() async throws {
        let defaults = UserDefaults.standard
        let previousBridgeSetting = defaults.object(forKey: SwiftDataBridgeSettings.isEnabledKey)
        defaults.set(false, forKey: SwiftDataBridgeSettings.isEnabledKey)
        defer {
            if let previousBridgeSetting {
                defaults.set(previousBridgeSetting, forKey: SwiftDataBridgeSettings.isEnabledKey)
            } else {
                defaults.removeObject(forKey: SwiftDataBridgeSettings.isEnabledKey)
            }
        }

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

        let rows = try TimelineStore(database: database).articles(
            scope: .feed(result.feedID),
            includeRead: true,
            includeHidden: false,
            limit: 10
        )
        let swiftDataFeeds = try context.fetch(FetchDescriptor<Feed>())
        let swiftDataArticles = try context.fetch(FetchDescriptor<Article>())

        #expect(rows.map(\.title) == ["Erster Artikel"])
        #expect(swiftDataFeeds.isEmpty)
        #expect(swiftDataArticles.isEmpty)
    }

    @MainActor
    @Test func addFeedErkenntDuplikatAuchInSwiftDataBridge() async throws {
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
        let existingFeed = Feed(
            url: " HTTPS://EXAMPLE.COM/FEED.XML ",
            title: "Schon vorhanden"
        )
        context.insert(existingFeed)
        try context.save()

        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { url in
                ParsedFeed(
                    sourceURL: url,
                    title: "Duplikat",
                    description: nil,
                    articles: []
                )
            },
            discoverFaviconURL: { _ in nil }
        )

        do {
            _ = try await service.addFeed(
                urlString: "https://example.com/feed.xml",
                context: context
            )
            Issue.record("Add-Feed hätte wegen SwiftData-Duplikat fehlschlagen müssen.")
        } catch let error as SQLiteFeedSubscriptionError {
            #expect(error == .duplicateFeed)
        }

        #expect(try FeedStore(database: database).feeds().isEmpty)
    }

    @MainActor
    @Test func addFeedRaeumtSQLiteFeedNachArticleUpsertFehlerAuf() async throws {
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
                    title: "Fehler Feed",
                    description: nil,
                    articles: [
                        ParsedArticle(
                            title: "Wird nicht gespeichert",
                            sourceID: "kaputt",
                            link: "https://example.com/broken",
                            summary: nil,
                            content: nil,
                            publishedAt: nil,
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in nil },
            articleUpsert: { _ in
                throw CleanupFailure.articleUpsertFailed
            }
        )

        do {
            _ = try await service.addFeed(
                urlString: "https://example.com/feed.xml",
                context: context
            )
            Issue.record("Add-Feed hätte wegen Article-Upsert-Fehler fehlschlagen müssen.")
        } catch let error as CleanupFailure {
            #expect(error == .articleUpsertFailed)
        }

        #expect(try FeedStore(database: database).feeds().isEmpty)
        #expect(try context.fetch(FetchDescriptor<Feed>()).isEmpty)
    }

    @MainActor
    @Test func addFeedRaeumtArticleStatusesNachFehlerNachArticleUpsertAuf() async throws {
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
                    title: "Fehler nach Upsert",
                    description: nil,
                    articles: [
                        ParsedArticle(
                            title: "Status wird verwaist",
                            sourceID: "status",
                            link: "https://example.com/status",
                            summary: nil,
                            content: nil,
                            publishedAt: nil,
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in nil },
            afterArticleUpsert: {
                throw CleanupFailure.afterArticleUpsertFailed
            }
        )

        do {
            _ = try await service.addFeed(
                urlString: "https://example.com/feed.xml",
                context: context
            )
            Issue.record("Add-Feed hätte nach Article-Upsert fehlschlagen müssen.")
        } catch let error as CleanupFailure {
            #expect(error == .afterArticleUpsertFailed)
        }

        #expect(try tableCount("feeds", database: database) == 0)
        #expect(try tableCount("articles", database: database) == 0)
        #expect(try tableCount("article_statuses", database: database) == 0)
        #expect(try context.fetch(FetchDescriptor<Feed>()).isEmpty)
    }

    @MainActor
    @Test func importOPMLSpeichertOrdnerTagsUndUeberspringtDuplikate() async throws {
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
        try FeedStore(database: database).save(
            FeedRecord(
                url: "https://example.com/existing.xml",
                title: "Schon da"
            )
        )
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { url in
                ParsedFeed(
                    sourceURL: url,
                    title: "Parsed \(url)",
                    description: nil,
                    articles: []
                )
            },
            discoverFaviconURL: { _ in nil }
        )

        let result = try await service.importOPMLFeeds(
            [
                OPMLFeed(
                    title: "Neu",
                    xmlURL: "https://example.com/new.xml",
                    htmlURL: "https://example.com",
                    folderName: "News",
                    tagNames: ["Swift", "Mac"]
                ),
                OPMLFeed(
                    title: "Duplikat",
                    xmlURL: "https://example.com/existing.xml",
                    htmlURL: nil,
                    folderName: "News",
                    tagNames: ["Swift"]
                )
            ],
            allowsDuplicates: false,
            refreshAfterImport: false,
            refreshIntervalMinutes: 120,
            context: context
        )

        let feeds = try FeedStore(database: database).feeds()
        let importedFeed = try #require(feeds.first { $0.url == "https://example.com/new.xml" })
        let folders = try FeedFolderStore(database: database).folders()
        let tags = try TagStore(database: database).tags()
        let bridgeFeeds = try context.fetch(FetchDescriptor<Feed>())

        #expect(result.total == 2)
        #expect(result.imported == 1)
        #expect(result.skippedDuplicates == 1)
        #expect(result.failedFeedTitles.isEmpty)
        #expect(importedFeed.title == "Neu")
        #expect(importedFeed.websiteURL == "https://example.com")
        #expect(importedFeed.folderName == "News")
        #expect(importedFeed.refreshIntervalMinutes == 120)
        #expect(folders.map(\.name) == ["News"])
        #expect(tags.map(\.name).sorted() == ["Mac", "Swift"])
        #expect(try tableCount("feed_tags", database: database) == 2)
        #expect(bridgeFeeds.count == 1)
        #expect(bridgeFeeds[0].id.uuidString == importedFeed.id)
        #expect(bridgeFeeds[0].refreshIntervalMinutes == 120)
    }

    @MainActor
    @Test func importOPMLKannOhneSwiftDataBridgeLaufen() async throws {
        let defaults = UserDefaults.standard
        let previousBridgeSetting = defaults.object(forKey: SwiftDataBridgeSettings.isEnabledKey)
        defaults.set(false, forKey: SwiftDataBridgeSettings.isEnabledKey)
        defer {
            if let previousBridgeSetting {
                defaults.set(previousBridgeSetting, forKey: SwiftDataBridgeSettings.isEnabledKey)
            } else {
                defaults.removeObject(forKey: SwiftDataBridgeSettings.isEnabledKey)
            }
        }

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
                    title: "Parsed \(url)",
                    description: nil,
                    articles: []
                )
            },
            discoverFaviconURL: { _ in nil }
        )

        _ = try await service.importOPMLFeeds(
            [
                OPMLFeed(
                    title: "Neu",
                    xmlURL: "https://example.com/new.xml",
                    htmlURL: "https://example.com",
                    folderName: "News",
                    tagNames: ["Swift", "Mac"]
                )
            ],
            allowsDuplicates: false,
            refreshAfterImport: false,
            refreshIntervalMinutes: 120,
            context: context
        )

        #expect((try FeedStore(database: database).feeds().count) == 1)
        #expect(try context.fetch(FetchDescriptor<Feed>()).isEmpty)
    }

    @MainActor
    @Test func importOPMLMeldetRefreshFehlerAlsTeilproblem() async throws {
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
            fetchFeed: { _ in
                throw FeedServiceError.httpError(500)
            },
            discoverFaviconURL: { _ in nil }
        )

        let result = try await service.importOPMLFeeds(
            [
                OPMLFeed(
                    title: "Kaputt",
                    xmlURL: "https://example.com/broken.xml",
                    htmlURL: nil,
                    folderName: nil
                )
            ],
            allowsDuplicates: false,
            refreshAfterImport: true,
            refreshIntervalMinutes: 60,
            context: context
        )

        let feeds = try FeedStore(database: database).feeds()
        let feed = try #require(feeds.first)
        let logs = try FeedLogStore(database: database).logs(feedID: feed.id, limit: 5)

        #expect(result.total == 1)
        #expect(result.imported == 1)
        #expect(result.skippedDuplicates == 0)
        #expect(result.failedFeedTitles == ["Kaputt"])
        #expect(feeds.map(\.url) == ["https://example.com/broken.xml"])
        #expect(feed.title == "Kaputt")
        #expect(logs.contains { $0.level == "error" && $0.httpStatusCode == 500 })
    }

    @MainActor
    @Test func importOPMLAktualisiertSwiftDataBridgeNachErfolgreichemRefresh() async throws {
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
                    title: "Titel aus Refresh",
                    description: nil,
                    siteURL: "https://example.com/aktualisiert",
                    articles: [
                        ParsedArticle(
                            title: "Neuer SQLite Artikel",
                            sourceID: "sqlite-new",
                            link: "https://example.com/artikel",
                            summary: nil,
                            content: nil,
                            publishedAt: Date(timeIntervalSince1970: 42),
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in nil }
        )

        let result = try await service.importOPMLFeeds(
            [
                OPMLFeed(
                    title: "Titel aus OPML",
                    xmlURL: "https://example.com/feed.xml",
                    htmlURL: "https://example.com/alt",
                    folderName: "News"
                )
            ],
            allowsDuplicates: false,
            refreshAfterImport: true,
            refreshIntervalMinutes: 60,
            context: context
        )

        let feedID = try #require(try FeedStore(database: database).feed(url: "https://example.com/feed.xml")?.id)
        let bridgeFeed = try #require(try context.fetch(FetchDescriptor<Feed>()).first)

        #expect(result.imported == 1)
        #expect(result.failedFeedTitles.isEmpty)
        #expect(bridgeFeed.id.uuidString == feedID)
        #expect(bridgeFeed.title == "Titel aus Refresh")
        #expect(bridgeFeed.siteURL == "https://example.com/aktualisiert")
        #expect(bridgeFeed.unreadCount == 1)
        #expect(try context.fetch(FetchDescriptor<Article>()).isEmpty)
    }

    @MainActor
    @Test func importOPMLKannDuplikateBewusstImportieren() async throws {
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
        try FeedStore(database: database).save(
            FeedRecord(
                url: "https://example.com/existing.xml",
                title: "Schon da"
            )
        )
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { url in
                ParsedFeed(
                    sourceURL: url,
                    title: "Parsed \(url)",
                    description: nil,
                    articles: []
                )
            },
            discoverFaviconURL: { _ in nil }
        )

        let result = try await service.importOPMLFeeds(
            [
                OPMLFeed(
                    title: "Noch einmal",
                    xmlURL: "https://example.com/existing.xml",
                    htmlURL: nil,
                    folderName: nil
                )
            ],
            allowsDuplicates: true,
            refreshAfterImport: false,
            refreshIntervalMinutes: 60,
            context: context
        )

        let duplicateFeeds = try FeedStore(database: database)
            .feeds()
            .filter { $0.url == "https://example.com/existing.xml" }

        #expect(result.total == 1)
        #expect(result.imported == 1)
        #expect(result.skippedDuplicates == 0)
        #expect(duplicateFeeds.count == 2)
        #expect(Set(duplicateFeeds.map(\.id)).count == 2)
    }

    @MainActor
    @Test func importOPMLUeberspringtDuplikatAusSwiftDataBridge() async throws {
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
        context.insert(
            Feed(
                url: " HTTPS://EXAMPLE.COM/EXISTING.XML ",
                title: "Nur SwiftData"
            )
        )
        try context.save()
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { url in
                ParsedFeed(
                    sourceURL: url,
                    title: "Parsed \(url)",
                    description: nil,
                    articles: []
                )
            },
            discoverFaviconURL: { _ in nil }
        )

        let result = try await service.importOPMLFeeds(
            [
                OPMLFeed(
                    title: "Duplikat",
                    xmlURL: "https://example.com/existing.xml",
                    htmlURL: nil,
                    folderName: nil
                )
            ],
            allowsDuplicates: false,
            refreshAfterImport: false,
            refreshIntervalMinutes: 60,
            context: context
        )

        #expect(result.imported == 0)
        #expect(result.skippedDuplicates == 1)
        #expect(try FeedStore(database: database).feeds().isEmpty)
    }

    @MainActor
    @Test func importOPMLRaeumtSQLiteFeedNachFehlerNachFeedSaveAuf() async throws {
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
                    title: "Parsed \(url)",
                    description: nil,
                    articles: []
                )
            },
            discoverFaviconURL: { _ in nil },
            afterOPMLTagsSave: {
                throw CleanupFailure.afterOPMLFeedSaveFailed
            }
        )

        do {
            _ = try await service.importOPMLFeeds(
                [
                    OPMLFeed(
                        title: "Fehler",
                        xmlURL: "https://example.com/broken.xml",
                        htmlURL: nil,
                        folderName: "News",
                        tagNames: ["Temp"]
                    )
                ],
                allowsDuplicates: false,
                refreshAfterImport: false,
                refreshIntervalMinutes: 60,
                context: context
            )
            Issue.record("OPML-Import hätte nach Feed-Save fehlschlagen müssen.")
        } catch let error as CleanupFailure {
            #expect(error == .afterOPMLFeedSaveFailed)
        }

        #expect(try tableCount("feeds", database: database) == 0)
        #expect(try tableCount("tags", database: database) == 0)
        #expect(try tableCount("feed_tags", database: database) == 0)
        #expect(try tableCount("feed_logs", database: database) == 0)
        #expect(try tableCount("feed_folders", database: database) == 0)
        #expect(try context.fetch(FetchDescriptor<Feed>()).isEmpty)
    }

    @MainActor
    @Test func importOPMLBehaeltVorhandenenOrdnerNachRollback() async throws {
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
        let existingFolder = FeedFolderRecord(id: "folder-news", name: "News")
        try FeedFolderStore(database: database).save(existingFolder)
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { url in
                ParsedFeed(
                    sourceURL: url,
                    title: "Parsed \(url)",
                    description: nil,
                    articles: []
                )
            },
            discoverFaviconURL: { _ in nil },
            afterOPMLTagsSave: {
                throw CleanupFailure.afterOPMLFeedSaveFailed
            }
        )

        do {
            _ = try await service.importOPMLFeeds(
                [
                    OPMLFeed(
                        title: "Fehler",
                        xmlURL: "https://example.com/broken.xml",
                        htmlURL: nil,
                        folderName: "News",
                        tagNames: ["Temp"]
                    )
                ],
                allowsDuplicates: false,
                refreshAfterImport: false,
                refreshIntervalMinutes: 60,
                context: context
            )
            Issue.record("OPML-Import hätte nach Feed-Save fehlschlagen müssen.")
        } catch let error as CleanupFailure {
            #expect(error == .afterOPMLFeedSaveFailed)
        }

        let folders = try FeedFolderStore(database: database).folders()
        #expect(try tableCount("feeds", database: database) == 0)
        #expect(folders.map(\.id) == [existingFolder.id])
        #expect(folders.map(\.name) == ["News"])
    }

    private func tableCount(_ tableName: String, database: FeedivoDatabase) throws -> Int {
        try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(tableName)") ?? 0
        }
    }
}
