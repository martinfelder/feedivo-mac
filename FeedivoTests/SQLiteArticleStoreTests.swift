import Foundation
import GRDB
import Testing
@testable import Feedivo

struct SQLiteArticleStoreTests {
    @Test func upsertInsertsArticleAndCreatesStatus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let publishedAt = Date(timeIntervalSince1970: 1_000)
        let arrivedAt = Date(timeIntervalSince1970: 2_000)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let articleID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "source-1",
                link: "https://example.com/articles/1",
                title: "First Article",
                summary: "Summary",
                content: "Full content",
                imageURL: "https://example.com/image.jpg",
                author: "Author",
                publishedAt: publishedAt,
                arrivedAt: arrivedAt,
                estimatedReadingMinutes: 4
            )
        )

        let readerArticle = try articleStore.readerArticle(id: articleID)
        let status = try statusStore.status(articleID: articleID)

        #expect(readerArticle?.title == "First Article")
        #expect(readerArticle?.feedTitle == "Example")
        #expect(readerArticle?.content == "Full content")
        #expect(status?.isRead == false)
    }

    @Test func upsertUpdatesExistingArticleBySourceIDWithoutOverwritingStatus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let originalArrivedAt = Date(timeIntervalSince1970: 2_000)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let firstID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "source-1",
                link: "https://example.com/articles/old",
                title: "Old Title",
                summary: "Old summary",
                content: "Old content",
                publishedAt: Date(timeIntervalSince1970: 1_000),
                arrivedAt: originalArrivedAt,
                estimatedReadingMinutes: 3
            )
        )
        try statusStore.setRead(true, articleID: firstID, at: Date(timeIntervalSince1970: 3_000))

        let secondID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "source-1",
                link: "https://example.com/articles/new",
                title: "New Title",
                summary: "New summary",
                content: "New content",
                publishedAt: Date(timeIntervalSince1970: 4_000),
                arrivedAt: Date(timeIntervalSince1970: 5_000),
                estimatedReadingMinutes: 7
            )
        )

        let readerArticle = try articleStore.readerArticle(id: firstID)
        let status = try statusStore.status(articleID: firstID)

        #expect(secondID == firstID)
        #expect(readerArticle?.title == "New Title")
        #expect(readerArticle?.summary == "New summary")
        #expect(readerArticle?.content == "New content")
        #expect(readerArticle?.estimatedReadingMinutes == 7)
        #expect(status?.isRead == true)
        #expect(status?.dateArrived == originalArrivedAt)
        #expect(readerArticle?.arrivedAt == originalArrivedAt)
    }

    @Test func upsertFallsBackToLinkWhenSourceIDIsMissing() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let firstID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: nil,
                link: "https://example.com/articles/1",
                title: "Old Title"
            )
        )
        let secondID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: nil,
                link: "https://example.com/articles/1",
                title: "New Title"
            )
        )

        let readerArticle = try articleStore.readerArticle(id: firstID)

        #expect(secondID == firstID)
        #expect(readerArticle?.title == "New Title")
    }

    @Test func upsertPersistsLaterSourceIDAfterLinkFallbackMatch() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let firstID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: nil,
                link: "https://example.com/articles/original",
                title: "Original"
            )
        )
        let secondID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "source-1",
                link: "https://example.com/articles/original",
                title: "With Source"
            )
        )
        let thirdID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "source-1",
                link: "https://example.com/articles/changed",
                title: "Changed Link"
            )
        )

        let readerArticle = try articleStore.readerArticle(id: firstID)

        #expect(secondID == firstID)
        #expect(thirdID == firstID)
        #expect(readerArticle?.link == "https://example.com/articles/changed")
        #expect(readerArticle?.title == "Changed Link")
    }

    @Test func readerArticleUsesArticleArrivedAtInsteadOfStatusDateArrived() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let articleArrivedAt = Date(timeIntervalSince1970: 2_000)
        let statusDateArrived = Date(timeIntervalSince1970: 9_000)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let articleID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "source-1",
                link: "https://example.com/articles/1",
                title: "First Article",
                arrivedAt: articleArrivedAt
            )
        )
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE article_statuses
                    SET dateArrived = ?
                    WHERE articleID = ?
                    """,
                arguments: [statusDateArrived, articleID]
            )
        }

        let readerArticle = try articleStore.readerArticle(id: articleID)
        let status = try statusStore.status(articleID: articleID)

        #expect(readerArticle?.arrivedAt == articleArrivedAt)
        #expect(status?.dateArrived == statusDateArrived)
    }

    @Test func upsertIgnoresWhitespaceSourceIDForExistingMatch() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let firstID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "source-1",
                link: "https://example.com/articles/1",
                title: "Old Title"
            )
        )
        let secondID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "   ",
                link: "https://example.com/articles/2",
                title: "New Title"
            )
        )

        #expect(secondID != firstID)
    }

    @Test func batchUpsertReturnsInsertedAndUpdatedIDs() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let existingID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "existing", title: "Old Title")
        )

        let result = try articleStore.upsert([
            ArticleUpsertInput(feedID: "feed-1", sourceID: "existing", title: "Updated Title"),
            ArticleUpsertInput(feedID: "feed-1", sourceID: "new", title: "New Title")
        ])

        let updatedArticle = try articleStore.readerArticle(id: existingID)
        let articleCount = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM articles") ?? 0
        }

        #expect(result.updatedArticleIDs == [existingID])
        #expect(result.insertedArticleIDs.count == 1)
        #expect(result.articleIDs.count == 2)
        #expect(updatedArticle?.title == "Updated Title")
        #expect(articleCount == 2)
    }

    @Test func batchUpsertRunsInOneTransactionAndPreservesStatus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let originalArrivedAt = Date(timeIntervalSince1970: 1_000)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let articleID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "existing",
                title: "Old Title",
                arrivedAt: originalArrivedAt
            )
        )
        try statusStore.setRead(true, articleID: articleID, at: Date(timeIntervalSince1970: 2_000))

        let result = try articleStore.upsert([
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "existing",
                title: "Updated Title",
                arrivedAt: Date(timeIntervalSince1970: 3_000)
            )
        ])

        let status = try statusStore.status(articleID: articleID)
        let readerArticle = try articleStore.readerArticle(id: articleID)

        #expect(result.insertedArticleIDs.isEmpty)
        #expect(result.updatedArticleIDs == [articleID])
        #expect(status?.isRead == true)
        #expect(status?.dateArrived == originalArrivedAt)
        #expect(readerArticle?.arrivedAt == originalArrivedAt)
    }
}
