import Foundation
import Testing
@testable import Feedivo

private func seedUnreadArticles(
    database: FeedivoDatabase,
    feedID: String,
    count: Int
) throws {
    let articleStore = ArticleStore(database: database)
    for index in 0..<count {
        _ = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: feedID,
                sourceID: "\(feedID)-article-\(index)",
                title: "Article \(index)"
            )
        )
    }
}

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
        try seedUnreadArticles(database: database, feedID: "b", count: 2)
        try seedUnreadArticles(database: database, feedID: "a", count: 1)

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
        try seedUnreadArticles(database: database, feedID: "unread", count: 3)

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

    @Test func sidebarSnapshotsMarkenFeedMitJuengstemErrorLogAlsFehlerhaft() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try store.save(FeedRecord(id: "feed-a", url: "https://a.example/feed.xml", title: "A"))
        try store.save(FeedRecord(id: "feed-b", url: "https://b.example/feed.xml", title: "B"))

        try logStore.append(FeedLogRecord(
            feedID: "feed-a",
            createdAt: Date(timeIntervalSince1970: 100),
            level: "error",
            message: "Netzwerkfehler"
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-b",
            createdAt: Date(timeIntervalSince1970: 100),
            level: "info",
            message: "3 neue Artikel"
        ))

        let snapshots = try store.sidebarFeeds()

        #expect(snapshots.first { $0.id == "feed-a" }?.hasRecentError == true)
        #expect(snapshots.first { $0.id == "feed-b" }?.hasRecentError == false)
    }

    @Test func sidebarSnapshotsLoeschenFehlerstatusNachErfolgreichemFolgeRefresh() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try store.save(FeedRecord(id: "feed-a", url: "https://a.example/feed.xml", title: "A"))

        try logStore.append(FeedLogRecord(
            feedID: "feed-a",
            createdAt: Date(timeIntervalSince1970: 100),
            level: "error",
            message: "Netzwerkfehler"
        ))
        try logStore.append(FeedLogRecord(
            feedID: "feed-a",
            createdAt: Date(timeIntervalSince1970: 200),
            level: "info",
            message: "2 neue Artikel"
        ))

        let snapshots = try store.sidebarFeeds()

        #expect(snapshots.first { $0.id == "feed-a" }?.hasRecentError == false)
    }

    @Test func sidebarSnapshotsOhneLogEintraegeSindNichtFehlerhaft() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)

        try store.save(FeedRecord(id: "feed-a", url: "https://a.example/feed.xml", title: "A"))

        let snapshots = try store.sidebarFeeds()

        #expect(snapshots.first { $0.id == "feed-a" }?.hasRecentError == false)
    }

    @Test func hasRecentErrorLiefertStatusFuerEinzelnenFeed() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try store.save(FeedRecord(id: "feed-a", url: "https://a.example/feed.xml", title: "A"))
        try logStore.append(FeedLogRecord(
            feedID: "feed-a",
            createdAt: Date(timeIntervalSince1970: 100),
            level: "error",
            message: "Netzwerkfehler"
        ))

        #expect(try store.hasRecentError(feedID: "feed-a") == true)
    }

    @Test func hasRecentErrorLiefertFalseFuerUnbekannteFeedID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)

        #expect(try store.hasRecentError(feedID: "unbekannt") == false)
    }

    @Test func sidebarFeedsSortiertNachSortIndexNichtNachTitel() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        try feedStore.save(
            FeedRecord(id: "feed-z", url: "https://z.example/feed.xml", title: "Zulu", sortIndex: 0)
        )
        try feedStore.save(
            FeedRecord(id: "feed-a", url: "https://a.example/feed.xml", title: "Alpha", sortIndex: 1)
        )

        let snapshots = try feedStore.sidebarFeeds()

        #expect(snapshots.map(\.id) == ["feed-z", "feed-a"])
    }

    @Test func moveFeedOrdnetGruppeNeuInnerhalbDesselbenOrdners() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        try feedStore.save(
            FeedRecord(id: "feed-a", url: "https://a.example/feed.xml", title: "A", folderName: "Tech", sortIndex: 0)
        )
        try feedStore.save(
            FeedRecord(id: "feed-b", url: "https://b.example/feed.xml", title: "B", folderName: "Tech", sortIndex: 1)
        )
        try feedStore.save(
            FeedRecord(id: "feed-c", url: "https://c.example/feed.xml", title: "C", folderName: "Tech", sortIndex: 2)
        )

        try feedStore.moveFeed(id: "feed-c", toFolderName: "Tech", targetIndex: 0)

        let orderedIDs = try feedStore.feeds()
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.id)
        #expect(orderedIDs == ["feed-c", "feed-a", "feed-b"])
    }

    @Test func moveFeedWeistNeuenOrdnerZuUndReihtAmEndeEin() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        try feedStore.save(
            FeedRecord(id: "feed-a", url: "https://a.example/feed.xml", title: "A", folderName: "Tech", sortIndex: 0)
        )
        try feedStore.save(
            FeedRecord(id: "feed-b", url: "https://b.example/feed.xml", title: "B", folderName: "News", sortIndex: 0)
        )

        try feedStore.moveFeed(id: "feed-b", toFolderName: "Tech", targetIndex: 1)

        let feedB = try feedStore.feed(id: "feed-b")
        #expect(feedB?.folderName == "Tech")
        #expect(feedB?.sortIndex == 1)
        let feedA = try feedStore.feed(id: "feed-a")
        #expect(feedA?.sortIndex == 0)
    }

    @Test func moveFeedZuOhneOrdnerSetztFolderNameAufNil() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        try feedStore.save(
            FeedRecord(id: "feed-a", url: "https://a.example/feed.xml", title: "A", folderName: "Tech", sortIndex: 0)
        )

        try feedStore.moveFeed(id: "feed-a", toFolderName: nil, targetIndex: 0)

        let feed = try feedStore.feed(id: "feed-a")
        #expect(feed?.folderName == nil)
        #expect(feed?.sortIndex == 0)
    }

    @Test func moveFeedKlemmtTargetIndexAufGueltigenBereich() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        try feedStore.save(
            FeedRecord(id: "feed-a", url: "https://a.example/feed.xml", title: "A", sortIndex: 0)
        )
        try feedStore.save(
            FeedRecord(id: "feed-b", url: "https://b.example/feed.xml", title: "B", sortIndex: 1)
        )

        try feedStore.moveFeed(id: "feed-a", toFolderName: nil, targetIndex: 999)

        let orderedIDs = try feedStore.feeds()
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.id)
        #expect(orderedIDs == ["feed-b", "feed-a"])
    }

    // MARK: - iCloud Sync (Phase 2a, Task 4)

    @Test func saveMarkiertFeedAlsPendingSyncWennAktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }
        let store = FeedStore(database: database)

        try store.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Beispiel"))

        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        #expect(pending.map(\.id) == ["feed-1"])
    }

    @Test func saveMarkiertNichtsWennSyncDeaktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey)
        let store = FeedStore(database: database)

        try store.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Beispiel"))

        #expect(try CloudSyncPendingChangeStore(database: database).pendingChanges().isEmpty)
    }

    @Test func deleteMarkiertFeedAlsPendingDeleteWennAktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        try store.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Beispiel"))

        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.delete(id: "feed-1")

        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        #expect(pending.map(\.id) == ["feed-1"])
        #expect(pending.first?.changeType == .delete)
    }

    @Test func moveFeedMarkiertAlleUmsortiertenFeedsAlsPendingSync() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        let store = FeedStore(database: database)
        let feedA = FeedRecord(id: "feed-a", url: "https://a.example.com", title: "A", sortIndex: 0)
        let feedB = FeedRecord(id: "feed-b", url: "https://b.example.com", title: "B", sortIndex: 1)
        try store.save(feedA)
        try store.save(feedB)

        try store.moveFeed(id: "feed-b", toFolderName: nil, targetIndex: 0)

        let pendingChangeStore = CloudSyncPendingChangeStore(database: database)
        let pendingIDs = Set(try pendingChangeStore.pendingChanges().map(\.id))
        #expect(pendingIDs.contains("feed-a"))
        #expect(pendingIDs.contains("feed-b"))
    }

    @Test func updateAfterRefreshMarkiertFeedNichtAlsPendingSync() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        try store.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Beispiel"))

        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.updateAfterRefresh(
            feedID: "feed-1",
            title: "Neuer Titel",
            websiteURL: nil,
            validators: FeedHTTPValidators(eTag: "etag-1", lastModified: nil, contentHash: nil, lastStatusCode: 200),
            unreadCount: 3,
            refreshedAt: Date()
        )

        #expect(try CloudSyncPendingChangeStore(database: database).pendingChanges().isEmpty)
    }

    @Test func setUnreadCountMarkiertFeedNichtAlsPendingSync() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        try store.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Beispiel"))

        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.setUnreadCount(5, feedID: "feed-1")

        #expect(try CloudSyncPendingChangeStore(database: database).pendingChanges().isEmpty)
    }
}
