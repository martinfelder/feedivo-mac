import Foundation
import CloudKit
import GRDB
import Testing
@testable import Feedivo

/// Tests für `CloudSyncSmartFolderMapping` (iCloud Sync Phase 2a, Task 7). `smart_folders`
/// syncen NUR benutzerdefiniert (`isDefault == false`) — `isDefault`/`defaultKey` werden
/// deshalb bewusst NIE auf das CKRecord geschrieben, und ein eingehender Record mit gesetztem
/// `defaultKey` wird defensiv verworfen (siehe Dokumentation im Mapping selbst).
struct CloudSyncSmartFolderMappingTests {
    @Test func makeCKRecordMapptAlleFelder() {
        let folder = SmartFolderRecord(
            id: "folder-1",
            name: "Meine Auswahl",
            matchMode: "all",
            isShownInSidebar: true,
            isDefault: false,
            sortOrder: 3,
            iconName: "star",
            colorHex: "#FF0000",
            defaultShowsReadArticles: true
        )

        let record = CloudSyncSmartFolderMapping.makeCKRecord(from: folder)

        #expect(record.recordType == "SmartFolder")
        #expect(record["name"] as? String == "Meine Auswahl")
        #expect(record["matchMode"] as? String == "all")
        #expect(record["isShownInSidebar"] as? Bool == true)
        #expect(record["sortOrder"] as? Int == 3)
        #expect(record["iconName"] as? String == "star")
        #expect(record["colorHex"] as? String == "#FF0000")
        #expect(record["defaultShowsReadArticles"] as? Bool == true)
    }

    /// Kernklausel dieses Mappings: `isDefault`/`defaultKey` dürfen NIE auf dem CKRecord landen
    /// — ein synctes SmartFolder ist per Definition immer benutzerdefiniert.
    @Test func makeCKRecordSchreibtNiemalsIsDefaultOderDefaultKey() {
        let folder = SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", isDefault: false, defaultKey: nil)

        let record = CloudSyncSmartFolderMapping.makeCKRecord(from: folder)

        #expect(record["isDefault"] == nil)
        #expect(record["defaultKey"] == nil)
    }

    @Test func makeCKRecordAktualisiertBestehendesRecordStattEinNeuesZuErzeugen() {
        let folder = SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", sortOrder: 0)
        let existing = CKRecord(recordType: "SmartFolder", recordID: CloudSyncSmartFolderMapping.recordID(forLocalID: "folder-1"))

        let record = CloudSyncSmartFolderMapping.makeCKRecord(from: folder, existing: existing)

        #expect(record === existing)
        #expect(record["name"] as? String == "Meine Auswahl")
    }

    @Test func smartFolderRecordFromCKRecordMapptZurueck() {
        let folder = SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", sortOrder: 3)
        let record = CloudSyncSmartFolderMapping.makeCKRecord(from: folder)

        let mapped = CloudSyncSmartFolderMapping.smartFolderRecord(from: record)

        #expect(mapped?.name == "Meine Auswahl")
        #expect(mapped?.isDefault == false)
        #expect(mapped?.defaultKey == nil)
    }

    @Test func smartFolderRecordFromCKRecordLiefertNilBeiFehlendenPflichtfeldern() {
        let ckRecord = CKRecord(recordType: "SmartFolder", recordID: CloudSyncSmartFolderMapping.recordID(forLocalID: "folder-1"))

        #expect(CloudSyncSmartFolderMapping.smartFolderRecord(from: ckRecord) == nil)
    }

    @Test func makeCKRecordFromLocalIDLiefertNilFuerUnbekannteID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let record = try CloudSyncSmartFolderMapping.makeCKRecord(fromLocalID: "unbekannt", database: database)

