import Foundation
import Testing
@testable import Feedivo

struct SQLiteFeedStoreTests {
    @Test func saveFeedPersistsAndUpdatesByID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        let now = Date(timeIntervalSince1970: 1_000)

        var feed = FeedRecord(
            id: "feed-1",
            url: "https://example.com/feed.xml",
            title: "Example",
            createdAt: now,
            updatedAt: now
        )
        try store.save(feed)

        feed.title = "Updated"
        feed.unreadCount = 7
        feed.updatedAt = Date(timeIntervalSince1970: 2_000)
        try store.save(feed)

        let loaded = try store.feed(id: "feed-1")

        #expect(loaded?.title == "Updated")
        #expect(loaded?.unreadCount == 7)
    }

    @Test func duplicateURLsAreAllowed() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)

        try store.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "One"))
        try store.save(FeedRecord(id: "feed-2", url: "https://example.com/feed.xml", title: "Two"))

        let feeds = try store.feeds()

        #expect(feeds.count == 2)
        #expect(Set(feeds.map(\.id)) == ["feed-1", "feed-2"])
        #expect(feeds.map(\.url) == ["https://example.com/feed.xml", "https://example.com/feed.xml"])
    }

    @Test func sidebarSnapshotsAreSortedByTitle() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)

        try store.save(FeedRecord(id: "b", url: "https://b.example/feed.xml", title: "Beta", unreadCount: 2))
        try store.save(FeedRecord(id: "a", url: "https://a.example/feed.xml", title: "Alpha", unreadCount: 1))

        let snapshots = try store.sidebarFeeds()

        #expect(snapshots.map(\.id) == ["a", "b"])
        #expect(snapshots.first?.unreadCount == 1)
    }

    @Test func sidebarSnapshotsUseDeterministicTieBreakerForMatchingTitles() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)

        try store.save(FeedRecord(id: "b", url: "https://b.example/feed.xml", title: "Alpha"))
        try store.save(FeedRecord(id: "a", url: "https://a.example/feed.xml", title: "Alpha"))

        let snapshots = try store.sidebarFeeds()

        #expect(snapshots.map(\.id) == ["a", "b"])
    }

    @Test func sidebarSnapshotsCanHideReadFeeds() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)

        try store.save(FeedRecord(id: "read", url: "https://read.example/feed.xml", title: "Read", unreadCount: 0))
        try store.save(FeedRecord(id: "unread", url: "https://unread.example/feed.xml", title: "Unread", unreadCount: 3))

        let visible = try store.sidebarFeeds(showsReadFeeds: false)

        #expect(visible.map(\.id) == ["unread"])
    }

    @Test func opmlExportFeedsIncludeFoldersWebsiteAndFeedTags() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let tagStore = TagStore(database: database)

        try feedStore.save(FeedRecord(
            id: "feed-1",
            url: "https://example.com/feed.xml",
            title: "Example",
            websiteURL: "https://example.com",
            folderName: "News"
        ))
        try tagStore.save(TagRecord(id: "tag-1", name: "Swift", colorHex: "#ff0000"))
        try tagStore.save(TagRecord(id: "tag-2", name: "RSS", colorHex: "#00ff00"))
        try tagStore.assignTag(tagID: "tag-1", toFeedID: "feed-1", at: Date(timeIntervalSince1970: 1_000))
        try tagStore.assignTag(tagID: "tag-2", toFeedID: "feed-1", at: Date(timeIntervalSince1970: 1_000))

        let feeds = try feedStore.opmlFeedsForExport()

        #expect(feeds == [
            OPMLFeed(
                title: "Example",
                xmlURL: "https://example.com/feed.xml",
                htmlURL: "https://example.com",
                folderName: "News",
                tagNames: ["RSS", "Swift"]
            )
        ])
    }

    @Test func feedByURLFindsExistingRecordLegacyMehrdeutig() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)

        try store.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let loaded = try store.feed(url: "https://example.com/feed.xml")

        #expect(loaded?.id == "feed-1")
        #expect(loaded?.title == "Example")
    }

    @Test func updateAfterRefreshStoresValidatorsAndUnreadCount() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        let refreshedAt = Date(timeIntervalSince1970: 5_000)

        try store.save(FeedRecord(
            id: "feed-1",
            url: "https://example.com/feed.xml",
            title: "Old Title",
            folderName: "News"
        ))

        try store.updateAfterRefresh(
            feedID: "feed-1",
            title: "New Title",
            websiteURL: "https://example.com",
            validators: FeedHTTPValidators(
                eTag: "etag-1",
                lastModified: "Thu, 02 Jul 2026 17:00:00 GMT",
                contentHash: "hash-1",
                lastStatusCode: 200
            ),
            unreadCount: 7,
            refreshedAt: refreshedAt
        )

        let loaded = try store.feed(id: "feed-1")

        #expect(loaded?.title == "New Title")
        #expect(loaded?.websiteURL == "https://example.com")
        #expect(loaded?.folderName == "News")
        #expect(loaded?.lastETag == "etag-1")
        #expect(loaded?.lastModified == "Thu, 02 Jul 2026 17:00:00 GMT")
        #expect(loaded?.lastBodyHash == "hash-1")
        #expect(loaded?.lastHTTPStatusCode == 200)
        #expect(loaded?.unreadCount == 7)
        #expect(loaded?.lastRefreshedAt == refreshedAt)
    }
}
