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
    @Test func loadReadsTagSnapshotsForSidebarBadges() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let tagStore = TagStore(database: database)
        try feedStore.save(FeedRecord(id: "feed-1", url: "https://one.example/feed.xml", title: "One"))
        let articleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "article-1", title: "Artikel")
        )
        try tagStore.save(TagRecord(id: "tag-1", name: "Swift", colorHex: "#ff0000"))
        try tagStore.assignTag(tagID: "tag-1", toArticleID: articleID, at: Date(timeIntervalSince1970: 100))
        let state = SQLiteSidebarState()

        state.load(database: database, showsReadFeeds: true)

        #expect(state.tagSnapshots.map(\.id) == ["tag-1"])
        #expect(state.tagSnapshot(id: "tag-1")?.articleCount == 1)
    }

    @MainActor
    @Test func loadReadsSmartFolderBadgeSnapshotFromSQLiteStatuses() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        try feedStore.save(FeedRecord(id: "feed-1", url: "https://one.example/feed.xml", title: "One", unreadCount: 2))
        let starredID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "article-1", title: "Stern")
        )
        let archivedID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "article-2", title: "Archiv")
        )
        let hiddenID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "article-3", title: "Versteckt")
        )
        try statusStore.setStarred(true, articleID: starredID, at: Date(timeIntervalSince1970: 100))
        try statusStore.setArchived(true, articleID: archivedID, at: Date(timeIntervalSince1970: 100))
        try statusStore.setHidden(true, articleID: hiddenID, at: Date(timeIntervalSince1970: 100))
        let state = SQLiteSidebarState()

        state.load(database: database, showsReadFeeds: true)

        #expect(state.smartFolderBadgeSnapshot.unread == 2)
        #expect(state.smartFolderBadgeSnapshot.starred == 1)
        #expect(state.smartFolderBadgeSnapshot.hidden == 1)
        #expect(state.smartFolderBadgeSnapshot.saved == 2)
    }

    @MainActor
    @Test func loadReadsFeedFoldersAndSmartFolderSnapshots() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedFolderStore(database: database).save(FeedFolderRecord(id: "folder-1", name: "Technik"))
        try SQLiteSmartFolderStore(database: database).save(
            SmartFolderRecord(
                id: "smart-1",
                name: "Ungelesen",
                matchMode: RuleMatchMode.all.rawValue,
                isShownInSidebar: true,
                isDefault: true,
                sortOrder: 0,
                defaultKey: "unread",
                iconName: "circle.fill",
                colorHex: "#22C55E"
            ),
            conditions: [
                SmartFolderConditionRecord(
                    id: "condition-1",
                    smartFolderID: "smart-1",
                    field: SmartFolderConditionField.status.rawValue,
                    conditionOperator: SmartFolderConditionOperator.is.rawValue,
                    value: SmartFolderStatusValue.unread.rawValue
                )
            ]
        )
        let state = SQLiteSidebarState()

        state.load(database: database, showsReadFeeds: true)

        #expect(state.feedFolders.map(\.name) == ["Technik"])
        #expect(state.smartFolderSnapshots.map(\.id) == ["smart-1"])
        #expect(state.smartFolderSnapshots.first?.conditions.first?.value == SmartFolderStatusValue.unread.rawValue)
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
