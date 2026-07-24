import Foundation
import CloudKit
import Testing
@testable import Feedivo

/// Tests für `CloudSyncFeedMapping` (iCloud Sync Phase 2a, Task 4). Deckt insbesondere ab,
/// dass NUR die syncbare Konfigurations-Teilmenge der `feeds`-Tabelle in ein `CKRecord`
/// gemappt wird — Refresh-Metadaten (`lastETag`, `unreadCount`, …) dürfen NIE im Record
/// landen (siehe Design-Spec-Begründung in `CloudSyncFeedMapping.swift`).
struct CloudSyncFeedMappingTests {
    @Test func makeCKRecordMapptNurKonfigurationsfelder() {
        let feed = FeedRecord(
            id: "feed-1",
            url: "https://example.com/feed",
            title: "Beispiel",
            websiteURL: "https://example.com",
            folderName: "Tech",
            sortIndex: 2,
            refreshIntervalMinutes: 60,
            isNotificationEnabled: true,
            articleRetentionOverridesGlobalSetting: true,
            articleRetentionIsEnabled: true,
            articleRetentionDays: 30,
            articleRetentionMinimumArticles: 10,
            articleRetentionIncludesProtectedArticles: true,
            lastETag: "sollte-nicht-synct-werden",
            unreadCount: 42
        )

        let record = CloudSyncFeedMapping.makeCKRecord(from: feed)

        #expect(record.recordType == "Feed")
        #expect(record["url"] as? String == "https://example.com/feed")
        #expect(record["folderName"] as? String == "Tech")
        #expect(record["refreshIntervalMinutes"] as? Int == 60)
        #expect(record["articleRetentionDays"] as? Int == 30)
        #expect(record.allKeys().contains("lastETag") == false)
        #expect(record.allKeys().contains("unreadCount") == false)
        #expect(record.allKeys().contains("lastRefreshedAt") == false)
        #expect(record.allKeys().contains("lastModified") == false)
        #expect(record.allKeys().contains("lastBodyHash") == false)
        #expect(record.allKeys().contains("lastHTTPStatusCode") == false)
    }

    @Test func makeCKRecordAktualisiertBestehendesRecordStattEinNeuesZuErzeugen() {
        let feed = FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Beispiel", sortIndex: 1, refreshIntervalMinutes: 45)
        let existing = CKRecord(recordType: "Feed", recordID: CloudSyncFeedMapping.recordID(forLocalID: "feed-1"))

        let record = CloudSyncFeedMapping.makeCKRecord(from: feed, existing: existing)

        #expect(record === existing)
        #expect(record["url"] as? String == "https://example.com/feed")
    }

    @Test func feedConfigFromCKRecordLiefertNilBeiFehlendenPflichtfeldern() {
        let ckRecord = CKRecord(recordType: "Feed", recordID: CloudSyncFeedMapping.recordID(forLocalID: "feed-1"))

        #expect(CloudSyncFeedMapping.feedConfig(from: ckRecord) == nil)
    }

    @Test func feedConfigFromCKRecordMapptZurueck() {
        let feed = FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Beispiel", sortIndex: 1, refreshIntervalMinutes: 45)
        let record = CloudSyncFeedMapping.makeCKRecord(from: feed)

        let config = CloudSyncFeedMapping.feedConfig(from: record)

        #expect(config?.url == "https://example.com/feed")
        #expect(config?.refreshIntervalMinutes == 45)
    }

    @Test func makeCKRecordFromLocalIDLiefertNilFuerUnbekannteID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let record = try CloudSyncFeedMapping.makeCKRecord(fromLocalID: "unbekannt", existing: nil, database: database)

