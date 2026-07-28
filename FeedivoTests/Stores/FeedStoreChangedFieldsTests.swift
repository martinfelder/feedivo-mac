import Foundation
import Testing
@testable import Feedivo

struct FeedStoreChangedFieldsTests {
    @Test func renameFeedMarkiertNurTitleAlsGeaendert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        try store.save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Alt", sortIndex: 0))
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.renameFeed(id: "feed-1", displayTitle: "Neu")

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "feed-1")
        #expect(change?.changedFields == ["title"])
    }

    @Test func moveFeedMarkiertNurSortIndexAlsGeaendert() throws {
        // Cleanup vor dem Test
        UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        try store.save(FeedRecord(id: "feed-a", url: "https://a.example.com", title: "A", sortIndex: 0))
        try store.save(FeedRecord(id: "feed-b", url: "https://b.example.com", title: "B", sortIndex: 1))
        try store.save(FeedRecord(id: "feed-c", url: "https://c.example.com", title: "C", sortIndex: 2))
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)

        try store.moveFeed(id: "feed-b", toFolderName: nil, targetIndex: 0)

        let changeA = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "feed-a")
        #expect(changeA?.changedFields == ["sortIndex"])

        let changeB = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "feed-b")
        #expect(changeB?.changedFields == ["sortIndex"])

        let changeC = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "feed-c")
        #expect(changeC?.changedFields == ["sortIndex"])
    }

    @Test func updateRetentionSettingsMarkiertAlle5RetentionFelderAlsGeaendert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        try store.save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Titel", sortIndex: 0))
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.updateRetentionSettings(id: "feed-1", overridesGlobal: true, isEnabled: true, days: 30, minimumArticles: 5, includesProtectedArticles: false)

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "feed-1")
        let expectedFields = [
            "articleRetentionOverridesGlobalSetting",
            "articleRetentionIsEnabled",
            "articleRetentionDays",
            "articleRetentionMinimumArticles",
            "articleRetentionIncludesProtectedArticles"
        ]
        #expect(change?.changedFields == expectedFields)
    }
}
