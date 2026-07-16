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
                            imageURL: "https://example.com/one.jpg"
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

        #expect(result.feedID == "feed-1")
        #expect(result.insertedArticleIDs.count == 2)
        #expect(result.updatedArticleIDs.isEmpty)
        #expect(result.unreadCount == 2)
        #expect(result.isNotModified == false)
        #expect(feed?.title == "Example")
        #expect(feed?.websiteURL == "https://example.com")
        #expect(feed?.unreadCount == 2)
        #expect(feed?.lastETag == "etag-1")
        #expect(articleCount == 2)
        #expect(firstArticle?.content == "Content one")
        #expect(logs.first?.level == "info")
        #expect(logs.first?.newArticleCount == 2)
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
        #expect(result.updatedArticleIDs.isEmpty)
        #expect(result.unreadCount == 1)
        #expect(result.isNotModified == true)
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
        #expect(result.updatedArticleIDs == [existingID])
        #expect(result.unreadCount == 0)
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
}