        #expect(record == nil)
    }

    @Test func makeCKRecordFromLocalIDLiefertNilFuerDefaultOrdner() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try SQLiteSmartFolderStore(database: database).restoreDefaultFolders()
        let defaultFolder = try SQLiteSmartFolderStore(database: database).folders().first { $0.defaultKey == "unread" }
        let defaultFolderID = try #require(defaultFolder?.id)

        let record = try CloudSyncSmartFolderMapping.makeCKRecord(fromLocalID: defaultFolderID, database: database)

        #expect(record == nil)
    }

    @Test func makeCKRecordFromLocalIDLaedtBestehendenBenutzerdefiniertenOrdner() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try SQLiteSmartFolderStore(database: database).save(
            SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", isDefault: false, sortOrder: 3),
            conditions: []
        )

        let record = try CloudSyncSmartFolderMapping.makeCKRecord(fromLocalID: "folder-1", database: database)

        #expect(record?["name"] as? String == "Meine Auswahl")
        #expect(record?["sortOrder"] as? Int == 3)
    }

    @Test func applyIncomingFuegtNeuenOrdnerEin() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let folder = SmartFolderRecord(id: "folder-neu", name: "Neu", sortOrder: 1)
        let record = CloudSyncSmartFolderMapping.makeCKRecord(from: folder)

        try CloudSyncSmartFolderMapping.applyIncoming(record, database: database)

        let loaded = try SQLiteSmartFolderStore(database: database).folder(id: "folder-neu")
        #expect(loaded?.name == "Neu")
        #expect(loaded?.isDefault == false)
    }

    @Test func applyIncomingAktualisiertBestehendenOrdner() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)
        try store.save(SmartFolderRecord(id: "folder-1", name: "Alt", sortOrder: 0), conditions: [])

        let updatedFolder = SmartFolderRecord(id: "folder-1", name: "Neu Betitelt", sortOrder: 3)
        let record = CloudSyncSmartFolderMapping.makeCKRecord(from: updatedFolder)

        try CloudSyncSmartFolderMapping.applyIncoming(record, database: database)

        let loaded = try store.folder(id: "folder-1")
        #expect(loaded?.name == "Neu Betitelt")
        #expect(loaded?.sortOrder == 3)
    }

    /// Mandatorischer Schutzklausel-Test: ein eingehender Record mit gesetztem, nicht-leerem
    /// `defaultKey` darf niemals lokal gespeichert werden — regulär von
    /// `CloudSyncSmartFolderMapping.makeCKRecord(from:)` erzeugte Records tragen niemals einen
    /// `defaultKey`, aber ein fremder Client könnte theoretisch einen solchen Wert senden.
    @Test func applyIncomingVerwirftRecordMitGesetztemDefaultKey() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let record = CKRecord(recordType: "SmartFolder", recordID: CloudSyncSmartFolderMapping.recordID(forLocalID: "folder-1"))
        record["name"] = "Ungelesen" as CKRecordValue
        record["matchMode"] = "all" as CKRecordValue
        record["isShownInSidebar"] = true as CKRecordValue
        record["sortOrder"] = 0 as CKRecordValue
        record["defaultShowsReadArticles"] = false as CKRecordValue
        record["defaultKey"] = "unread" as CKRecordValue

        try CloudSyncSmartFolderMapping.applyIncoming(record, database: database)

        let count = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM smart_folders WHERE id = 'folder-1'") ?? 0
        }
        #expect(count == 0)
    }

    @Test func applyIncomingDeletionEntferntBenutzerdefiniertenOrdner() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)
        try store.save(SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", isDefault: false, sortOrder: 0), conditions: [])

        try CloudSyncSmartFolderMapping.applyIncomingDeletion(recordID: CloudSyncSmartFolderMapping.recordID(forLocalID: "folder-1"), database: database)

        #expect(try store.folder(id: "folder-1") == nil)
    }

    /// Zweite Schutzklausel-Ebene auf der Löschungsseite: `applyIncomingDeletion` filtert
    /// zusätzlich `AND isDefault = 0` — ein eingebauter Ordner darf auch über eine (theoretisch
    /// niemals auftretende) eingehende Löschung nicht verschwinden.
    @Test func applyIncomingDeletionLoeschtNiemalsDefaultOrdner() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)
        try store.restoreDefaultFolders()
        let defaultFolder = try #require(try store.folders().first { $0.defaultKey == "unread" })

        try CloudSyncSmartFolderMapping.applyIncomingDeletion(recordID: CloudSyncSmartFolderMapping.recordID(forLocalID: defaultFolder.id), database: database)

        #expect(try store.folder(id: defaultFolder.id) != nil)
    }

    @Test func localUpdatedAtLiefertUpdatedAt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)
        try store.save(SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", sortOrder: 0), conditions: [])

        let localUpdatedAt = try CloudSyncSmartFolderMapping.localUpdatedAt(forLocalID: "folder-1", database: database)

        #expect(localUpdatedAt != nil)
    }

    @Test func localUpdatedAtLiefertNilFuerUnbekannteID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let localUpdatedAt = try CloudSyncSmartFolderMapping.localUpdatedAt(forLocalID: "unbekannt", database: database)

        #expect(localUpdatedAt == nil)
    }
}
