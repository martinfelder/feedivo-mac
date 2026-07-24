import Foundation
import CloudKit
import GRDB
import Testing
@testable import Feedivo

/// Tests für `CloudSyncSmartFolderConditionMapping` (iCloud Sync Phase 2a, Task 7).
/// `smart_folder_conditions` wird vollständig gemappt, eigener CKRecord pro Bedingungszeile.
/// Der Fremdschlüssel-Randfall (Bedingung trifft vor ihrem Elternordner ein) wird analog zu
/// `CloudSyncRuleConditionMappingTests` getestet — GRDBs In-Memory-Testdatenbank hat dieselbe
/// `PRAGMA foreign_keys = ON`-Konfiguration wie die echte App.
struct CloudSyncSmartFolderConditionMappingTests {
    @Test func makeCKRecordMapptAlleFelder() {
        let condition = SmartFolderConditionRecord(
            id: "cond-1",
            smartFolderID: "folder-1",
            field: "status",
            conditionOperator: "is",
            value: "unread",
            sortOrder: 2
        )

        let record = CloudSyncSmartFolderConditionMapping.makeCKRecord(from: condition)

        #expect(record.recordType == "SmartFolderCondition")
        #expect(record["smartFolderID"] as? String == "folder-1")
        #expect(record["field"] as? String == "status")
        #expect(record["conditionOperator"] as? String == "is")
        #expect(record["value"] as? String == "unread")
        #expect(record["sortOrder"] as? Int == 2)
    }

    @Test func makeCKRecordAktualisiertBestehendesRecordStattEinNeuesZuErzeugen() {
        let condition = SmartFolderConditionRecord(id: "cond-1", smartFolderID: "folder-1", field: "status", conditionOperator: "is", value: "unread")
        let existing = CKRecord(recordType: "SmartFolderCondition", recordID: CloudSyncSmartFolderConditionMapping.recordID(forLocalID: "cond-1"))

        let record = CloudSyncSmartFolderConditionMapping.makeCKRecord(from: condition, existing: existing)

        #expect(record === existing)
        #expect(record["smartFolderID"] as? String == "folder-1")
    }

    @Test func smartFolderConditionRecordFromCKRecordMapptZurueck() {
        let condition = SmartFolderConditionRecord(id: "cond-1", smartFolderID: "folder-1", field: "status", conditionOperator: "is", value: "unread")
        let record = CloudSyncSmartFolderConditionMapping.makeCKRecord(from: condition)

        let mapped = CloudSyncSmartFolderConditionMapping.smartFolderConditionRecord(from: record)

        #expect(mapped?.smartFolderID == "folder-1")
        #expect(mapped?.field == "status")
        #expect(mapped?.conditionOperator == "is")
        #expect(mapped?.value == "unread")
    }

    @Test func smartFolderConditionRecordFromCKRecordLiefertNilBeiFehlendenPflichtfeldern() {
        let ckRecord = CKRecord(recordType: "SmartFolderCondition", recordID: CloudSyncSmartFolderConditionMapping.recordID(forLocalID: "cond-1"))

        #expect(CloudSyncSmartFolderConditionMapping.smartFolderConditionRecord(from: ckRecord) == nil)
    }

    @Test func makeCKRecordFromLocalIDLiefertNilFuerUnbekannteID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let record = try CloudSyncSmartFolderConditionMapping.makeCKRecord(fromLocalID: "unbekannt", database: database)

