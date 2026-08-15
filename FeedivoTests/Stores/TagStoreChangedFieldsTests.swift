import Foundation
import Testing
@testable import Feedivo

struct TagStoreChangedFieldsTests {
    @Test func renameTagMarkiertNurNameAlsGeaendert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = TagStore(database: database)
        try store.save(TagRecord(id: "tag-1", name: "Alt", colorHex: "#FF0000", sortIndex: 0))
        try CloudSyncSettingsStore(database: database).setEnabled(true)

        try store.renameTag(id: "tag-1", name: "Neu")

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "tag-1")
        #expect(change?.changedFields == ["name"])
    }

    @Test func updateColorMarkiertNurColorHexAlsGeaendert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = TagStore(database: database)
        try store.save(TagRecord(id: "tag-1", name: "Alt", colorHex: "#FF0000", sortIndex: 0))
        try CloudSyncSettingsStore(database: database).setEnabled(true)

        try store.updateColor(id: "tag-1", colorHex: "#00FF00")

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "tag-1")
        #expect(change?.changedFields == ["colorHex"])
    }

    @Test func moveMarkiertNurSortIndexAlsGeaendert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = TagStore(database: database)
        try store.save(TagRecord(id: "tag-1", name: "Tag1", colorHex: "#FF0000", sortIndex: 0))
        try store.save(TagRecord(id: "tag-2", name: "Tag2", colorHex: "#00FF00", sortIndex: 1))
        try store.save(TagRecord(id: "tag-3", name: "Tag3", colorHex: "#0000FF", sortIndex: 2))
        try CloudSyncSettingsStore(database: database).setEnabled(true)

        try store.move(id: "tag-1", targetIndex: 2)

        let change1 = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "tag-1")
        #expect(change1?.changedFields == ["sortIndex"])

        let change2 = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "tag-2")
        #expect(change2?.changedFields == ["sortIndex"])

        let change3 = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "tag-3")
        #expect(change3?.changedFields == ["sortIndex"])
    }
}
