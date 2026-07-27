import Foundation
import GRDB
import Testing
@testable import Feedivo

struct SQLiteFeedRefreshServiceTests {
    @Test func refreshInsertsParsedArticlesAndUpdatesUnreadCount() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let logStore = FeedLogStore(database: database)
        let refreshedAt = Date(timeIntervalSince1970: 5_000)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Old"))

        let service = SQLiteFeedRefreshService(database: database, now: { refreshedAt }) { url, validators in
            #expect(url == "https://example.com/feed.xml")
            #expect(validators == FeedHTTPValidators())
            return .updated(
                ParsedFeed(
                    sourceURL: url,
                    title: "Example",
                    description: "Description",
                    siteURL: "https://example.com",
                    articles: [
                        ParsedArticle(
                            title: "One",
                            sourceID: "one",
                            link: "https://example.com/one",
                            summary: "Summary one",
                            content: "Content one",
                            publishedAt: Date(timeIntervalSince1970: 1_000),
                            imageURL: "https://example.com/one.jpg",
                            author: "Autor Eins"
                        ),
                        ParsedArticle(
                            title: "Two",
                            sourceID: "two",
                            link: "https://example.com/two",
                            summary: nil,
                            content: nil,
                            publishedAt: Date(timeIntervalSince1970: 2_000),
                            imageURL: nil
                        )
                    ]
                ),
                FeedHTTPValidators(eTag: "etag-1", lastModified: "last-1", contentHash: "hash-1", lastStatusCode: 200)
            )
        }

