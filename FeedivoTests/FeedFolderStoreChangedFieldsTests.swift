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
}
