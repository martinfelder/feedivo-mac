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

    @Test func updateRetentionSettingsMarkiertAlle5RetentionFelderAlsGeaendert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedStore(database: database)
        try store.save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Titel", sortIndex: 0))
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.updateRetentionSettings(id: "feed-1", overridesGlobal: true, isEnabled: true, days: 30, minimumArticles: 5, includesProtectedArticles: false)

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "feed-1")
        #expect(change?.changedFields?.count == 5)
        #expect(change?.changedFields?.contains("articleRetentionDays") == true)
    }
}
