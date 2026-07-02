import Foundation
import SwiftData
import Testing
@testable import Feedivo

struct SQLiteSidebarStateTests {
    @MainActor
    @Test func loadReadsSnapshotsAndTotalUnreadCount() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        try store.save(FeedRecord(id: "feed-1", url: "https://one.example/feed.xml", title: "One", unreadCount: 2))
        try store.save(FeedRecord(id: "feed-2", url: "https://two.example/feed.xml", title: "Two", unreadCount: 3))
        let state = SQLiteSidebarState()

        state.load(database: database, showsReadFeeds: true)

        #expect(state.snapshots.map(\.id) == ["feed-1", "feed-2"])
        #expect(state.totalUnreadCount == 5)
        #expect(state.errorMessage == nil)
    }

    @MainActor
    @Test func visibleSwiftDataFeedsFollowSQLiteVisibility() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        let readFeed = Feed(url: "https://read.example/feed.xml", title: "Read")
        let unreadFeed = Feed(url: "https://unread.example/feed.xml", title: "Unread")
        try store.save(FeedRecord(id: readFeed.id.uuidString, url: readFeed.url, title: readFeed.title, unreadCount: 0))
        try store.save(FeedRecord(id: unreadFeed.id.uuidString, url: unreadFeed.url, title: unreadFeed.title, unreadCount: 4))
        let state = SQLiteSidebarState()

        state.load(database: database, showsReadFeeds: false)
        let visibleFeeds = state.visibleFeeds(
            from: [readFeed, unreadFeed],
            showsReadFeeds: false
        )

        #expect(visibleFeeds.map(\.id) == [unreadFeed.id])
        #expect(state.snapshot(for: unreadFeed)?.unreadCount == 4)
    }
}
