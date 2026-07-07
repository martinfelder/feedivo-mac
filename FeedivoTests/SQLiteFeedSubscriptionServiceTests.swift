import Foundation
import GRDB
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
    @Test func addFeedRaeumtSQLiteFeedNachArticleUpsertFehlerAuf() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
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
                urlString: "https://example.com/feed.xml"
            )
            Issue.record("Add-Feed hätte wegen Article-Upsert-Fehler fehlschlagen müssen.")
        } catch let error as CleanupFailure {
            #expect(error == .articleUpsertFailed)
        }

        #expect(try FeedStore(database: database).feeds().isEmpty)
    }

    @MainActor
    @Test func addFeedRaeumtArticleStatusesNachFehlerNachArticleUpsertAuf() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
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
                urlString: "https://example.com/feed.xml"
            )
            Issue.record("Add-Feed hätte nach Article-Upsert fehlschlagen müssen.")
        } catch let error as CleanupFailure {
            #expect(error == .afterArticleUpsertFailed)
        }

        #expect(try tableCount("feeds", database: database) == 0)
        #expect(try tableCount("articles", database: database) == 0)
        #expect(try tableCount("article_statuses", database: database) == 0)
    }

    @MainActor
    @Test func importOPMLSpeichertOrdnerTagsUndUeberspringtDuplikate() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
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
            refreshIntervalMinutes: 120
        )

        let feeds = try FeedStore(database: database).feeds()
        let importedFeed = try #require(feeds.first { $0.url == "https://example.com/new.xml" })
        let folders = try FeedFolderStore(database: database).folders()
        let tags = try TagStore(database: database).tags()

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
    }

    @MainActor
    @Test func importOPMLMeldetRefreshFehlerAlsTeilproblem() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
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
            refreshIntervalMinutes: 60
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
    @Test func importOPMLKannDuplikateBewusstImportieren() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
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
            refreshIntervalMinutes: 60
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
    @Test func importOPMLRaeumtSQLiteFeedNachFehlerNachFeedSaveAuf() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
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
                refreshIntervalMinutes: 60
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
    }

    @MainActor
    @Test func importOPMLBehaeltVorhandenenOrdnerNachRollback() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
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
                refreshIntervalMinutes: 60
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

    // MARK: - OPML-Importvorschau (produktive Logik, ehemals in FeedViewModel)

    @MainActor
    @Test func previewMarkiertDuplikateUndNichtErreichbareFeeds() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedStore(database: database).save(
            FeedRecord(id: "existing", url: "https://example.com/existing.xml", title: "Schon da")
        )
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { urlString in
                if urlString == "https://example.com/broken.xml" {
                    throw FeedServiceError.parsingFailed
                }
                return ParsedFeed(sourceURL: urlString, title: "OK", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )

        let rows = await service.previewOPMLFeeds(for: [
            OPMLFeed(title: "Neu", xmlURL: "https://example.com/new.xml", htmlURL: nil, folderName: "News"),
            OPMLFeed(title: "Schon da", xmlURL: "https://example.com/existing.xml", htmlURL: nil, folderName: "Tech"),
            OPMLFeed(title: "Kaputt", xmlURL: "https://example.com/broken.xml", htmlURL: nil, folderName: "News")
        ])

        #expect(rows.map(\.status) == [.available, .duplicate, .unreachable])
        #expect(rows.map(\.isSelected) == [true, false, false])
    }

    @MainActor
    @Test func previewMeldetSichtbarenPrueffortschrittInBeidePhasen() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { urlString in
                ParsedFeed(sourceURL: urlString, title: "OK", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )
        var progressEvents: [OPMLImportPreviewProgress] = []

        _ = await service.previewOPMLFeeds(
            for: [
                OPMLFeed(title: "Erster Feed", xmlURL: "https://example.com/1.xml", htmlURL: nil, folderName: nil),
                OPMLFeed(title: "Zweiter Feed", xmlURL: "https://example.com/2.xml", htmlURL: nil, folderName: nil)
            ],
            onProgress: { progressEvents.append($0) }
        )

        let phase1Events = progressEvents.prefix(2)
        #expect(phase1Events.map(\.currentFeedTitle) == ["Erster Feed", "Zweiter Feed"])
        #expect(phase1Events.map(\.currentIndex) == [1, 2])
        #expect(phase1Events.map(\.displayText) == [
            "Feed 1 von 2 wird geprüft: Erster Feed",
            "Feed 2 von 2 wird geprüft: Zweiter Feed"
        ])

        let phase2Events = progressEvents.dropFirst(2)
        #expect(phase2Events.count == 2)
        #expect(Set(phase2Events.map(\.currentIndex)) == Set(1...2))
        #expect(phase2Events.allSatisfy { $0.totalCount == 2 })
    }

    @MainActor
    @Test func previewParalleelisiertBehaeltReihenfolgeUndStatus() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { urlString in
                if urlString.hasPrefix("fail://") {
                    throw FeedServiceError.parsingFailed
                }
                return ParsedFeed(sourceURL: urlString, title: urlString, description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )
        let opmlFeeds: [OPMLFeed] = [
            OPMLFeed(title: "F1", xmlURL: "https://f1.example.com/feed.xml", htmlURL: nil, folderName: nil),
            OPMLFeed(title: "F2", xmlURL: "https://f2.example.com/feed.xml", htmlURL: nil, folderName: nil),
            OPMLFeed(title: "F3", xmlURL: "fail://broken", htmlURL: nil, folderName: nil),
            OPMLFeed(title: "F4", xmlURL: "https://f4.example.com/feed.xml", htmlURL: nil, folderName: nil),
            OPMLFeed(title: "F5", xmlURL: "https://f5.example.com/feed.xml", htmlURL: nil, folderName: nil),
            OPMLFeed(title: "F6", xmlURL: "https://f6.example.com/feed.xml", htmlURL: nil, folderName: nil)
        ]

        let rows = await service.previewOPMLFeeds(for: opmlFeeds)

        #expect(rows.count == 6)
        #expect(rows.map(\.feed.title) == ["F1", "F2", "F3", "F4", "F5", "F6"])
        #expect(rows[0].status == .available)
        #expect(rows[1].status == .available)
        #expect(rows[2].status == .unreachable)
        #expect(rows[3].status == .available)
        #expect(rows[4].status == .available)
        #expect(rows[5].status == .available)
        #expect(rows.allSatisfy { $0.status != .duplicate })
    }
}
