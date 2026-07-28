import Foundation
import Testing
@testable import Feedivo

/// iCloud-Sync-`changedFields`-Diffing-Tests für `SQLiteSmartFolderStore` (Phase 3, Task 10).
///
/// Spiegelt `SQLiteRuleStoreChangedFieldsTests` (Task 9) 1:1: `save(_:conditions:)` ist auch hier
/// ein genereller Upsert — der Intelligente-Ordner-Editor ruft ihn bei JEDER Speicherung auf,
/// egal welches Feld sich tatsächlich geändert hat. Diese Tests verifizieren, dass
/// `SQLiteSmartFolderStore` deshalb VOR dem Schreiben den bestehenden Ordner-Stand lädt und gegen
/// den neuen vergleicht, um `changedFields` korrekt (nur die tatsächlich geänderten Felder) zu
/// berechnen — sowie, dass die beiden Mehrzeilen-Fälle (Bedingungs-Ersetzung in `save`, Reorder
/// in `move`) das erwartete `changedFields` für JEDE betroffene Zeile speichern, nicht nur für
/// die zuerst geprüfte.
struct SQLiteSmartFolderStoreChangedFieldsTests {
    @Test func saveMarkiertNurTatsaechlichGeaenderteFelder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)
        let original = SmartFolderRecord(
            id: "folder-1", name: "Alt", matchMode: RuleMatchMode.all.rawValue,
            isShownInSidebar: true, isDefault: false, sortOrder: 0, defaultKey: nil,
            iconName: nil, colorHex: nil, defaultShowsReadArticles: false,
            createdAt: Date(), updatedAt: Date()
        )
        try store.save(original, conditions: [])
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        var updated = original
        updated.name = "Neu"
        try store.save(updated, conditions: [])

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-1")
        #expect(change?.changedFields == ["name"])
    }

    @Test func updateSidebarVisibilityMarkiertNurIsShownInSidebar() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)
        let folder = SmartFolderRecord(
            id: "folder-1", name: "Ordner", matchMode: RuleMatchMode.all.rawValue,
            isShownInSidebar: true, isDefault: false, sortOrder: 0, defaultKey: nil,
            iconName: nil, colorHex: nil, defaultShowsReadArticles: false,
            createdAt: Date(), updatedAt: Date()
        )
        try store.save(folder, conditions: [])
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.updateSidebarVisibility(id: "folder-1", isShownInSidebar: false)

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-1")
        #expect(change?.changedFields == ["isShownInSidebar"])
    }

    /// Regressionsschutz: eine erneute Speicherung mit IDENTISCHEM Inhalt (kein Feld hat sich
    /// geändert) darf keine leere `changedFields`-Liste erzeugen, die fälschlich als "kein Feld
    /// geändert, aber trotzdem Feld-Ebene-Tracking aktiv" interpretiert werden könnte —
    /// `changedSmartFolderFields` liefert `nil`, sobald die Diff-Liste leer ist (siehe
    /// `SQLiteSmartFolderStore.changedSmartFolderFields`).
    @Test func saveOhneAenderungMarkiertKeineFelder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)
        let folder = SmartFolderRecord(
            id: "folder-1", name: "Unverändert", matchMode: RuleMatchMode.all.rawValue,
            isShownInSidebar: true, isDefault: false, sortOrder: 0, defaultKey: nil,
            iconName: nil, colorHex: nil, defaultShowsReadArticles: false,
            createdAt: Date(), updatedAt: Date()
        )
        try store.save(folder, conditions: [])
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.save(folder, conditions: [])

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-1")
        #expect(change?.changedFields == nil)
    }

    /// Regressionsschutz für eine echte Neuanlage (keine vorherige Zeile existiert): hier gibt es
    /// keinen "alten Stand", gegen den diffed werden könnte — `changedFields` muss `nil` bleiben
    /// (volle Feldübertragung, kein Feld-Ebene-Tracking für Neuanlagen).
    @Test func saveBeiNeuanlageMarkiertKeineChangedFields() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        let store = SQLiteSmartFolderStore(database: database)
        let folder = SmartFolderRecord(
            id: "folder-1", name: "Neu", matchMode: RuleMatchMode.all.rawValue,
            isShownInSidebar: true, isDefault: false, sortOrder: 0, defaultKey: nil,
            iconName: nil, colorHex: nil, defaultShowsReadArticles: false,
            createdAt: Date(), updatedAt: Date()
        )
        try store.save(folder, conditions: [])

        let change = try CloudSyncPendingChangeStore(database: database).pendingChange(recordName: "folder-1")
        #expect(change?.changedFields == nil)
    }

    /// Mehrzeilen-Fall 1: `save(_:conditions:)` ersetzt bei JEDER Speicherung ALLE Bedingungen
    /// eines Ordners wholesale (DELETE + Re-Insert, siehe Kommentar in
    /// `SQLiteSmartFolderStore.swift`). Diese Task diffed bewusst NUR die Ordner-Felder selbst,
    /// nicht die einzelnen Bedingungszeilen — für `smart_folder_conditions` bleibt es beim
    /// bisherigen Verhalten (volle Feldübertragung ohne Feld-Ebene-Tracking). Dieser Test liest
    /// den TATSÄCHLICH gespeicherten `changedFields`-Wert für mehrere betroffene Bedingungszeilen
    /// zurück, statt nur zu prüfen, dass sie pending sind — genau die Prüfung, die in den
    /// Fix-Runden von Task 7/8 anfangs fehlte.
    @Test func saveErsetztBedingungenWholesaleOhneChangedFieldsProZeile() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)
        let folder = SmartFolderRecord(id: "folder-1", name: "Ordner", sortOrder: 0)
        try store.save(
            folder,
            conditions: [
                SmartFolderConditionRecord(id: "cond-a", smartFolderID: "folder-1", field: "title", conditionOperator: "contains", value: "alt-a"),
                SmartFolderConditionRecord(id: "cond-b", smartFolderID: "folder-1", field: "title", conditionOperator: "contains", value: "alt-b")
            ]
        )
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        // Zweite Speicherung: 3 neue Bedingungszeilen (unabhängig von den alten IDs) ersetzen die
        // vorherigen 2 komplett.
        try store.save(
            folder,
            conditions: [
                SmartFolderConditionRecord(id: "cond-x", smartFolderID: "folder-1", field: "title", conditionOperator: "contains", value: "neu-x"),
                SmartFolderConditionRecord(id: "cond-y", smartFolderID: "folder-1", field: "title", conditionOperator: "contains", value: "neu-y"),
                SmartFolderConditionRecord(id: "cond-z", smartFolderID: "folder-1", field: "title", conditionOperator: "contains", value: "neu-z")
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
        // Feldübertragung — kein Feld-Ebene-Tracking für smart_folder_conditions in dieser Task).
        for recordName in ["cond-x", "cond-y", "cond-z"] {
            let change = try changeStore.pendingChange(recordName: recordName)
            #expect(change?.changeType == .save)
            #expect(change?.changedFields == nil)
        }
    }

    /// Mehrzeilen-Fall 2: `move(id:toPositionOf:)` schreibt bei jedem Aufruf für ALLE
    /// (nicht-eingebauten) Ordner in der Liste ein frisches `sortOrder` (nicht nur für
    /// Quelle/Ziel), analog zu `SQLiteRuleStore.move` (Task 9). Prüft den tatsächlich
    /// gespeicherten `changedFields`-Wert für JEDEN der drei betroffenen Ordner.
    @Test func moveMarkiertNurSortOrderFuerAlleBetroffenenOrdner() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)
        try store.save(SmartFolderRecord(id: "folder-a", name: "Alpha", sortOrder: 0), conditions: [])
        try store.save(SmartFolderRecord(id: "folder-b", name: "Bravo", sortOrder: 1), conditions: [])
        try store.save(SmartFolderRecord(id: "folder-c", name: "Charlie", sortOrder: 2), conditions: [])
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.move(id: "folder-b", toPositionOf: "folder-a")

        let changeStore = CloudSyncPendingChangeStore(database: database)
        let changeA = try changeStore.pendingChange(recordName: "folder-a")
        #expect(changeA?.changedFields == ["sortOrder"])
        let changeB = try changeStore.pendingChange(recordName: "folder-b")
        #expect(changeB?.changedFields == ["sortOrder"])
        let changeC = try changeStore.pendingChange(recordName: "folder-c")
        #expect(changeC?.changedFields == ["sortOrder"])
    }

    /// Eingebaute Ordner (`isDefault == true`) syncen nie (siehe Kommentar in
    /// `SQLiteSmartFolderStore.swift`) — `move` darf für sie deshalb auch kein
    /// `changedFields`-Tracking anstoßen, unabhängig davon, dass sich ihr `sortOrder` beim
    /// gemeinsamen Reorder ebenfalls ändert.
    @Test func moveEnqueuedNichtsFuerEingebauteOrdner() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)
        try store.save(SmartFolderRecord(id: "folder-default", name: "Ungelesen", isDefault: true, sortOrder: 0), conditions: [])
        try store.save(SmartFolderRecord(id: "folder-b", name: "Bravo", isDefault: false, sortOrder: 1), conditions: [])
        UserDefaults.standard.set(true, forKey: CloudSyncSettings.isEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudSyncSettings.isEnabledKey) }

        try store.move(id: "folder-b", toPositionOf: "folder-default")

        let changeStore = CloudSyncPendingChangeStore(database: database)
        let changeDefault = try changeStore.pendingChange(recordName: "folder-default")
        #expect(changeDefault == nil)
    }
}
