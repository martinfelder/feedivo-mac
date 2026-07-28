import Foundation
import CloudKit
import Testing
@testable import Feedivo

/// Tests für `CloudSyncRuleMapping` (iCloud Sync Phase 2a, Task 6). `rules` wird vollständig
/// gemappt (keine lokal-only Felder) — `assignTagID` ist eine reine, optionale String-Referenz
/// auf `tags.id`, siehe Doku im Mapping selbst.
struct CloudSyncRuleMappingTests {
    @Test func makeCKRecordMapptAlleFelder() {
        let rule = RuleRecord(
            id: "rule-1",
            name: "Wichtig",
            isEnabled: true,
            matchMode: "all",
            action: "assignTag",
            assignTagID: "tag-1",
            notificationTemplate: "{Titel}",
            notificationPriority: "normal",
            sortOrder: 1
        )

        let record = CloudSyncRuleMapping.makeCKRecord(from: rule)

        #expect(record.recordType == "Rule")
        #expect(record["name"] as? String == "Wichtig")
        #expect(record["isEnabled"] as? Bool == true)
        #expect(record["matchMode"] as? String == "all")
        #expect(record["action"] as? String == "assignTag")
        #expect(record["assignTagID"] as? String == "tag-1")
        #expect(record["notificationTemplate"] as? String == "{Titel}")
        #expect(record["notificationPriority"] as? String == "normal")
        #expect(record["sortOrder"] as? Int == 1)
    }

    @Test func makeCKRecordAktualisiertBestehendesRecordStattEinNeuesZuErzeugen() {
        let rule = RuleRecord(id: "rule-1", name: "Wichtig", sortOrder: 0)
        let existing = CKRecord(recordType: "Rule", recordID: CloudSyncRuleMapping.recordID(forLocalID: "rule-1"))

        let record = CloudSyncRuleMapping.makeCKRecord(from: rule, existing: existing)

        #expect(record === existing)
        #expect(record["name"] as? String == "Wichtig")
    }

    @Test func ruleRecordFromCKRecordMapptZurueckOhneAssignTagID() {
        let rule = RuleRecord(id: "rule-1", name: "Wichtig", assignTagID: nil, sortOrder: 0)
        let record = CloudSyncRuleMapping.makeCKRecord(from: rule)

        let mapped = CloudSyncRuleMapping.ruleRecord(from: record)

        #expect(mapped?.assignTagID == nil)
        #expect(mapped?.name == "Wichtig")
    }

    @Test func ruleRecordFromCKRecordMapptZurueckMitAssignTagID() {
        let rule = RuleRecord(id: "rule-1", name: "Wichtig", assignTagID: "tag-1", sortOrder: 0)
        let record = CloudSyncRuleMapping.makeCKRecord(from: rule)

        let mapped = CloudSyncRuleMapping.ruleRecord(from: record)

        #expect(mapped?.assignTagID == "tag-1")
    }

    @Test func ruleRecordFromCKRecordLiefertNilBeiFehlendenPflichtfeldern() {
        let ckRecord = CKRecord(recordType: "Rule", recordID: CloudSyncRuleMapping.recordID(forLocalID: "rule-1"))

        #expect(CloudSyncRuleMapping.ruleRecord(from: ckRecord) == nil)
    }

    @Test func makeCKRecordFromLocalIDLiefertNilFuerUnbekannteID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let record = try CloudSyncRuleMapping.makeCKRecord(fromLocalID: "unbekannt", existing: nil, database: database)

        #expect(record == nil)
    }

    @Test func makeCKRecordFromLocalIDLaedtBestehendeRegel() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try SQLiteRuleStore(database: database).save(
            RuleRecord(id: "rule-1", name: "Wichtig", sortOrder: 3),
            conditions: []
        )

        let record = try CloudSyncRuleMapping.makeCKRecord(fromLocalID: "rule-1", existing: nil, database: database)

        #expect(record?["name"] as? String == "Wichtig")
        #expect(record?["sortOrder"] as? Int == 3)
    }

    @Test func applyIncomingFuegtNeueRegelEin() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let rule = RuleRecord(id: "rule-neu", name: "Neu", sortOrder: 1)
        let record = CloudSyncRuleMapping.makeCKRecord(from: rule)

        try CloudSyncRuleMapping.applyIncoming(record, database: database)

        let loaded = try SQLiteRuleStore(database: database).rule(id: "rule-neu")
        #expect(loaded?.name == "Neu")
        #expect(loaded?.sortOrder == 1)
    }

    @Test func applyIncomingAktualisiertBestehendeRegel() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteRuleStore(database: database)
        try store.save(RuleRecord(id: "rule-1", name: "Alt", sortOrder: 0), conditions: [])

        let updatedRule = RuleRecord(id: "rule-1", name: "Neu Betitelt", sortOrder: 3)
        let record = CloudSyncRuleMapping.makeCKRecord(from: updatedRule)

        try CloudSyncRuleMapping.applyIncoming(record, database: database)

        let loaded = try store.rule(id: "rule-1")
        #expect(loaded?.name == "Neu Betitelt")
        #expect(loaded?.sortOrder == 3)
    }

    @Test func applyIncomingDeletionEntferntRegel() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteRuleStore(database: database)
        try store.save(RuleRecord(id: "rule-1", name: "Wichtig", sortOrder: 0), conditions: [])

        try CloudSyncRuleMapping.applyIncomingDeletion(recordID: CloudSyncRuleMapping.recordID(forLocalID: "rule-1"), database: database)

        #expect(try store.rule(id: "rule-1") == nil)
    }

    @Test func localUpdatedAtLiefertUpdatedAt() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteRuleStore(database: database)
        try store.save(RuleRecord(id: "rule-1", name: "Wichtig", sortOrder: 0), conditions: [])

        let localUpdatedAt = try CloudSyncRuleMapping.localUpdatedAt(forLocalID: "rule-1", database: database)

        #expect(localUpdatedAt != nil)
    }

    @Test func localUpdatedAtLiefertNilFuerUnbekannteID() throws {
        let database = try FeedivoDatabase.inMemoryForTests()

        let localUpdatedAt = try CloudSyncRuleMapping.localUpdatedAt(forLocalID: "unbekannt", database: database)

        #expect(localUpdatedAt == nil)
    }

    @Test func allLocalIDsListetAlleRegelnAuf() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try SQLiteRuleStore(database: database).save(RuleRecord(id: "rule-1", name: "Wichtig", sortOrder: 0), conditions: [])
        try SQLiteRuleStore(database: database).save(RuleRecord(id: "rule-2", name: "Später", sortOrder: 1), conditions: [])

        let ids = try CloudSyncRuleMapping.allLocalIDs(database: database)

        #expect(Set(ids) == Set(["rule-1", "rule-2"]))
    }

    @Test func makeCKRecordFromLocalIDMitExistingBehaeltSystemfelder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try SQLiteRuleStore(database: database).save(RuleRecord(id: "rule-1", name: "Wichtig", sortOrder: 0), conditions: [])
        let existing = CKRecord(recordType: "Rule", recordID: CloudSyncRuleMapping.recordID(forLocalID: "rule-1"))

        let record = try CloudSyncRuleMapping.makeCKRecord(fromLocalID: "rule-1", existing: existing, database: database)

        #expect(record === existing)
        #expect(record?["name"] as? String == "Wichtig")
    }
}
