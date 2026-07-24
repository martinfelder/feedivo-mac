import Foundation
import CloudKit
import GRDB
import Testing
@testable import Feedivo

/// Tests für `CloudSyncRuleConditionMapping` (iCloud Sync Phase 2a, Task 6). `rule_conditions`
/// wird vollständig gemappt, eigener CKRecord pro Bedingungszeile. Der Fremdschlüssel-
/// Randfall (Bedingung trifft vor ihrer Regel ein) wird NICHT hier getestet — GRDBs In-Memory-
/// Testdatenbank hat dieselbe `PRAGMA foreign_keys = ON`-Konfiguration wie die echte App, ein
/// direkter Test dafür würde `applyIncoming` real zum Scheitern bringen und den
/// Catch-and-Log-Pfad decken, siehe eigener Test unten.
struct CloudSyncRuleConditionMappingTests {
    @Test func makeCKRecordMapptAlleFelder() {
        let condition = RuleConditionRecord(
            id: "cond-1",
            ruleID: "rule-1",
            field: "title",
            conditionOperator: "contains",
            value: "Test",
            sortOrder: 0,
            groupIndex: 1
        )

        let record = CloudSyncRuleConditionMapping.makeCKRecord(from: condition)

        #expect(record.recordType == "RuleCondition")
        #expect(record["ruleID"] as? String == "rule-1")
        #expect(record["field"] as? String == "title")
        #expect(record["conditionOperator"] as? String == "contains")
        #expect(record["value"] as? String == "Test")
        #expect(record["sortOrder"] as? Int == 0)
        #expect(record["groupIndex"] as? Int == 1)
    }

    @Test func makeCKRecordAktualisiertBestehendesRecordStattEinNeuesZuErzeugen() {
        let condition = RuleConditionRecord(id: "cond-1", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "Test")
        let existing = CKRecord(recordType: "RuleCondition", recordID: CloudSyncRuleConditionMapping.recordID(forLocalID: "cond-1"))

        let record = CloudSyncRuleConditionMapping.makeCKRecord(from: condition, existing: existing)

        #expect(record === existing)
        #expect(record["ruleID"] as? String == "rule-1")
    }

    @Test func ruleConditionRecordFromCKRecordMapptZurueck() {
        let condition = RuleConditionRecord(id: "cond-1", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "Test")
        let record = CloudSyncRuleConditionMapping.makeCKRecord(from: condition)

        let mapped = CloudSyncRuleConditionMapping.ruleConditionRecord(from: record)

        #expect(mapped?.ruleID == "rule-1")
        #expect(mapped?.field == "title")
        #expect(mapped?.conditionOperator == "contains")
        #expect(mapped?.value == "Test")
    }

    @Test func ruleConditionRecordFromCKRecordLiefertNilBeiFehlendenPflichtfeldern() {
        let ckRecord = CKRecord(recordType: "RuleCondition", recordID: CloudSyncRuleConditionMapping.recordID(forLocalID: "cond-1"))

        #expect(CloudSyncRuleConditionMapping.ruleConditionRecord(from: ckRecord) == nil)
    }

    @Test func makeCKRecordFromLocalIDLiefertNilFuerUnbekannteID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let record = try CloudSyncRuleConditionMapping.makeCKRecord(fromLocalID: "unbekannt", database: database)

        #expect(record == nil)
    }

    @Test func makeCKRecordFromLocalIDLaedtBestehendeBedingung() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try SQLiteRuleStore(database: database).save(
            RuleRecord(id: "rule-1", name: "Wichtig", sortOrder: 0),
            conditions: [
                RuleConditionRecord(id: "cond-1", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "Test")
            ]
        )

        let record = try CloudSyncRuleConditionMapping.makeCKRecord(fromLocalID: "cond-1", database: database)

        #expect(record?["field"] as? String == "title")
        #expect(record?["value"] as? String == "Test")
    }

    @Test func applyIncomingFuegtNeueBedingungEinWennElternregelExistiert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try SQLiteRuleStore(database: database).save(RuleRecord(id: "rule-1", name: "Wichtig", sortOrder: 0), conditions: [])

        let condition = RuleConditionRecord(id: "cond-1", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "Test")
        let record = CloudSyncRuleConditionMapping.makeCKRecord(from: condition)

        try CloudSyncRuleConditionMapping.applyIncoming(record, database: database)

        let loaded = try database.read { db in
            try RuleConditionRecord.fetchOne(db, sql: "SELECT * FROM rule_conditions WHERE id = ?", arguments: ["cond-1"])
        }
        #expect(loaded?.value == "Test")
    }

    @Test func applyIncomingLoggtUndUeberspringtStattZuWerfenWennElternregelFehlt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        // Bewusst KEINE zugehörige Regel angelegt — reproduziert den dokumentierten
        // Fremdschlüssel-Randfall (Bedingung trifft vor ihrer Regel ein).
        let condition = RuleConditionRecord(id: "cond-verwaist", ruleID: "rule-fehlt", field: "title", conditionOperator: "contains", value: "Test")
        let record = CloudSyncRuleConditionMapping.makeCKRecord(from: condition)

        // Darf NICHT werfen — catch-and-log ist das spezifizierte Verhalten.
        try CloudSyncRuleConditionMapping.applyIncoming(record, database: database)

        let loaded = try database.read { db in
            try RuleConditionRecord.fetchOne(db, sql: "SELECT * FROM rule_conditions WHERE id = ?", arguments: ["cond-verwaist"])
        }
        #expect(loaded == nil)
    }

    @Test func applyIncomingDeletionEntferntBedingung() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try SQLiteRuleStore(database: database).save(
            RuleRecord(id: "rule-1", name: "Wichtig", sortOrder: 0),
            conditions: [
                RuleConditionRecord(id: "cond-1", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "Test")
            ]
        )

        try CloudSyncRuleConditionMapping.applyIncomingDeletion(recordID: CloudSyncRuleConditionMapping.recordID(forLocalID: "cond-1"), database: database)

        let loaded = try database.read { db in
            try RuleConditionRecord.fetchOne(db, sql: "SELECT * FROM rule_conditions WHERE id = ?", arguments: ["cond-1"])
        }
        #expect(loaded == nil)
    }

    @Test func localUpdatedAtLiefertUpdatedAt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try SQLiteRuleStore(database: database).save(
            RuleRecord(id: "rule-1", name: "Wichtig", sortOrder: 0),
            conditions: [
                RuleConditionRecord(id: "cond-1", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "Test")
            ]
        )

        let localUpdatedAt = try CloudSyncRuleConditionMapping.localUpdatedAt(forLocalID: "cond-1", database: database)

        #expect(localUpdatedAt != nil)
    }

    @Test func localUpdatedAtLiefertNilFuerUnbekannteID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let localUpdatedAt = try CloudSyncRuleConditionMapping.localUpdatedAt(forLocalID: "unbekannt", database: database)

        #expect(localUpdatedAt == nil)
    }
}