        #expect(record == nil)
    }

    @Test func makeCKRecordFromLocalIDLaedtBestehendeBedingung() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try SQLiteSmartFolderStore(database: database).save(
            SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", sortOrder: 0),
            conditions: [
                SmartFolderConditionRecord(id: "cond-1", smartFolderID: "folder-1", field: "status", conditionOperator: "is", value: "unread")
            ]
        )

        let record = try CloudSyncSmartFolderConditionMapping.makeCKRecord(fromLocalID: "cond-1", database: database)

        #expect(record?["field"] as? String == "status")
        #expect(record?["value"] as? String == "unread")
    }

    @Test func applyIncomingFuegtNeueBedingungEinWennElternordnerExistiert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try SQLiteSmartFolderStore(database: database).save(SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", sortOrder: 0), conditions: [])

        let condition = SmartFolderConditionRecord(id: "cond-1", smartFolderID: "folder-1", field: "status", conditionOperator: "is", value: "unread")
        let record = CloudSyncSmartFolderConditionMapping.makeCKRecord(from: condition)

        try CloudSyncSmartFolderConditionMapping.applyIncoming(record, database: database)

        let loaded = try database.read { db in
            try SmartFolderConditionRecord.fetchOne(db, sql: "SELECT * FROM smart_folder_conditions WHERE id = ?", arguments: ["cond-1"])
        }
        #expect(loaded?.value == "unread")
    }

    @Test func applyIncomingLoggtUndUeberspringtStattZuWerfenWennElternordnerFehlt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        // Bewusst KEIN zugehöriger Ordner angelegt — reproduziert den dokumentierten
        // Fremdschlüssel-Randfall (Bedingung trifft vor ihrem Elternordner ein).
        let condition = SmartFolderConditionRecord(id: "cond-verwaist", smartFolderID: "folder-fehlt", field: "status", conditionOperator: "is", value: "unread")
        let record = CloudSyncSmartFolderConditionMapping.makeCKRecord(from: condition)

        // Darf NICHT werfen — catch-and-log ist das spezifizierte Verhalten.
        try CloudSyncSmartFolderConditionMapping.applyIncoming(record, database: database)

        let loaded = try database.read { db in
            try SmartFolderConditionRecord.fetchOne(db, sql: "SELECT * FROM smart_folder_conditions WHERE id = ?", arguments: ["cond-verwaist"])
        }
        #expect(loaded == nil)
    }

    @Test func applyIncomingDeletionEntferntBedingung() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try SQLiteSmartFolderStore(database: database).save(
            SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", sortOrder: 0),
            conditions: [
                SmartFolderConditionRecord(id: "cond-1", smartFolderID: "folder-1", field: "status", conditionOperator: "is", value: "unread")
            ]
        )

        try CloudSyncSmartFolderConditionMapping.applyIncomingDeletion(recordID: CloudSyncSmartFolderConditionMapping.recordID(forLocalID: "cond-1"), database: database)

        let loaded = try database.read { db in
            try SmartFolderConditionRecord.fetchOne(db, sql: "SELECT * FROM smart_folder_conditions WHERE id = ?", arguments: ["cond-1"])
        }
        #expect(loaded == nil)
    }

    @Test func localUpdatedAtLiefertUpdatedAt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try SQLiteSmartFolderStore(database: database).save(
            SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", sortOrder: 0),
            conditions: [
                SmartFolderConditionRecord(id: "cond-1", smartFolderID: "folder-1", field: "status", conditionOperator: "is", value: "unread")
            ]
        )

        let localUpdatedAt = try CloudSyncSmartFolderConditionMapping.localUpdatedAt(forLocalID: "cond-1", database: database)

        #expect(localUpdatedAt != nil)
    }

    @Test func localUpdatedAtLiefertNilFuerUnbekannteID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let localUpdatedAt = try CloudSyncSmartFolderConditionMapping.localUpdatedAt(forLocalID: "unbekannt", database: database)

        #expect(localUpdatedAt == nil)
    }

    /// Kernklausel: Bedingungen, die zu einem eingebauten Ordner gehören (z. B. "Ungelesen"),
    /// dürfen NIE im Backfill landen — der JOIN gegen `smart_folders.isDefault` muss das filtern.
    @Test func allLocalIDsListetNurBedingungenNichtDefaultOrdnerAuf() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)
        try store.restoreDefaultFolders()
        let customCondition = SmartFolderConditionRecord(id: "cond-custom", smartFolderID: "custom-1", field: "status", conditionOperator: "is", value: "unread")
        try store.save(SmartFolderRecord(id: "custom-1", name: "Meine Auswahl", isDefault: false), conditions: [customCondition])

        let ids = try CloudSyncSmartFolderConditionMapping.allLocalIDs(database: database)

        #expect(ids == ["cond-custom"])
    }
}
