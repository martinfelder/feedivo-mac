import Foundation
import GRDB
import Testing
@testable import Feedivo

/// iCloud-Sync-Wiring-Tests für `SQLiteRuleStore` (Phase 2a, Task 6). Basis-Funktionalität
/// (Speichern/Duplizieren/Verschieben ohne Sync) ist bereits in `SQLiteAdminStoreTests.swift`
/// abgedeckt — diese Datei testet ausschließlich das Enqueue-Verhalten für
/// `CloudSyncPendingChangeStore`, analog zu `FeedFolderStoreTests.swift` (Task 5).
struct SQLiteRuleStoreTests {
    @Test func saveMarkiertRegelUndBedingungenAlsPendingSyncWennAktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        let store = SQLiteRuleStore(database: database)
        try store.save(
            RuleRecord(id: "rule-1", name: "Test", sortOrder: 0),
            conditions: [
                RuleConditionRecord(id: "cond-1", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "x")
            ]
        )

        let pendingIDs = Set(try CloudSyncPendingChangeStore(database: database).pendingChanges().map(\.id))
        #expect(pendingIDs == Set(["rule-1", "cond-1"]))
    }

    @Test func saveMarkiertNichtsWennSyncDeaktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey)

        let store = SQLiteRuleStore(database: database)
        try store.save(
            RuleRecord(id: "rule-1", name: "Test", sortOrder: 0),
            conditions: [
                RuleConditionRecord(id: "cond-1", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "x")
            ]
        )

        #expect(try CloudSyncPendingChangeStore(database: database).pendingChanges().isEmpty)
    }

    @Test func saveBeimBearbeitenMarkiertAlteBedingungenAlsDeleteUndNeueAlsSave() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteRuleStore(database: database)
        try store.save(
            RuleRecord(id: "rule-1", name: "Test", sortOrder: 0),
            conditions: [
                RuleConditionRecord(id: "cond-alt", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "alt")
            ]
        )

        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        // Editieren: Bedingungsliste wird komplett ersetzt (bestehendes save()-Verhalten:
        // delete-all-then-reinsert) — die alte Bedingungs-ID muss als .delete enqueued
        // werden, die neue als .save.
        try store.save(
            RuleRecord(id: "rule-1", name: "Test", sortOrder: 0),
            conditions: [
                RuleConditionRecord(id: "cond-neu", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "neu")
            ]
        )

        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        let byID = Dictionary(uniqueKeysWithValues: pending.map { ($0.id, $0.changeType) })
        #expect(byID["cond-alt"] == .delete)
        #expect(byID["cond-neu"] == .save)
        #expect(byID["rule-1"] == .save)
    }

    @Test func updateEnabledMarkiertRegelAlsPendingSync() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteRuleStore(database: database)
        try store.save(RuleRecord(id: "rule-1", name: "Test", sortOrder: 0), conditions: [])

        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.updateEnabled(id: "rule-1", isEnabled: false)

        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        #expect(pending.map(\.id) == ["rule-1"])
        #expect(pending.first?.changeType == .save)
    }

    @Test func moveMarkiertBetroffeneRegelnAlsPendingSync() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteRuleStore(database: database)
        try store.save(RuleRecord(id: "rule-a", name: "A", sortOrder: 0), conditions: [])
        try store.save(RuleRecord(id: "rule-b", name: "B", sortOrder: 1), conditions: [])

        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.move(id: "rule-b", toPositionOf: "rule-a")

        let pendingIDs = Set(try CloudSyncPendingChangeStore(database: database).pendingChanges().map(\.id))
        #expect(pendingIDs.contains("rule-a"))
        #expect(pendingIDs.contains("rule-b"))
    }

    @Test func deleteRuleEnqueuedLoeschungenFuerRegelUndAlleBedingungen() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteRuleStore(database: database)
        let rule = RuleRecord(id: "rule-1", name: "Test", sortOrder: 0)
        let condition = RuleConditionRecord(id: "cond-1", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "x")
        try store.save(rule, conditions: [condition])

        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.delete(id: "rule-1")

        let pendingDeletes = try CloudSyncPendingChangeStore(database: database).pendingChanges()
            .filter { $0.changeType == .delete }
            .map(\.id)
        #expect(Set(pendingDeletes) == Set(["rule-1", "cond-1"]))

        // Die Kaskade selbst muss tatsächlich stattgefunden haben — sonst wäre der Test ein
        // Blindgänger (die Bedingung könnte theoretisch noch existieren, obwohl ihre
        // Löschung bereits enqueued wurde).
        let remainingCondition = try database.read { db in
            try RuleConditionRecord.fetchOne(db, sql: "SELECT * FROM rule_conditions WHERE id = ?", arguments: ["cond-1"])
        }
        #expect(remainingCondition == nil)
    }

    @Test func duplicateMarkiertNeueRegelUndBedingungenAlsPendingSync() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteRuleStore(database: database)
        try store.save(
            RuleRecord(id: "rule-1", name: "Original", sortOrder: 0),
            conditions: [
                RuleConditionRecord(id: "cond-1", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "x")
            ]
        )

        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        let duplicate = try store.duplicate(id: "rule-1", copyName: "Kopie")
        let duplicateConditionID = try store.conditions(ruleID: duplicate.id).first?.id

        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        let byID = Dictionary(uniqueKeysWithValues: pending.map { ($0.id, $0.changeType) })
        #expect(byID[duplicate.id] == .save)
        if let duplicateConditionID {
            #expect(byID[duplicateConditionID] == .save)
        } else {
            Issue.record("Erwartete duplizierte Bedingung wurde nicht gefunden")
        }
    }
}
