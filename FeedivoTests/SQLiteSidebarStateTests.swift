import Foundation
import SwiftData
import Testing
@testable import Feedivo

struct SQLiteSidebarStateTests {
    @MainActor
    @Test func loadReadsSnapshotsAndTotalUnreadCount() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        try store.save(FeedRecord(id: "feed-1", url: "https://one.example/feed.xml", title: "One", unreadCount: 2))
        try store.save(FeedRecord(id: "feed-2", url: "https://two.example/feed.xml", title: "Two", unreadCount: 3))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "one-a", title: "One A"))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-1", sourceID: "one-b", title: "One B"))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-2", sourceID: "two-a", title: "Two A"))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-2", sourceID: "two-b", title: "Two B"))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: "feed-2", sourceID: "two-c", title: "Two C"))
        let state = SQLiteSidebarState()

        state.load(database: database, showsReadFeeds: true)

        #expect(state.snapshots.map(\.id) == ["feed-1", "feed-2"])
        #expect(state.totalUnreadCount == 5)
        #expect(state.errorMessage == nil)
    }

    @MainActor
    @Test func loadIgnoresStaleFeedUnreadCountCache() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        try feedStore.save(FeedRecord(id: "feed-1", url: "https://one.example/feed.xml", title: "One", unreadCount: 9))
        let articleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "article-1", title: "Gelesen")
        )
        try statusStore.setRead(true, articleID: articleID, at: Date(timeIntervalSince1970: 1_000))
        try feedStore.setUnreadCount(9, feedID: "feed-1")
        let state = SQLiteSidebarState()

        state.load(database: database, showsReadFeeds: true)

        #expect(state.snapshot(forFeedID: "feed-1")?.unreadCount == 0)
        #expect(state.totalUnreadCount == 0)
        #expect(state.smartFolderBadgeSnapshot.unread == 0)
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
    @Test func visibleSnapshotsFollowSQLiteVisibility() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let readFeedID = UUID().uuidString
        let unreadFeedID = UUID().uuidString
        try store.save(FeedRecord(id: readFeedID, url: "https://read.example/feed.xml", title: "Read", unreadCount: 0))
        try store.save(FeedRecord(id: unreadFeedID, url: "https://unread.example/feed.xml", title: "Unread", unreadCount: 4))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: unreadFeedID, sourceID: "unread-a", title: "Unread A"))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: unreadFeedID, sourceID: "unread-b", title: "Unread B"))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: unreadFeedID, sourceID: "unread-c", title: "Unread C"))
        _ = try articleStore.upsert(ArticleUpsertInput(feedID: unreadFeedID, sourceID: "unread-d", title: "Unread D"))
        let state = SQLiteSidebarState()

        state.load(database: database, showsReadFeeds: false)

        // Bei showsReadFeeds=false darf nur der ungelesene Feed in den Snapshots
        // auftauchen; die Sichtbarkeit ist vollständig in SQLite geklärt.
        #expect(state.snapshots.map(\.id) == [unreadFeedID])
        #expect(state.snapshot(forFeedID: unreadFeedID)?.unreadCount == 4)
        #expect(state.snapshot(forFeedID: readFeedID) == nil)
    }

    @MainActor
    @Test func loadComputesMixedCountsForAllArticlesAndTodayDefaultFolders() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let smartFolderStore = SQLiteSmartFolderStore(database: database)
        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        try smartFolderStore.save(
            SmartFolderRecord(id: "smart-all", name: "Alle Artikel", defaultKey: "all"),
            conditions: []
        )
        try smartFolderStore.save(
            SmartFolderRecord(id: "smart-today", name: "Heute", defaultKey: "today"),
            conditions: [
                SmartFolderConditionRecord(
                    id: "condition-today",
                    smartFolderID: "smart-today",
                    field: SmartFolderConditionField.date.rawValue,
                    conditionOperator: SmartFolderConditionOperator.is.rawValue,
                    value: SmartFolderDateValue.today.rawValue
                )
            ]
        )

        let now = Date()
        let longAgo = now.addingTimeInterval(-10 * 24 * 60 * 60)
        let readTodayID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "read-today", title: "Gelesen heute", publishedAt: now, arrivedAt: now)
        )
        _ = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "unread-today", title: "Ungelesen heute", publishedAt: now, arrivedAt: now)
        )
        let oldID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "old", title: "Alt", publishedAt: longAgo, arrivedAt: now)
        )
        try statusStore.setRead(true, articleID: readTodayID, at: now)
        try statusStore.setRead(true, articleID: oldID, at: now)

        let state = SQLiteSidebarState()

        state.load(database: database, showsReadFeeds: true)

        #expect(state.mixedCountsByDefaultKey["all"]?.read == 2)
        #expect(state.mixedCountsByDefaultKey["all"]?.unread == 1)
        #expect(state.mixedCountsByDefaultKey["today"]?.read == 1)
        #expect(state.mixedCountsByDefaultKey["today"]?.unread == 1)
    }
}
