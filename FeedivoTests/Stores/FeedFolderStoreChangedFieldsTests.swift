import Foundation
import Testing
@testable import Feedivo

struct FeedFolderStoreChangedFieldsTests {
    @Test func renameFolderMarkiertNurNameAlsGeaendert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedFolderStore(database: database)
        try store.save(FeedFolderRecord(id: "folder-1", name: "Alt", sortIndex: 0, createdAt: Date(), updatedAt: Date()))
        try CloudSyncSettingsStore(database: database).setEnabled(true)

        try store.renameFolder(from: "Alt", to: "Neu")

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-1")
        #expect(change?.changedFields == ["name"])
    }

    @Test func moveFolderMarkiertNurSortIndexAlsGeaendert() throws {
        // Standard einer frischen Datenbank ist bereits "aus" (Migration v33), kein Cleanup nötig.
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedFolderStore(database: database)
        try store.save(FeedFolderRecord(id: "folder-a", name: "Alpha", sortIndex: 0))
        try store.save(FeedFolderRecord(id: "folder-b", name: "Bravo", sortIndex: 1))
        try store.save(FeedFolderRecord(id: "folder-c", name: "Charlie", sortIndex: 2))
        try CloudSyncSettingsStore(database: database).setEnabled(true)

        try store.moveFolder(name: "Bravo", targetIndex: 0)

        let changeA = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-a")
        #expect(changeA?.changedFields == ["sortIndex"])

        let changeB = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-b")
        #expect(changeB?.changedFields == ["sortIndex"])

        let changeC = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-c")
        #expect(changeC?.changedFields == ["sortIndex"])
    }

    @Test func sortAlphabeticallyMarkiertNurSortIndexAlsGeaendert() throws {
        // Standard einer frischen Datenbank ist bereits "aus" (Migration v33), kein Cleanup nötig.
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = FeedFolderStore(database: database)
        try store.save(FeedFolderRecord(id: "folder-b", name: "Bravo", sortIndex: 0))
        try store.save(FeedFolderRecord(id: "folder-a", name: "Alpha", sortIndex: 1))
        try store.save(FeedFolderRecord(id: "folder-c", name: "Charlie", sortIndex: 2))
        try CloudSyncSettingsStore(database: database).setEnabled(true)

        try store.sortAlphabetically()

        let changeA = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-a")
        #expect(changeA?.changedFields == ["sortIndex"])

        let changeB = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-b")
        #expect(changeB?.changedFields == ["sortIndex"])

        let changeC = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-c")
        #expect(changeC?.changedFields == ["sortIndex"])
    }
}
