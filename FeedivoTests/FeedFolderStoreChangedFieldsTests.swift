import Foundation
import Testing
@testable import Feedivo

struct FeedFolderStoreChangedFieldsTests {
    @Test func renameFolderMarkiertNurNameAlsGeaendert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedFolderStore(database: database)
        try store.save(FeedFolderRecord(id: "folder-1", name: "Alt", sortIndex: 0, createdAt: Date(), updatedAt: Date()))
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.renameFolder(from: "Alt", to: "Neu")

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-1")
        #expect(change?.changedFields == ["name"])
    }

    @Test func moveFolderMarkiertNurSortIndexAlsGeaendert() throws {
        // Cleanup vor dem Test
        UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedFolderStore(database: database)
        try store.save(FeedFolderRecord(id: "folder-a", name: "Alpha", sortIndex: 0))
        try store.save(FeedFolderRecord(id: "folder-b", name: "Bravo", sortIndex: 1))
        try store.save(FeedFolderRecord(id: "folder-c", name: "Charlie", sortIndex: 2))
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)

        try store.moveFolder(name: "Bravo", targetIndex: 0)

        let changeA = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-a")
        #expect(changeA?.changedFields == ["sortIndex"])

        let changeB = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-b")
        #expect(changeB?.changedFields == ["sortIndex"])

        let changeC = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-c")
        #expect(changeC?.changedFields == ["sortIndex"])
    }

    @Test func sortAlphabeticallyMarkiertNurSortIndexAlsGeaendert() throws {
        // Cleanup vor dem Test
        UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedFolderStore(database: database)
        try store.save(FeedFolderRecord(id: "folder-b", name: "Bravo", sortIndex: 0))
        try store.save(FeedFolderRecord(id: "folder-a", name: "Alpha", sortIndex: 1))
        try store.save(FeedFolderRecord(id: "folder-c", name: "Charlie", sortIndex: 2))
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)

        try store.sortAlphabetically()

        let changeA = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-a")
        #expect(changeA?.changedFields == ["sortIndex"])

        let changeB = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-b")
        #expect(changeB?.changedFields == ["sortIndex"])

        let changeC = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-c")
        #expect(changeC?.changedFields == ["sortIndex"])
    }
}