        let result = try await service.refresh(feedID: "feed-1")
        let feed = try feedStore.feed(id: "feed-1")
        let logs = try logStore.logs(feedID: "feed-1", limit: 5)
        let articleCount = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM articles") ?? 0
        }
        let firstArticle = try articleStore.readerArticle(id: result.insertedArticleIDs[0])

        #expect(result.insertedArticleIDs.count == 2)
        #expect(feed?.title == "Example")
        #expect(feed?.websiteURL == "https://example.com")
        #expect(feed?.unreadCount == 2)
        #expect(feed?.lastETag == "etag-1")
        #expect(articleCount == 2)
        #expect(firstArticle?.content == "Content one")
        #expect(firstArticle?.author == "Autor Eins")
        #expect(logs.first?.level == "info")
        #expect(logs.first?.newArticleCount == 2)
    }

    // Regressionstest für den enrichArticleImages-Verdrahtungsfix: die Closure
    // muss vor dem ArticleUpsertInput-Mapping aufgerufen werden und ihr
    // Ergebnis muss tatsächlich gespeichert werden — nicht das rohe
    // article.imageURL aus dem Feed-Parse. Siehe CLAUDE.md-Regressionsbefund
    // zu Commit 0e4ae0a6 (2026-07-07), der den letzten produktiven Aufruf
    // versehentlich mitentfernt hatte.
    @Test func refreshRuftEnrichArticleImagesAufUndSpeichertDerenErgebnis() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Old"))

        var receivedArticles: [ParsedArticle] = []
        let service = SQLiteFeedRefreshService(
            database: database,
            enrichArticleImages: { articles in
                receivedArticles = articles
                return articles.map { article in
                    ParsedArticle(
                        title: article.title,
                        sourceID: article.sourceID,
                        link: article.link,
                        summary: article.summary,
                        content: article.content,
                        publishedAt: article.publishedAt,
                        imageURL: "https://example.com/enriched.jpg",
                        author: article.author
                    )
                }
            },
            fetcher: { url, _ in
                .updated(
                    ParsedFeed(
                        sourceURL: url,
                        title: "Example",
                        description: nil,
                        siteURL: nil,
                        articles: [
                            ParsedArticle(
                                title: "Ohne Bild",
                                sourceID: "one",
                                link: "https://example.com/one",
                                summary: nil,
                                content: nil,
                                publishedAt: Date(timeIntervalSince1970: 1_000),
                                imageURL: nil
                            )
                        ]
                    ),
                    FeedHTTPValidators()
                )
            }
        )

        let result = try await service.refresh(feedID: "feed-1")
        let storedArticle = try articleStore.readerArticle(id: result.insertedArticleIDs[0])

        #expect(receivedArticles.count == 1)
        #expect(receivedArticles.first?.imageURL == nil)
        #expect(storedArticle?.imageURL == "https://example.com/enriched.jpg")
    }

    @Test func refreshIndexiertNeueArtikelInSpotlight() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        var indexedSnapshots: [ArticleListSnapshot] = []
        let service = SQLiteFeedRefreshService(
            database: database,
            indexForSpotlight: { indexedSnapshots.append(contentsOf: $0) }
        ) { url, _ in
            .updated(
                ParsedFeed(
                    sourceURL: url,
                    title: "Example",
                    description: nil,
                    articles: [
                        ParsedArticle(
                            title: "Neu",
                            sourceID: "one",
                            link: nil,
                            summary: "Zusammenfassung",
                            content: nil,
                            publishedAt: nil,
                            imageURL: nil
                        )
                    ]
                ),
                FeedHTTPValidators()
            )
        }

        _ = try await service.refresh(feedID: "feed-1")

        #expect(indexedSnapshots.count == 1)
        #expect(indexedSnapshots.first?.title == "Neu")
        #expect(indexedSnapshots.first?.feedTitle == "Example")
    }

    @Test func refreshRuftSpotlightIndexierungNichtBeiNotModifiedAuf() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        var indexCallCount = 0
        let service = SQLiteFeedRefreshService(
            database: database,
            indexForSpotlight: { _ in indexCallCount += 1 }
        ) { _, validators in
            .notModified(validators)
        }

        _ = try await service.refresh(feedID: "feed-1")

        #expect(indexCallCount == 0)
    }

    @Test func refreshNotModifiedUpdatesValidatorsAndLeavesArticlesUntouched() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let logStore = FeedLogStore(database: database)
        let refreshedAt = Date(timeIntervalSince1970: 5_000)

        try feedStore.save(FeedRecord(
            id: "feed-1",
            url: "https://example.com/feed.xml",
            title: "Example",
            lastETag: "old-etag",
            unreadCount: 1
        ))
        let existingID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "one", title: "Existing")
        )

        let service = SQLiteFeedRefreshService(database: database, now: { refreshedAt }) { _, validators in
            #expect(validators.eTag == "old-etag")
            return .notModified(FeedHTTPValidators(eTag: "new-etag", lastModified: "last-2", contentHash: "hash-2", lastStatusCode: 304))
        }

        let result = try await service.refresh(feedID: "feed-1")
        let feed = try feedStore.feed(id: "feed-1")
        let article = try articleStore.readerArticle(id: existingID)
        let logs = try logStore.logs(feedID: "feed-1", limit: 5)

        #expect(result.insertedArticleIDs.isEmpty)
        #expect(feed?.unreadCount == 1)
        #expect(feed?.lastETag == "new-etag")
        #expect(feed?.lastHTTPStatusCode == 304)
        #expect(article?.title == "Existing")
        #expect(logs.first?.message == "Nicht geändert")
    }

    @Test func refreshFailureWritesErrorLogAndKeepsExistingArticles() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "one", title: "Existing"))

        let service = SQLiteFeedRefreshService(database: database) { _, _ in
            throw FeedServiceError.httpError(500)
        }

        await #expect(throws: FeedServiceError.self) {
            try await service.refresh(feedID: "feed-1")
        }
        let logs = try logStore.logs(feedID: "feed-1", limit: 5)
        let articleCount = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM articles") ?? 0
        }

        #expect(articleCount == 1)
        #expect(logs.first?.level == "error")
        #expect(logs.first?.httpStatusCode == 500)
    }

    @Test func refreshPreservesReadStatusWhenArticleUpdates() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let existingID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "one", title: "Old Title")
        )
        try statusStore.setRead(true, articleID: existingID, at: Date(timeIntervalSince1970: 2_000))

        let service = SQLiteFeedRefreshService(database: database) { url, _ in
            .updated(
                ParsedFeed(
                    sourceURL: url,
                    title: "Example",
                    description: nil,
                    siteURL: nil,
                    articles: [
                        ParsedArticle(
                            title: "New Title",
                            sourceID: "one",
                            link: "https://example.com/changed",
                            summary: "Updated",
                            content: "Updated content",
                            publishedAt: Date(timeIntervalSince1970: 3_000),
                            imageURL: nil
                        )
                    ]
                ),
                FeedHTTPValidators(lastStatusCode: 200)
            )
        }

        let result = try await service.refresh(feedID: "feed-1")
        let article = try articleStore.readerArticle(id: existingID)
        let status = try statusStore.status(articleID: existingID)

        #expect(result.insertedArticleIDs.isEmpty)
        #expect(article?.title == "New Title")
        #expect(article?.link == "https://example.com/changed")
        #expect(status?.isRead == true)
    }

    @Test func refreshCountsOnlyRecentlyPublishedArticlesAsNew() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)
        let refreshedAt = Date(timeIntervalSince1970: 1_000_000)
        let longAgo = refreshedAt.addingTimeInterval(-30 * 24 * 60 * 60)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Old"))

        let service = SQLiteFeedRefreshService(database: database, now: { refreshedAt }) { url, _ in
            .updated(
                ParsedFeed(
                    sourceURL: url,
                    title: "Example",
                    description: nil,
                    siteURL: nil,
                    articles: [
                        ParsedArticle(
                            title: "Frischer Artikel",
                            sourceID: "fresh",
                            link: "https://example.com/fresh",
                            summary: nil,
                            content: nil,
                            publishedAt: refreshedAt.addingTimeInterval(-60),
                            imageURL: nil
                        ),
                        ParsedArticle(
                            title: "Archiv-Artikel",
                            sourceID: "archive",
                            link: "https://example.com/archive",
                            summary: nil,
                            content: nil,
                            publishedAt: longAgo,
                            imageURL: nil
                        )
                    ]
                ),
                FeedHTTPValidators(lastStatusCode: 200)
            )
        }

        let result = try await service.refresh(feedID: "feed-1")
        let logs = try logStore.logs(feedID: "feed-1", limit: 5)

        #expect(result.insertedArticleIDs.count == 2)
        #expect(result.newArticleCount == 1)
        #expect(logs.first?.newArticleCount == 1)
    }

    // Regressionstest für den Performance-Fix aus dem NetNewsWire-Vergleich
    // (2026-07-27): applyRules() schrieb bisher für jeden Regel-Treffer eine
    // eigene GRDB-Transaktion (je ein setHidden- bzw. tagStore.save/assignTag-
    // Aufruf pro Artikel) — die Anzahl der COMMITs wuchs damit linear mit der
    // Trefferzahl. Jetzt läuft die gesamte Regel-Persistenz eines Refreshs in
    // EINER Transaktion, daher darf die COMMIT-Zahl nicht mehr mit der
    // Trefferzahl wachsen. Gemessen über GRDBs SQL-Trace (zählt "COMMIT
    // TRANSACTION"-Anweisungen), nicht über Implementierungsdetails der Stores.
    @Test func applyRulesPersistiertTrefferInEinerTransaktionUnabhaengigVonDerTrefferzahl() async throws {
        let commitsForOneMatch = try await commitCountForRefresh(matchingArticleCount: 1)
        let commitsForFiveMatches = try await commitCountForRefresh(matchingArticleCount: 5)

        #expect(commitsForOneMatch == commitsForFiveMatches)
    }

    private final class CommitCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func increment() {
            lock.lock()
            value += 1
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private func commitCountForRefresh(matchingArticleCount: Int) async throws -> Int {
        let commits = CommitCounter()
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
            database.trace(options: .statement) { event in
                guard case .statement(let statementEvent) = event else { return }
                if statementEvent.sql.uppercased().hasPrefix("COMMIT") {
                    commits.increment()
                }
            }
        }
        let queue = try DatabaseQueue(configuration: configuration)
        try FeedivoDatabaseMigrator.migrator.migrate(queue)
        let database = FeedivoDatabase(writer: queue)

        let feedStore = FeedStore(database: database)
        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Feed"))

        let tag = RuleEngine.TagSnapshot(id: "tag-1", name: "Auto", colorHex: "#3B82F6")
        let tagRule = RuleEngine.RuleSnapshot(
            id: UUID(),
            name: "Tag alles",
            isEnabled: true,
            actionRaw: RuleAction.assignTag.rawValue,
            notificationTemplate: "{Titel}",
            notificationPriorityRaw: RuleNotificationPriority.normal.rawValue,
            sortOrder: 0,
            conditions: [
                RuleEngine.RuleConditionSnapshot(
                    field: RuleConditionField.title.rawValue,
                    conditionOperator: RuleConditionOperator.contains.rawValue,
                    value: "Artikel",
                    sortOrder: 0
                )
            ],
            assignTag: tag
        )
        let hideRule = RuleEngine.RuleSnapshot(
            id: UUID(),
            name: "Verstecke alles",
            isEnabled: true,
            actionRaw: RuleAction.hideArticle.rawValue,
            notificationTemplate: "{Titel}",
            notificationPriorityRaw: RuleNotificationPriority.normal.rawValue,
            sortOrder: 1,
            conditions: [
                RuleEngine.RuleConditionSnapshot(
                    field: RuleConditionField.title.rawValue,
                    conditionOperator: RuleConditionOperator.contains.rawValue,
                    value: "Artikel",
                    sortOrder: 0
                )
            ],
            assignTag: nil
        )

        let articles = (0..<matchingArticleCount).map { index in
            ParsedArticle(
                title: "Artikel \(index)",
                sourceID: "id-\(index)",
                link: "https://example.com/\(index)",
                summary: nil,
                content: nil,
                publishedAt: Date(timeIntervalSince1970: Double(index)),
                imageURL: nil
            )
        }

        let service = SQLiteFeedRefreshService(
            database: database,
            ruleSnapshots: [tagRule, hideRule]
        ) { url, _ in
            .updated(
                ParsedFeed(sourceURL: url, title: "Feed", description: nil, siteURL: nil, articles: articles),
                FeedHTTPValidators()
            )
        }

        _ = try await service.refresh(feedID: "feed-1")
        return commits.count
    }
}
