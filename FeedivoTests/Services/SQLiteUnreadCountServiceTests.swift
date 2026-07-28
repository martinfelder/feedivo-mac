import Foundation
import Testing
@testable import Feedivo

struct SQLiteUnreadCountServiceTests {
    @Test func unreadCountZaehltNurUngeleseneSichtbareArtikel() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let unreadCountService = SQLiteUnreadCountService(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "unread", title: "Unread"))
        let readID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "read", title: "Read"))
        let hiddenID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "hidden", title: "Hidden"))

        try statusStore.setRead(true, articleID: readID, at: Date(timeIntervalSince1970: 1_000))
        try statusStore.setHidden(true, articleID: hiddenID, at: Date(timeIntervalSince1970: 2_000))

        let unreadCount = try unreadCountService.unreadCount(feedID: "feed-1")

        #expect(unreadCount == 1)
    }

    @Test func rebuildFeedUnreadCountKorrigiertGespeichertenFeedZaehler() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let unreadCountService = SQLiteUnreadCountService(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example", unreadCount: 99))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "unread", title: "Unread"))
        let readID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "read", title: "Read"))
        try statusStore.setRead(true, articleID: readID, at: Date(timeIntervalSince1970: 1_000))

        let rebuiltCount = try unreadCountService.rebuildFeedUnreadCount(feedID: "feed-1")
        let feed = try feedStore.feed(id: "feed-1")

        #expect(rebuiltCount == 1)
        #expect(feed?.unreadCount == 1)
    }

    @Test func rebuildAllFeedUnreadCountsKorrigiertAlleFeedZaehler() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let unreadCountService = SQLiteUnreadCountService(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://one.example/feed.xml", title: "One", unreadCount: 50))
        try feedStore.save(FeedRecord(id: "feed-2", url: "https://two.example/feed.xml", title: "Two", unreadCount: 50))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "one-unread", title: "One Unread"))
        let feedOneReadID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "one-read", title: "One Read"))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-2", sourceID: "two-unread-a", title: "Two Unread A"))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-2", sourceID: "two-unread-b", title: "Two Unread B"))
        try statusStore.setRead(true, articleID: feedOneReadID, at: Date(timeIntervalSince1970: 1_000))

        let rebuiltCounts = try unreadCountService.rebuildAllFeedUnreadCounts()
        let firstFeed = try feedStore.feed(id: "feed-1")
        let secondFeed = try feedStore.feed(id: "feed-2")

        #expect(rebuiltCounts == ["feed-1": 1, "feed-2": 2])
        #expect(firstFeed?.unreadCount == 1)
        #expect(secondFeed?.unreadCount == 2)
    }

    @Test func totalUnreadCountIgnoriertGespeicherteFeedZaehler() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let unreadCountService = SQLiteUnreadCountService(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://one.example/feed.xml", title: "One", unreadCount: 99))
        try feedStore.save(FeedRecord(id: "feed-2", url: "https://two.example/feed.xml", title: "Two", unreadCount: 99))
        let readID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "read", title: "Read"))
        let hiddenID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "hidden", title: "Hidden"))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-2", sourceID: "unread", title: "Unread"))
        try statusStore.setRead(true, articleID: readID, at: Date(timeIntervalSince1970: 1_000))
        try statusStore.setHidden(true, articleID: hiddenID, at: Date(timeIntervalSince1970: 2_000))

        let totalUnreadCount = try unreadCountService.totalUnreadCount()

        #expect(totalUnreadCount == 1)
    }

    @Test func sidebarSmartFolderBadgeSnapshotKommtAusZentralemService() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let unreadCountService = SQLiteUnreadCountService(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example", unreadCount: 2))
        let starredID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "starred", title: "Starred"))
        let archivedID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "archived", title: "Archived"))
        let hiddenID = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "hidden", title: "Hidden"))

        try statusStore.setStarred(true, articleID: starredID, at: Date(timeIntervalSince1970: 100))
        try statusStore.setArchived(true, articleID: archivedID, at: Date(timeIntervalSince1970: 200))
        try statusStore.setHidden(true, articleID: hiddenID, at: Date(timeIntervalSince1970: 300))

        let snapshot = try unreadCountService.sidebarSmartFolderBadgeSnapshot()

        #expect(snapshot.unread == 2)
        #expect(snapshot.starred == 1)
        #expect(snapshot.hidden == 1)
        #expect(snapshot.saved == 2)
    }
}
