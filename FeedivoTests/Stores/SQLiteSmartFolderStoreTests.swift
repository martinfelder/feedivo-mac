import Foundation
import GRDB
import Testing
@testable import Feedivo

/// iCloud-Sync-Wiring-Tests für `SQLiteSmartFolderStore` (Phase 2a, Task 7). Basis-
/// Funktionalität (Speichern/Duplizieren/Verschieben ohne Sync) ist bereits in
/// `SQLiteAdminStoreTests.swift` abgedeckt — diese Datei testet ausschließlich das
/// Enqueue-Verhalten für `CloudSyncPendingChangeStore`, analog zu `SQLiteRuleStoreTests.swift`
/// (Task 6). Zentrale Besonderheit gegenüber Regeln: `smart_folders` hat eingebaute
/// Default-Ordner (`isDefault == true`), die NIE syncen dürfen — die meisten Tests hier prüfen
/// deshalb explizit das Gate, nicht nur den "passiert etwas"-Fall.
struct SQLiteSmartFolderStoreTests {
    @Test func saveMarkiertBenutzerdefiniertenOrdnerUndBedingungenAlsPendingSyncWennAktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try CloudSyncSettingsStore(database: database).setEnabled(true)

        let store = SQLiteSmartFolderStore(database: database)
        try store.save(
            SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", isDefault: false, sortOrder: 0),
            conditions: [
                SmartFolderConditionRecord(id: "cond-1", smartFolderID: "folder-1", field: "status", conditionOperator: "is", value: "unread")
            ]
        )

