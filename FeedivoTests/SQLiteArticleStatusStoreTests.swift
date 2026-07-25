import Foundation
import CloudKit
import Testing
@testable import Feedivo

private func seedArticleForStatusTest(
    database: FeedivoDatabase,
    articleID: String = "article-1",
    arrivedAt: Date = Date(timeIntervalSince1970: 100)
) throws -> String {
    let feedStore = FeedStore(database: database)
    let articleStore = ArticleStore(database: database)
    try feedStore.save(
        FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example")
    )
    return try articleStore.upsert(
        ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: articleID,
            title: "Article",
            arrivedAt: arrivedAt
        )
    )
}

struct SQLiteArticleStatusStoreTests {
    @Test func ensureStatusCreatesDefaultUnreadStatus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = ArticleStatusStore(database: database)
        let arrivedAt = Date(timeIntervalSince1970: 100)
        let articleID = try seedArticleForStatusTest(database: database, arrivedAt: arrivedAt)

        try store.ensureStatus(articleID: articleID, dateArrived: arrivedAt)

        let status = try store.status(articleID: articleID)

        #expect(status?.articleID == articleID)
        #expect(status?.isRead == false)
        #expect(status?.isStarred == false)
        #expect(status?.dateArrived == arrivedAt)
    }

    @Test func ensureStatusDoesNotOverwriteExistingStatus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = ArticleStatusStore(database: database)
        let articleID = try seedArticleForStatusTest(database: database)

        try store.ensureStatus(articleID: articleID, dateArrived: Date(timeIntervalSince1970: 100))
        try store.setRead(true, articleID: articleID, at: Date(timeIntervalSince1970: 200))
        try store.ensureStatus(articleID: articleID, dateArrived: Date(timeIntervalSince1970: 300))

        let status = try store.status(articleID: articleID)

        #expect(status?.isRead == true)
        #expect(status?.readAt == Date(timeIntervalSince1970: 200))
        #expect(status?.dateArrived == Date(timeIntervalSince1970: 100))
    }

    @Test func statusMutationsUpdateStatusValues() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let statusStore = ArticleStatusStore(database: database)
        let articleID = try seedArticleForStatusTest(database: database)

        try statusStore.ensureStatus(articleID: articleID, dateArrived: Date(timeIntervalSince1970: 100))
        try statusStore.setStarred(true, articleID: articleID, at: Date(timeIntervalSince1970: 400))
        try statusStore.setArchived(true, articleID: articleID, at: Date(timeIntervalSince1970: 500))
        try statusStore.setHidden(true, articleID: articleID, at: Date(timeIntervalSince1970: 600))

        let status = try statusStore.status(articleID: articleID)

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
        let articleID = try seedArticleForStatusTest(database: database)

        try store.ensureStatus(articleID: articleID, dateArrived: Date(timeIntervalSince1970: 100))
        try store.setRead(true, articleID: articleID, at: Date(timeIntervalSince1970: 200))
        try store.setRead(false, articleID: articleID, at: Date(timeIntervalSince1970: 300))

        let status = try store.status(articleID: articleID)

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

    @Test func readMutationUpdatesFeedUnreadCountSnapshot() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let articleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "article-1", title: "Article")
        )
        try feedStore.setUnreadCount(1, feedID: "feed-1")

        try statusStore.setRead(true, articleID: articleID, at: Date(timeIntervalSince1970: 1_000))
        let readFeed = try feedStore.feed(id: "feed-1")

        try statusStore.setRead(false, articleID: articleID, at: nil)
        let unreadFeed = try feedStore.feed(id: "feed-1")

        #expect(readFeed?.unreadCount == 0)
        #expect(unreadFeed?.unreadCount == 1)
    }

    @Test func readMutationUpdatesIdentityHistoryForReappearingArticles() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let originalID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "source-1",
                link: "https://example.com/original",
                title: "Stable Title"
            )
        )
        try statusStore.setRead(true, articleID: originalID, at: Date(timeIntervalSince1970: 1_000))

        let reappearingID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "source-2",
                link: "https://example.com/changed",
                title: "Stable Title"
            )
        )
        let reappearingStatus = try statusStore.status(articleID: reappearingID)

        #expect(reappearingID != originalID)
        #expect(reappearingStatus?.isRead == true)
        #expect(reappearingStatus?.readAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test func hiddenMutationUpdatesFeedUnreadCountSnapshot() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let articleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "article-1", title: "Article")
        )
        try feedStore.setUnreadCount(1, feedID: "feed-1")

        try statusStore.setHidden(true, articleID: articleID, at: Date(timeIntervalSince1970: 1_000))
        let hiddenFeed = try feedStore.feed(id: "feed-1")

        try statusStore.setHidden(false, articleID: articleID, at: nil)
        let visibleFeed = try feedStore.feed(id: "feed-1")

        #expect(hiddenFeed?.unreadCount == 0)
        #expect(visibleFeed?.unreadCount == 1)
    }

    @Test func setReadSetztStatusSyncUpdatedAt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = ArticleStatusStore(database: database)
        let articleID = try seedArticleForStatusTest(database: database)

        try store.setRead(true, articleID: articleID, at: Date())

        let status = try store.status(articleID: articleID)
        #expect(status?.statusSyncUpdatedAt != nil)
    }

    @Test func setReadSetztStatusSyncUpdatedAtAuchBeiRevertAufFalse() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = ArticleStatusStore(database: database)
        let articleID = try seedArticleForStatusTest(database: database)
        try store.setRead(true, articleID: articleID, at: Date())

        try store.setRead(false, articleID: articleID, at: nil)

        let status = try store.status(articleID: articleID)
        #expect(status?.isRead == false)
        #expect(status?.statusSyncUpdatedAt != nil)
    }

    @Test func setArchivedLaesstStatusSyncUpdatedAtUnveraendert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = ArticleStatusStore(database: database)
        let articleID = try seedArticleForStatusTest(database: database)

        try store.setArchived(true, articleID: articleID, at: Date())

        let status = try store.status(articleID: articleID)
        #expect(status?.statusSyncUpdatedAt == nil)
    }

    @Test func setReadEnqueuedPendingChangeWennSyncAktiv() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }
        let store = ArticleStatusStore(database: database)
        let articleID = try seedArticleForStatusTest(database: database)

        try store.setStarred(true, articleID: articleID, at: Date())

        // Der enqueuede recordName ist die syncStableID (nicht die lokale articleID) —
        // siehe iCloud Sync Phase 2b Stable-Identity-Fix, Task 12 Re-Review Finding 1.
        let status = try store.status(articleID: articleID)
        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        #expect(pending.contains { $0.id == status?.syncStableID && $0.recordType == CloudSyncArticleStatusMapping.recordType })
    }

    @Test func setReadEnqueuedKeinenPendingChangeWennSyncDeaktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey)
        let store = ArticleStatusStore(database: database)
        let articleID = try seedArticleForStatusTest(database: database)

        try store.setStarred(true, articleID: articleID, at: Date())

        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        #expect(pending.isEmpty)
    }

    /// Beweist den vollen Round-Trip, nicht nur dass irgendein Pending-Change enqueued wird:
    /// der enqueued `recordName` muss sich tatsächlich über
    /// `CloudSyncArticleStatusMapping.makeCKRecord(fromLocalID:existing:database:)` wieder zu
    /// einem echten `CKRecord` auflösen lassen — genau der Schritt, der in der ursprünglichen
    /// Task-12-Umsetzung kaputt war, weil `enqueuePendingSync` weiterhin die rohe lokale
    /// `articleID` statt der `syncStableID` enqueuete (iCloud Sync Phase 2b Stable-Identity-Fix,
    /// Re-Review-Finding 1).
    @Test func setReadEnqueuedPendingChangeDieSichZuEinemCKRecordAufloesenLaesst() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }
        let store = ArticleStatusStore(database: database)
        let articleID = try seedArticleForStatusTest(database: database)

        try store.setRead(true, articleID: articleID, at: Date())

        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        let pendingChange = try #require(pending.first { $0.recordType == CloudSyncArticleStatusMapping.recordType })
        let record = try CloudSyncArticleStatusMapping.makeCKRecord(fromLocalID: pendingChange.id, existing: nil, database: database)
        #expect(record != nil)
        #expect(record?["isRead"] as? Bool == true)
    }
}
