import Foundation
import Testing
@testable import Feedivo

/// iCloud-Sync-`changedFields`-Diffing-Tests für `SQLiteRuleStore` (Phase 3, Task 9).
///
/// Anders als bei Tag/Feed/FeedFolder (Task 6-8, je ein Feld pro Mutationsmethode) ist
/// `save(_:conditions:)` ein genereller Upsert — der Regel-Editor ruft ihn bei JEDER Speicherung
/// auf, egal welches Feld sich tatsächlich geändert hat. Diese Tests verifizieren, dass
/// `SQLiteRuleStore` deshalb VOR dem Schreiben den bestehenden Rule-Stand lädt und gegen den
/// neuen vergleicht, um `changedFields` korrekt (nur die tatsächlich geänderten Felder) zu
/// berechnen — sowie, dass die beiden Mehrzeilen-Fälle (Bedingungs-Ersetzung in `save`,
/// Reorder in `move`) das erwartete `changedFields` für JEDE betroffene Zeile speichern, nicht
/// nur für die zuerst geprüfte.
struct SQLiteRuleStoreChangedFieldsTests {
    @Test func saveMarkiertNurTatsaechlichGeaenderteFelder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteRuleStore(database: database)
        let original = RuleRecord(
            id: "rule-1", name: "Alt", isEnabled: true, matchMode: RuleMatchMode.all.rawValue,
            action: "assignTag", assignTagID: nil, notificationTemplate: "{Titel}",
            notificationPriority: RuleNotificationPriority.normal.rawValue, sortOrder: 0, createdAt: Date()
        )
        try store.save(original, conditions: [])
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        var updated = original
        updated.name = "Neu"
        try store.save(updated, conditions: [])

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "rule-1")
        #expect(change?.changedFields == ["name"])
    }

    @Test func updateEnabledMarkiertNurIsEnabled() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteRuleStore(database: database)
        let rule = RuleRecord(
            id: "rule-1", name: "Regel", isEnabled: true, matchMode: RuleMatchMode.all.rawValue,
            action: "assignTag", assignTagID: nil, notificationTemplate: "{Titel}",
            notificationPriority: RuleNotificationPriority.normal.rawValue, sortOrder: 0, createdAt: Date()
        )
        try store.save(rule, conditions: [])
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.updateEnabled(id: "rule-1", isEnabled: false)

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "rule-1")
        #expect(change?.changedFields == ["isEnabled"])
    }

    /// Regressionsschutz: eine erneute Speicherung mit IDENTISCHEM Inhalt (kein Feld hat sich
    /// geändert) darf keine leere `changedFields`-Liste erzeugen, die fälschlich als "kein
    /// Feld geändert, aber trotzdem Feld-Ebene-Tracking aktiv" interpretiert werden könnte —
    /// `changedRuleFields` liefert `nil`, sobald die Diff-Liste leer ist (siehe
    /// `SQLiteRuleStore.changedRuleFields`).
    @Test func saveOhneAenderungMarkiertKeineFelder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteRuleStore(database: database)
        let rule = RuleRecord(
            id: "rule-1", name: "Unverändert", isEnabled: true, matchMode: RuleMatchMode.all.rawValue,
            action: "assignTag", assignTagID: nil, notificationTemplate: "{Titel}",
            notificationPriority: RuleNotificationPriority.normal.rawValue, sortOrder: 0, createdAt: Date()
        )
        try store.save(rule, conditions: [])
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.save(rule, conditions: [])

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "rule-1")
        // Whole-Branch-Review-Fund (Important 4c): `change?.changedFields == nil` allein wird
        // auch dann erfüllt, wenn `change` selbst `nil` ist — d. h. dieser Test hätte selbst
        // ein komplett entferntes Rule-Sync-Enqueueing NICHT bemerkt. Zuerst explizit
        // sicherstellen, dass die Pending-Sync-Zeile tatsächlich existiert.
        #expect(change != nil)
        #expect(change?.changedFields == nil)
    }

    /// Regressionsschutz für eine echte Neuanlage (keine vorherige Zeile existiert): hier gibt
    /// es keinen "alten Stand", gegen den diffed werden könnte — `changedFields` muss `nil`
    /// bleiben (volle Feldübertragung, kein Feld-Ebene-Tracking für Neuanlagen).
    @Test func saveBeiNeuanlageMarkiertKeineChangedFields() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        let store = SQLiteRuleStore(database: database)
        let rule = RuleRecord(
            id: "rule-1", name: "Neu", isEnabled: true, matchMode: RuleMatchMode.all.rawValue,
            action: "assignTag", assignTagID: nil, notificationTemplate: "{Titel}",
            notificationPriority: RuleNotificationPriority.normal.rawValue, sortOrder: 0, createdAt: Date()
        )
        try store.save(rule, conditions: [])

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "rule-1")
        // Whole-Branch-Review-Fund (Important 4c): siehe Kommentar oben — erst die Existenz der
        // Pending-Sync-Zeile selbst prüfen, bevor `changedFields == nil` ausgewertet wird.
        #expect(change != nil)
        #expect(change?.changedFields == nil)
    }

    /// Mehrzeilen-Fall 1: `save(_:conditions:)` ersetzt bei JEDER Speicherung ALLE Bedingungen
    /// einer Regel wholesale (DELETE + Re-Insert, siehe Kommentar in `SQLiteRuleStore.swift`).
    /// Diese Task diffed bewusst NUR die Rule-Felder selbst, nicht die einzelnen
    /// Bedingungszeilen — für `rule_conditions` bleibt es beim bisherigen Verhalten (volle
    /// Feldübertragung ohne Feld-Ebene-Tracking). Dieser Test liest den TATSÄCHLICH
    /// gespeicherten `changedFields`-Wert für mehrere betroffene Bedingungszeilen zurück, statt
    /// nur zu prüfen, dass sie pending sind — genau die Prüfung, die in den Fix-Runden von
    /// Task 7/8 anfangs fehlte.
    @Test func saveErsetztBedingungenWholesaleOhneChangedFieldsProZeile() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteRuleStore(database: database)
        let rule = RuleRecord(id: "rule-1", name: "Regel", sortOrder: 0)
        try store.save(
            rule,
            conditions: [
                RuleConditionRecord(id: "cond-a", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "alt-a"),
                RuleConditionRecord(id: "cond-b", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "alt-b")
            ]
        )
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        // Zweite Speicherung: 3 neue Bedingungszeilen (unabhängig von den alten IDs) ersetzen
        // die vorherigen 2 komplett.
        try store.save(
            rule,
            conditions: [
                RuleConditionRecord(id: "cond-x", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "neu-x"),
                RuleConditionRecord(id: "cond-y", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "neu-y"),
                RuleConditionRecord(id: "cond-z", ruleID: "rule-1", field: "title", conditionOperator: "contains", value: "neu-z")
            ]
        )

        let changeStore = CloudSyncPendingChangeStore(database: database)

        // Alte Bedingungszeilen: als gelöscht markiert, ohne changedFields.
        let changeA = try changeStore.pendingChange(recordName: "cond-a")
        #expect(changeA?.changeType == .delete)
        #expect(changeA?.changedFields == nil)
        let changeB = try changeStore.pendingChange(recordName: "cond-b")
        #expect(changeB?.changeType == .delete)
        #expect(changeB?.changedFields == nil)

        // Neue Bedingungszeilen: als gespeichert markiert, ohne changedFields (volle
        // Feldübertragung — kein Feld-Ebene-Tracking für rule_conditions in dieser Task).
        for recordName in ["cond-x", "cond-y", "cond-z"] {
            let change = try changeStore.pendingChange(recordName: recordName)
            #expect(change?.changeType == .save)
            #expect(change?.changedFields == nil)
        }
    }

    /// Mehrzeilen-Fall 2: `move(id:toPositionOf:)` schreibt bei jedem Aufruf für ALLE Regeln in
    /// der Liste ein frisches `sortOrder` (nicht nur für Quelle/Ziel), analog zu
    /// `FeedFolderStore.moveFolder`/`FeedStore.moveFeed` (Task 7/8). Prüft den tatsächlich
    /// gespeicherten `changedFields`-Wert für JEDE der drei betroffenen Regeln.
    @Test func moveMarkiertNurSortOrderFuerAlleBetroffenenRegeln() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteRuleStore(database: database)
        try store.save(RuleRecord(id: "rule-a", name: "Alpha", sortOrder: 0), conditions: [])
        try store.save(RuleRecord(id: "rule-b", name: "Bravo", sortOrder: 1), conditions: [])
        try store.save(RuleRecord(id: "rule-c", name: "Charlie", sortOrder: 2), conditions: [])
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.move(id: "rule-b", toPositionOf: "rule-a")

        let changeStore = CloudSyncPendingChangeStore(database: database)
        let changeA = try changeStore.pendingChange(recordName: "rule-a")
        #expect(changeA?.changedFields == ["sortOrder"])
        let changeB = try changeStore.pendingChange(recordName: "rule-b")
        #expect(changeB?.changedFields == ["sortOrder"])
        let changeC = try changeStore.pendingChange(recordName: "rule-c")
        #expect(changeC?.changedFields == ["sortOrder"])
    }
}