        let pendingIDs = Set(try CloudSyncPendingChangeStore(database: database).pendingChanges().map(\.id))
        #expect(pendingIDs == Set(["folder-1", "cond-1"]))
    }

    @Test func saveMarkiertNichtsWennSyncDeaktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        // Eine frische In-Memory-Testdatenbank steht nach Migration v33 deterministisch auf
        // "aus" — kein explizites Zurücksetzen mehr nötig.

        let store = SQLiteSmartFolderStore(database: database)
        try store.save(
            SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", isDefault: false, sortOrder: 0),
            conditions: [
                SmartFolderConditionRecord(id: "cond-1", smartFolderID: "folder-1", field: "status", conditionOperator: "is", value: "unread")
            ]
        )

        #expect(try CloudSyncPendingChangeStore(database: database).pendingChanges().isEmpty)
    }

    /// Kernklausel dieses Stores: ein Speichervorgang für einen EINGEBAUTEN Ordner darf NIE
    /// enqueuen, selbst wenn Sync aktiviert ist — nur die fachliche Mutation läuft.
    @Test func saveMarkiertNichtsFuerDefaultOrdnerAuchWennSyncAktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try CloudSyncSettingsStore(database: database).setEnabled(true)

        let store = SQLiteSmartFolderStore(database: database)
        try store.save(
            SmartFolderRecord(id: "folder-default", name: "Ungelesen", isDefault: true, sortOrder: 0, defaultKey: "unread"),
            conditions: [
                SmartFolderConditionRecord(id: "cond-default", smartFolderID: "folder-default", field: "status", conditionOperator: "is", value: "unread")
            ]
        )

        #expect(try CloudSyncPendingChangeStore(database: database).pendingChanges().isEmpty)
    }

    @Test func saveBeimBearbeitenMarkiertAlteBedingungenAlsDeleteUndNeueAlsSave() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)
        try store.save(
            SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", isDefault: false, sortOrder: 0),
            conditions: [
                SmartFolderConditionRecord(id: "cond-alt", smartFolderID: "folder-1", field: "status", conditionOperator: "is", value: "unread")
            ]
        )

        try CloudSyncSettingsStore(database: database).setEnabled(true)

        // Editieren: Bedingungsliste wird komplett ersetzt (bestehendes save()-Verhalten:
        // delete-all-then-reinsert) — die alte Bedingungs-ID muss als .delete enqueued
        // werden, die neue als .save.
        try store.save(
            SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", isDefault: false, sortOrder: 0),
            conditions: [
                SmartFolderConditionRecord(id: "cond-neu", smartFolderID: "folder-1", field: "status", conditionOperator: "is", value: "starred")
            ]
        )

        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        let byID = Dictionary(uniqueKeysWithValues: pending.map { ($0.id, $0.changeType) })
        #expect(byID["cond-alt"] == .delete)
        #expect(byID["cond-neu"] == .save)
        #expect(byID["folder-1"] == .save)
    }

    @Test func updateSidebarVisibilityMarkiertBenutzerdefiniertenOrdnerAlsPendingSync() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)
        try store.save(SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", isDefault: false, sortOrder: 0), conditions: [])

        try CloudSyncSettingsStore(database: database).setEnabled(true)

        try store.updateSidebarVisibility(id: "folder-1", isShownInSidebar: false)

        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        #expect(pending.map(\.id) == ["folder-1"])
        #expect(pending.first?.changeType == .save)
    }

    @Test func updateSidebarVisibilityMarkiertNichtsFuerDefaultOrdner() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)
        try store.restoreDefaultFolders()
        let defaultFolder = try #require(try store.folders().first { $0.defaultKey == "unread" })

        try CloudSyncSettingsStore(database: database).setEnabled(true)

        try store.updateSidebarVisibility(id: defaultFolder.id, isShownInSidebar: false)

        #expect(try CloudSyncPendingChangeStore(database: database).pendingChanges().isEmpty)
        // Die fachliche Mutation muss trotzdem stattgefunden haben.
        let reloaded = try store.folder(id: defaultFolder.id)
        #expect(reloaded?.isShownInSidebar == false)
    }

    @Test func moveMarkiertNurBenutzerdefinierteBetroffeneOrdnerAlsPendingSync() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)
        try store.restoreDefaultFolders()
        let defaultFolder = try #require(try store.folders().first { $0.defaultKey == "unread" })
        try store.save(SmartFolderRecord(id: "folder-a", name: "A", isDefault: false, sortOrder: 100), conditions: [])
        try store.save(SmartFolderRecord(id: "folder-b", name: "B", isDefault: false, sortOrder: 101), conditions: [])

        try CloudSyncSettingsStore(database: database).setEnabled(true)

        // Verschiebt "folder-b" an die Position des eingebauten Ordners — alle dazwischen
        // liegenden Ordner (inkl. des Default-Ordners selbst) bekommen ein neues sortOrder,
        // aber nur die benutzerdefinierten dürfen enqueuen.
        try store.move(id: "folder-b", toPositionOf: defaultFolder.id)

        let pendingIDs = Set(try CloudSyncPendingChangeStore(database: database).pendingChanges().map(\.id))
        #expect(!pendingIDs.contains(defaultFolder.id))
        #expect(pendingIDs.contains("folder-b"))
    }

    // `smart_folder_conditions.smartFolderID` hat `ON DELETE CASCADE` — die Kaskade selbst muss
    // tatsächlich stattgefunden haben, sonst wäre der Test ein Blindgänger (die Bedingung
    // könnte theoretisch noch existieren, obwohl ihre Löschung bereits enqueued wurde).
    @Test func deleteBenutzerdefiniertenOrdnerEnqueuedLoeschungenFuerOrdnerUndAlleBedingungen() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try CloudSyncSettingsStore(database: database).setEnabled(true)

        let store = SQLiteSmartFolderStore(database: database)
        let folder = SmartFolderRecord(id: "folder-1", name: "Meine Auswahl", isDefault: false)
        let condition = SmartFolderConditionRecord(id: "cond-1", smartFolderID: "folder-1", field: "status", conditionOperator: "is", value: "unread")
        try store.save(folder, conditions: [condition])

        try store.delete(id: "folder-1")

        let pendingDeletes = try CloudSyncPendingChangeStore(database: database).pendingChanges()
            .filter { $0.changeType == .delete }
            .map(\.id)
        #expect(Set(pendingDeletes) == Set(["folder-1", "cond-1"]))

        let remainingCondition = try database.read { db in
            try SmartFolderConditionRecord.fetchOne(db, sql: "SELECT * FROM smart_folder_conditions WHERE id = ?", arguments: ["cond-1"])
        }
        #expect(remainingCondition == nil)
    }

    /// Kernklausel: Löschen eines eingebauten Ordners darf nie enqueuen, auch wenn er
    /// (theoretisch) Bedingungen hat — die fachliche Kaskaden-Löschung selbst läuft unverändert.
    @Test func deleteDefaultOrdnerEnqueuedNichts() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)
        try store.restoreDefaultFolders()
        let defaultFolder = try #require(try store.folders().first { $0.defaultKey == "unread" })

        try CloudSyncSettingsStore(database: database).setEnabled(true)

        try store.delete(id: defaultFolder.id)

        #expect(try CloudSyncPendingChangeStore(database: database).pendingChanges().isEmpty)
        #expect(try store.folder(id: defaultFolder.id) == nil)
    }

    @Test func duplicateMarkiertNeuenOrdnerUndBedingungenImmerAlsPendingSync() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)
        try store.save(
            SmartFolderRecord(id: "folder-1", name: "Original", isDefault: false, sortOrder: 0),
            conditions: [
                SmartFolderConditionRecord(id: "cond-1", smartFolderID: "folder-1", field: "status", conditionOperator: "is", value: "unread")
            ]
        )

        try CloudSyncSettingsStore(database: database).setEnabled(true)

        let duplicate = try store.duplicate(id: "folder-1", copyName: "Kopie")
        let duplicateConditionID = try store.conditions(folderID: duplicate.id).first?.id

        let pending = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        let byID = Dictionary(uniqueKeysWithValues: pending.map { ($0.id, $0.changeType) })
        #expect(duplicate.isDefault == false)
        #expect(byID[duplicate.id] == .save)
        if let duplicateConditionID {
            #expect(byID[duplicateConditionID] == .save)
        } else {
            Issue.record("Erwartete duplizierte Bedingung wurde nicht gefunden")
        }
    }

    /// `duplicate` einer eingebauten Vorlage erzeugt trotzdem eine benutzerdefinierte Kopie
    /// (`isDefault: false`, siehe Konstruktor in `SQLiteSmartFolderStore.duplicate`) — muss
    /// also IMMER enqueuen, unabhängig davon, ob die Quelle ein Default-Ordner war.
    @Test func duplicateEinesDefaultOrdnersErzeugtBenutzerdefinierteKopieUndEnqueuedSie() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = SQLiteSmartFolderStore(database: database)
        try store.restoreDefaultFolders()
        let defaultFolder = try #require(try store.folders().first { $0.defaultKey == "unread" })

        try CloudSyncSettingsStore(database: database).setEnabled(true)

        let duplicate = try store.duplicate(id: defaultFolder.id, copyName: "Kopie von Ungelesen")

        #expect(duplicate.isDefault == false)
        #expect(duplicate.defaultKey == nil)
        let pendingIDs = Set(try CloudSyncPendingChangeStore(database: database).pendingChanges().map(\.id))
        #expect(pendingIDs.contains(duplicate.id))
    }

    /// Mandatorischer Regressionstest: `restoreDefaultFolders()` legt ausschließlich
    /// `isDefault: true`-Ordner an, die nie syncen sollen — die Methode selbst bleibt
    /// bewusst unverändert (kein Enqueue-Code) und darf deshalb auch bei aktiviertem Sync
    /// niemals eine ausstehende Änderung erzeugen.
    @Test func restoreDefaultFoldersEnqueuedNiemalsPendingSync() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try CloudSyncSettingsStore(database: database).setEnabled(true)

        let store = SQLiteSmartFolderStore(database: database)
        try store.restoreDefaultFolders()

        let pendingChanges = try CloudSyncPendingChangeStore(database: database).pendingChanges()
        #expect(pendingChanges.isEmpty)

        // Die fachliche Wirkung selbst muss trotzdem stattgefunden haben — sonst wäre der
        // Test ein Blindgänger (kein Ordner angelegt, also naturgemäß nichts enqueued).
        #expect(try store.folders().contains { $0.defaultKey == "unread" })
    }
}
