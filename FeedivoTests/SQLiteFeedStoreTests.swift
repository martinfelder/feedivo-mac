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

    @Test func duplicateURLIsRejectedByUniqueIndex() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)

        try store.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "One"))

        #expect(throws: Error.self) {
            try store.save(FeedRecord(id: "feed-2", url: "https://example.com/feed.xml", title: "Two"))
        }
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
}