        #expect(record == nil)
    }

    @Test func makeCKRecordFromLocalIDLaedtBestehendenFeed() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        try store.save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Beispiel", refreshIntervalMinutes: 45))

        let record = try CloudSyncFeedMapping.makeCKRecord(fromLocalID: "feed-1", existing: nil, database: database)

        #expect(record?["url"] as? String == "https://example.com/feed")
        #expect(record?["refreshIntervalMinutes"] as? Int == 45)
    }

    @Test func applyIncomingFuegtNeuenFeedEin() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feed = FeedRecord(id: "feed-neu", url: "https://neu.example/feed", title: "Neu", sortIndex: 3, refreshIntervalMinutes: 15)
        let record = CloudSyncFeedMapping.makeCKRecord(from: feed)

        try CloudSyncFeedMapping.applyIncoming(record, database: database)

        let loaded = try FeedStore(database: database).feed(id: "feed-neu")
        #expect(loaded?.url == "https://neu.example/feed")
        #expect(loaded?.title == "Neu")
        #expect(loaded?.sortIndex == 3)
        #expect(loaded?.refreshIntervalMinutes == 15)
    }

    @Test func applyIncomingAktualisiertBestehendenFeedOhneLokaleRefreshMetadatenZuBeruehren() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        try store.save(FeedRecord(
            id: "feed-1",
            url: "https://example.com/feed",
            title: "Alt",
            lastETag: "lokales-etag",
            unreadCount: 5
        ))

        let updatedFeed = FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Neu Betitelt", refreshIntervalMinutes: 90)
        let record = CloudSyncFeedMapping.makeCKRecord(from: updatedFeed)

        try CloudSyncFeedMapping.applyIncoming(record, database: database)

        let loaded = try store.feed(id: "feed-1")
        #expect(loaded?.title == "Neu Betitelt")
        #expect(loaded?.refreshIntervalMinutes == 90)
        #expect(loaded?.lastETag == "lokales-etag")
        #expect(loaded?.unreadCount == 5)
    }

    @Test func applyIncomingDeletionEntferntFeed() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        try store.save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Beispiel"))

        try CloudSyncFeedMapping.applyIncomingDeletion(recordID: CloudSyncFeedMapping.recordID(forLocalID: "feed-1"), database: database)

        #expect(try store.feed(id: "feed-1") == nil)
    }

    @Test func localUpdatedAtLiefertConfigUpdatedAtNichtUpdatedAt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        let configUpdatedAt = Date(timeIntervalSince1970: 1_000)
        try store.save(FeedRecord(
            id: "feed-1",
            url: "https://example.com/feed",
            title: "Beispiel",
            updatedAt: Date(timeIntervalSince1970: 9_999),
            configUpdatedAt: configUpdatedAt
        ))

        let localUpdatedAt = try CloudSyncFeedMapping.localUpdatedAt(forLocalID: "feed-1", database: database)

        #expect(localUpdatedAt == configUpdatedAt)
    }

    @Test func localUpdatedAtLiefertNilFuerUnbekannteID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let localUpdatedAt = try CloudSyncFeedMapping.localUpdatedAt(forLocalID: "unbekannt", database: database)

        #expect(localUpdatedAt == nil)
    }

    @Test func allLocalIDsListetAlleFeedsAuf() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://a.example.com", title: "A"))
        try FeedStore(database: database).save(FeedRecord(id: "feed-2", url: "https://b.example.com", title: "B"))

        let ids = try CloudSyncFeedMapping.allLocalIDs(database: database)

        #expect(Set(ids) == Set(["feed-1", "feed-2"]))
    }

    @Test func makeCKRecordFromLocalIDMitExistingBehaeltSystemfelder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Beispiel", refreshIntervalMinutes: 45))
        let existing = CKRecord(recordType: "Feed", recordID: CloudSyncFeedMapping.recordID(forLocalID: "feed-1"))

        let record = try CloudSyncFeedMapping.makeCKRecord(fromLocalID: "feed-1", existing: existing, database: database)

        #expect(record === existing)
        #expect(record?["url"] as? String == "https://example.com/feed")
    }
}
