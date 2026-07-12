import Foundation
import GRDB
import Testing
@testable import Feedivo

// Bewusst außerhalb der `@MainActor`-isolierten Testfunktion UND außerhalb des
// `@Suite`-Structs erzeugt: Ein Closure-Literal übernimmt sonst die Aktor-Isolation seines
// Erzeugungskontexts, nicht die des Aufrufers. Würde dieser Fetcher direkt als
// `{ urlString in await ... }`-Closure-Literal innerhalb von
// `previewFeedsWerdenTatsaechlichParallelAbgerufen()` (einer `@MainActor @Test func`)
// geschrieben, würde `Thread.isMainThread` innerhalb des Closures IMMER `true` liefern —
// unabhängig davon, ob `previewOPMLFeeds`s `group.addTask`-Kind-Tasks selbst auf den
// MainActor gepinnt sind oder nicht. Das wurde beim Schreiben dieses Tests live verifiziert
// (per Revert/Re-Apply des `@MainActor`-Pinnings in `SQLiteFeedSubscriptionService.swift`):
// Ein lexikalisch innerhalb der Testfunktion erzeugter Closure blieb in BEIDEN Fällen bei
// `[true, true, true, true, true, true]` hängen. Diese freistehende, explizit
// `nonisolated` Fabrikfunktion erzeugt den Fetcher dagegen in einem Kontext ohne
// MainActor-Bezug, sodass `Thread.isMainThread` tatsächlich widerspiegelt, auf welchem
// Executor der jeweilige `group.addTask`-Kind-Task läuft.
nonisolated func makeThreadObservingFeedFetcher(
    record: @escaping @Sendable (Bool) async -> Void
) -> SQLiteFeedSubscriptionService.FeedFetcher {
    { urlString in
        await record(Thread.isMainThread)
        return ParsedFeed(sourceURL: urlString, title: urlString, description: nil, articles: [])
    }
}

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
    @Test func addFeedMitNeuemFolderNameRaeumtOrdnerNachArticleUpsertFehlerAuf() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { url in
                ParsedFeed(
                    sourceURL: url,
                    title: "Fehler Feed mit Ordner",
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
                folderName: "Nachrichten"
            )
            Issue.record("Add-Feed hätte wegen Article-Upsert-Fehler fehlschlagen müssen.")
        } catch let error as CleanupFailure {
            #expect(error == .articleUpsertFailed)
        }

        #expect(try FeedStore(database: database).feeds().isEmpty)
        // Der beim gescheiterten Add-Feed neu angelegte Ordner darf nicht als
        // verwaister leerer Ordner zurueckbleiben.
        #expect(try FeedFolderStore(database: database).folders().isEmpty)
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
    @Test func previewMarkiertSyntaktischUngueltigeURLsSofortAlsNichtErreichbarOhneNetzwerkAufruf() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        var fetchCallCount = 0
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { urlString in
                fetchCallCount += 1
                return ParsedFeed(sourceURL: urlString, title: "OK", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )

        let rows = await service.previewOPMLFeeds(for: [
            OPMLFeed(title: "Mit Leerzeichen", xmlURL: "not a valid url", htmlURL: nil, folderName: nil),
            OPMLFeed(title: "Ohne Schema", xmlURL: "example.com/feed.xml", htmlURL: nil, folderName: nil),
            OPMLFeed(title: "Gueltig", xmlURL: "https://example.com/feed.xml", htmlURL: nil, folderName: nil)
        ])

        #expect(rows.map(\.status) == [.unreachable, .unreachable, .available])
        #expect(rows.map(\.isSelected) == [false, false, true])
        #expect(fetchCallCount == 1)
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

    @MainActor
    @Test func previewFeedsWerdenTatsaechlichParallelAbgerufen() async throws {
        actor ThreadObservationCollector {
            private var observations: [Bool] = []

            func record(isMainThread: Bool) {
                observations.append(isMainThread)
            }

            var isMainThreadFlags: [Bool] { observations }
        }

        let collector = ThreadObservationCollector()
        let database = try FeedivoDatabase.inMemoryForTests()
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: makeThreadObservingFeedFetcher { isMainThread in
                await collector.record(isMainThread: isMainThread)
            },
            discoverFaviconURL: { _ in nil }
        )
        let opmlFeeds = (1...6).map { index in
            OPMLFeed(
                title: "F\(index)",
                xmlURL: "https://f\(index).example.com/feed.xml",
                htmlURL: nil,
                folderName: nil
            )
        }

        _ = await service.previewOPMLFeeds(for: opmlFeeds)

        let flags = await collector.isMainThreadFlags
        #expect(flags.count == 6)
        #expect(flags.contains(false))
    }

    @MainActor
    @Test func addFeedMitFolderNameSetztOrdnerUndLegtOrdnerRecordAn() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { url in
                ParsedFeed(sourceURL: url, title: "Ordner Feed", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )

        _ = try await service.addFeed(
            urlString: "https://example.com/feed.xml",
            folderName: "Nachrichten"
        )

        let feed = try #require(try FeedStore(database: database).feeds().first)
        #expect(feed.folderName == "Nachrichten")

        let folderNames = try FeedFolderStore(database: database).folders().map(\.name)
        #expect(folderNames.contains("Nachrichten"))
    }

    @MainActor
    @Test func addFeedOhneFolderNameLaesstOrdnerLeer() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { url in
                ParsedFeed(sourceURL: url, title: "Kein Ordner Feed", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )

        _ = try await service.addFeed(urlString: "https://example.com/feed.xml")

        let feed = try #require(try FeedStore(database: database).feeds().first)
        #expect(feed.folderName == nil)
        #expect(try FeedFolderStore(database: database).folders().isEmpty)
    }

    @MainActor
    @Test func addFeedMitBestehendemOrdnerLegtKeinenZweitenRecordAn() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedFolderStore(database: database).save(FeedFolderRecord(name: "Technik"))
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { url in
                ParsedFeed(sourceURL: url, title: "Technik Feed", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )

        // Andere Gross-/Kleinschreibung muss auf den bestehenden Ordner matchen.
        _ = try await service.addFeed(
            urlString: "https://example.com/feed.xml",
            folderName: "technik"
        )

        let folders = try FeedFolderStore(database: database).folders()
        #expect(folders.count == 1)
        let feed = try #require(try FeedStore(database: database).feeds().first)
        // Feed uebernimmt den getippten (normalisierten) Namen.
        #expect(feed.folderName == "technik")
    }

    @MainActor
    @Test func actionServiceAddFeedReichtFolderNameDurch() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let service = SQLiteFeedActionService(
            database: database,
            fetchFeed: { url in
                ParsedFeed(sourceURL: url, title: "Action Feed", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )

        try await service.addFeed(
            urlString: "https://example.com/feed.xml",
            refreshIntervalMinutes: 60,
            folderName: "Blogs"
        )

        let feed = try #require(try FeedStore(database: database).feeds().first)
        #expect(feed.folderName == "Blogs")
    }
}
