import Foundation
import Testing
@testable import Feedivo

struct SQLiteArticleStatusStoreTests {
    @Test func ensureStatusCreatesDefaultUnreadStatus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = ArticleStatusStore(database: database)
        let arrivedAt = Date(timeIntervalSince1970: 100)

        try store.ensureStatus(articleID: "article-1", dateArrived: arrivedAt)

        let status = try store.status(articleID: "article-1")

        #expect(status?.articleID == "article-1")
        #expect(status?.isRead == false)
        #expect(status?.isStarred == false)
        #expect(status?.dateArrived == arrivedAt)
    }

    @Test func ensureStatusDoesNotOverwriteExistingStatus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = ArticleStatusStore(database: database)

        try store.ensureStatus(articleID: "article-1", dateArrived: Date(timeIntervalSince1970: 100))
        try store.setRead(true, articleID: "article-1", at: Date(timeIntervalSince1970: 200))
        try store.ensureStatus(articleID: "article-1", dateArrived: Date(timeIntervalSince1970: 300))

        let status = try store.status(articleID: "article-1")

        #expect(status?.isRead == true)
        #expect(status?.readAt == Date(timeIntervalSince1970: 200))
        #expect(status?.dateArrived == Date(timeIntervalSince1970: 100))
    }

    @Test func statusMutationsUpdateOnlyStatusTable() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let statusStore = ArticleStatusStore(database: database)

        try statusStore.ensureStatus(articleID: "article-1", dateArrived: Date(timeIntervalSince1970: 100))
        try statusStore.setStarred(true, articleID: "article-1", at: Date(timeIntervalSince1970: 400))
        try statusStore.setArchived(true, articleID: "article-1", at: Date(timeIntervalSince1970: 500))
        try statusStore.setHidden(true, articleID: "article-1", at: Date(timeIntervalSince1970: 600))

        let status = try statusStore.status(articleID: "article-1")

        #expect(status?.isStarred == true)
        #expect(status?.starredAt == Date(timeIntervalSince1970: 400))
        #expect(status?.isArchived == true)
        #expect(status?.archivedAt == Date(timeIntervalSince1970: 500))
        #expect(status?.isHidden == true)
        #expect(status?.hiddenAt == Date(timeIntervalSince1970: 600))
    }

    @Test func clearingStatusRemovesMatchingTimestamp() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = ArticleStatusStore(database: database)

        try store.ensureStatus(articleID: "article-1", dateArrived: Date(timeIntervalSince1970: 100))
        try store.setRead(true, articleID: "article-1", at: Date(timeIntervalSince1970: 200))
        try store.setRead(false, articleID: "article-1", at: Date(timeIntervalSince1970: 300))

        let status = try store.status(articleID: "article-1")

        #expect(status?.isRead == false)
        #expect(status?.readAt == nil)
    }

    @Test func unreadCountForFeedIgnoresReadAndHiddenArticles() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "unread", title: "Unread"))
        let readID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "read", title: "Read"))
        let hiddenID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "hidden", title: "Hidden"))

        try statusStore.setRead(true, articleID: readID, at: Date(timeIntervalSince1970: 1_000))
        try statusStore.setHidden(true, articleID: hiddenID, at: Date(timeIntervalSince1970: 2_000))

        let unreadCount = try statusStore.unreadCount(feedID: "feed-1")

        #expect(unreadCount == 1)
    }
}
