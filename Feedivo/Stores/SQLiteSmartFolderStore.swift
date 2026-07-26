import Foundation
import GRDB

struct SQLiteSmartFolderStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    /// Markiert eine lokale Ordner- oder Bedingungszeile als ausstehende Sync-Änderung, falls
    /// iCloud Sync aktiv ist. Läuft bewusst INNERHALB derselben `database.write`-Transaktion
    /// wie die fachliche Mutation — analog zu `FeedStore`/`FeedFolderStore`/`TagStore`/
    /// `SQLiteRuleStore`.
    private func enqueuePendingSync(_ db: Database, recordType: String, recordName: String, changeType: CloudSyncChangeType, changedFields: [String]? = nil) throws {
        guard CloudSyncSettings.isEnabled() else { return }
        try CloudSyncPendingChangeStore.enqueue(db, recordType: recordType, recordName: recordName, changeType: changeType, changedFields: changedFields)
    }

    // `smart_folder_conditions.smartFolderID` hat `ON DELETE CASCADE` (`PRAGMA foreign_keys = ON`
    // ist aktiv, siehe FeedivoDatabase.swift) — die alten Bedingungs-IDs müssen deshalb VOR dem
    // `DELETE FROM smart_folder_conditions` ermittelt und als `.delete` enqueued werden, sonst
    // sind sie danach nicht mehr abfragbar. Eingebaute Ordner (`isDefault == true`) syncen nie —
    // NUR das Enqueuen wird deshalb übersprungen (`guard !folder.isDefault` VOR jedem
    // `enqueuePendingSync`-Aufruf), das Delete-all-then-reinsert-Verhalten für Bedingungen
    // läuft unverändert für ALLE Ordner (default oder nicht) — ein früherer Entwurf, der die
    // komplette Bedingungslogik hinter einem einzigen `guard !folder.isDefault else { return }`
    // versteckte, brach `smartFolderStoreSpeichertOrdnerMitConditionsUndSnapshots()` in
    // `SQLiteAdminStoreTests.swift` (ein Aufruf mit `isDefault: true` UND Bedingungen), weil er
    // die Bedingungen für Default-Ordner gar nicht mehr persistierte.
    //
    // `save(_:conditions:)` ist ein genereller Upsert — der Intelligente-Ordner-Editor ruft ihn
    // bei JEDER Speicherung auf, egal welches Feld sich geändert hat (anders als bei
    // Tag/Feed/FeedFolder, wo jede Store-Methode genau ein Feld ändert). Deshalb wird VOR dem
    // Schreiben der bestehende Ordner-Stand geladen und per `changedSmartFolderFields` gegen den
    // neuen verglichen, um `changedFields` korrekt zu berechnen — analog zu `SQLiteRuleStore`
    // (Task 9). Die Bedingungszeilen selbst bleiben bewusst außerhalb dieses Diffs — sie werden
    // wholesale ersetzt (DELETE + Re-Insert), ein Feld-Ebene-Diff pro Bedingungszeile ist nicht
    // Teil dieser Aufgabe.
    func save(_ folder: SmartFolderRecord, conditions: [SmartFolderConditionRecord]) throws {
        try database.write { db in
            let existingFolder = try Self.fetchFolders(db).first { $0.id == folder.id }
            var folder = folder
            try folder.save(db)

            if !folder.isDefault {
                try enqueuePendingSync(db, recordType: CloudSyncSmartFolderMapping.recordType, recordName: folder.id, changeType: .save, changedFields: Self.changedSmartFolderFields(old: existingFolder, new: folder))
            }

            let existingConditionIDs = try String.fetchAll(db, sql: "SELECT id FROM smart_folder_conditions WHERE smartFolderID = ?", arguments: [folder.id])
            if !folder.isDefault {
                for conditionID in existingConditionIDs {
                    try enqueuePendingSync(db, recordType: CloudSyncSmartFolderConditionMapping.recordType, recordName: conditionID, changeType: .delete)
                }
            }

            try db.execute(
                sql: """
                    DELETE FROM smart_folder_conditions
                    WHERE smartFolderID = ?
                    """,
                arguments: [folder.id]
            )

            for condition in conditions {
                var condition = condition
                condition.smartFolderID = folder.id
                try condition.insert(db)
                if !folder.isDefault {
                    try enqueuePendingSync(db, recordType: CloudSyncSmartFolderConditionMapping.recordType, recordName: condition.id, changeType: .save)
                }
            }
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    /// Vergleicht den alten gegen den neuen Ordner-Stand und liefert exakt die Feldnamen, die
    /// sich tatsächlich geändert haben — `nil` (kein Tracking) falls `existingFolder` `nil` ist
    /// (echte Neuanlage, kein Feld-Merge sinnvoll) oder sich kein Feld geändert hat. Feldnamen
    /// entsprechen exakt den CKRecord-Schlüsseln aus `CloudSyncSmartFolderMapping.makeCKRecord`.
    private static func changedSmartFolderFields(old existingFolder: SmartFolderRecord?, new folder: SmartFolderRecord) -> [String]? {
        guard let existingFolder else { return nil }
        var changed: [String] = []
        if existingFolder.name != folder.name { changed.append("name") }
        if existingFolder.matchMode != folder.matchMode { changed.append("matchMode") }
        if existingFolder.isShownInSidebar != folder.isShownInSidebar { changed.append("isShownInSidebar") }
        if existingFolder.sortOrder != folder.sortOrder { changed.append("sortOrder") }
        if existingFolder.iconName != folder.iconName { changed.append("iconName") }
        if existingFolder.colorHex != folder.colorHex { changed.append("colorHex") }
        if existingFolder.defaultShowsReadArticles != folder.defaultShowsReadArticles { changed.append("defaultShowsReadArticles") }
        return changed.isEmpty ? nil : changed
    }

    func folders() throws -> [SmartFolderRecord] {
        try database.read { db in
            try Self.fetchFolders(db)
        }
    }

    func conditions(folderID: String) throws -> [SmartFolderConditionRecord] {
        try database.read { db in
            try Self.fetchConditions(db, folderID: folderID)
        }
    }

    func folder(id: String) throws -> SmartFolderRecord? {
        try database.read { db in
            try SmartFolderRecord.fetchOne(db, sql: """
                SELECT *
                FROM smart_folders
                WHERE id = ?
                """, arguments: [id])
        }
    }

    func updateSidebarVisibility(id: String, isShownInSidebar: Bool) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE smart_folders
                    SET isShownInSidebar = ?, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [isShownInSidebar, Date(), id]
            )

            let isDefault = try Bool.fetchOne(db, sql: "SELECT isDefault FROM smart_folders WHERE id = ?", arguments: [id]) ?? true
            guard !isDefault else { return }
            try enqueuePendingSync(db, recordType: CloudSyncSmartFolderMapping.recordType, recordName: id, changeType: .save, changedFields: ["isShownInSidebar"])
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    // Die Kopie ist immer `isDefault: false` (siehe Konstruktor unten) — enqueued deshalb
    // IMMER, unabhängig davon, ob der Quell-Ordner selbst ein eingebauter Ordner war.
    // `database.write { ... }` reicht hier den Rückgabewert des Closures (`SmartFolderRecord`)
    // durch — `notifyPendingChangesAvailable` steht deshalb NACH dem `write`-Aufruf, nicht darin.
    func duplicate(id: String, copyName: String) throws -> SmartFolderRecord {
        let duplicate = try database.write { db -> SmartFolderRecord in
            guard let source = try SmartFolderRecord.fetchOne(db, sql: """
                SELECT *
                FROM smart_folders
                WHERE id = ?
                """, arguments: [id])
            else {
                throw SQLiteSmartFolderStoreError.missingFolder
            }

            let maxSortOrder = (try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM smart_folders") ?? -1) + 1
            let duplicateID = UUID().uuidString
            var duplicate = SmartFolderRecord(
                id: duplicateID,
                name: copyName,
                matchMode: source.matchMode,
                isShownInSidebar: source.isShownInSidebar,
                isDefault: false,
                sortOrder: maxSortOrder,
                defaultKey: nil,
                iconName: source.iconName,
                colorHex: source.colorHex,
                defaultShowsReadArticles: source.defaultShowsReadArticles
            )
            try duplicate.insert(db)
            try enqueuePendingSync(db, recordType: CloudSyncSmartFolderMapping.recordType, recordName: duplicateID, changeType: .save)

            let conditions = try Self.fetchConditions(db, folderID: source.id)
            for (index, condition) in conditions.enumerated() {
                var copiedCondition = SmartFolderConditionRecord(
                    id: UUID().uuidString,
                    smartFolderID: duplicateID,
                    field: condition.field,
                    conditionOperator: condition.conditionOperator,
                    value: condition.value,
                    sortOrder: index
                )
                try copiedCondition.insert(db)
                try enqueuePendingSync(db, recordType: CloudSyncSmartFolderConditionMapping.recordType, recordName: copiedCondition.id, changeType: .save)
            }

            return duplicate
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
        return duplicate
    }

    func move(id sourceID: String, toPositionOf targetID: String) throws {
        try database.write { db in
            var folders = try Self.fetchFolders(db)
            guard sourceID != targetID,
                  let sourceIndex = folders.firstIndex(where: { $0.id == sourceID }),
                  let targetIndex = folders.firstIndex(where: { $0.id == targetID })
            else {
                return
            }

            let movedFolder = folders.remove(at: sourceIndex)
            folders.insert(movedFolder, at: targetIndex)

            for (index, folder) in folders.enumerated() {
                try db.execute(
                    sql: """
                        UPDATE smart_folders
                        SET sortOrder = ?, updatedAt = ?
                        WHERE id = ?
                        """,
                    arguments: [index, Date(), folder.id]
                )
                guard !folder.isDefault else { continue }
                try enqueuePendingSync(db, recordType: CloudSyncSmartFolderMapping.recordType, recordName: folder.id, changeType: .save, changedFields: ["sortOrder"])
            }
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func restoreDefaultFolders() throws {
        try database.write { db in
            let existingFolders = try Self.fetchFolders(db)
            let existingDefaultKeys = Set(existingFolders.compactMap(\.defaultKey))
            var nextSortOrder = (existingFolders.map(\.sortOrder).max() ?? -1) + 1

            for definition in Self.defaultFolderDefinitions where !existingDefaultKeys.contains(definition.defaultKey) {
                let folderID = UUID().uuidString
                var folder = SmartFolderRecord(
                    id: folderID,
                    name: definition.name,
                    matchMode: definition.matchMode.rawValue,
                    isShownInSidebar: true,
                    isDefault: true,
                    sortOrder: nextSortOrder,
                    defaultKey: definition.defaultKey,
                    iconName: definition.iconName,
                    colorHex: definition.colorHex,
                    defaultShowsReadArticles: definition.defaultShowsReadArticles
                )
                try folder.insert(db)

                for (index, condition) in definition.conditions.enumerated() {
                    var condition = SmartFolderConditionRecord(
                        id: UUID().uuidString,
                        smartFolderID: folderID,
                        field: condition.field.rawValue,
                        conditionOperator: condition.conditionOperator.rawValue,
                        value: condition.value,
                        sortOrder: index
                    )
                    try condition.insert(db)
                }

                nextSortOrder += 1
            }
        }
    }

    // `smart_folder_conditions.smartFolderID` hat `ON DELETE CASCADE` — die betroffenen
    // Bedingungs-IDs müssen VOR dem `DELETE FROM smart_folders`-Statement ermittelt und als
    // `.delete` enqueued werden, weil SQLite ihre Zeilen bei diesem einen Statement bereits
    // mitlöscht (siehe Doku oben bei `save`). Eingebaute Ordner (`isDefault == true`) syncen
    // nie — die fachliche Löschung läuft trotzdem für ALLE Ordner, nur ohne Enqueue.
    func delete(id: String) throws {
        try database.write { db in
            let isDefault = try Bool.fetchOne(db, sql: "SELECT isDefault FROM smart_folders WHERE id = ?", arguments: [id]) ?? true

            if !isDefault {
                let conditionIDs = try String.fetchAll(db, sql: "SELECT id FROM smart_folder_conditions WHERE smartFolderID = ?", arguments: [id])
                for conditionID in conditionIDs {
                    try enqueuePendingSync(db, recordType: CloudSyncSmartFolderConditionMapping.recordType, recordName: conditionID, changeType: .delete)
                }
                try enqueuePendingSync(db, recordType: CloudSyncSmartFolderMapping.recordType, recordName: id, changeType: .delete)
            }

            try db.execute(
                sql: """
                    DELETE FROM smart_folders
                    WHERE id = ?
                    """,
                arguments: [id]
            )
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func sidebarSnapshots() throws -> [SQLiteSmartFolderSnapshot] {
        try database.read { db in
            let folders = try SmartFolderRecord.fetchAll(db, sql: """
                SELECT *
                FROM smart_folders
                WHERE isShownInSidebar = 1
                ORDER BY sortOrder, name COLLATE NOCASE, id COLLATE NOCASE
                """)

            return try folders.map { folder in
                let conditions = try Self.fetchConditions(db, folderID: folder.id)
                return SQLiteSmartFolderSnapshot(
                    id: folder.id,
                    name: folder.name,
                    matchMode: RuleMatchMode.normalized(folder.matchMode),
                    conditions: conditions.compactMap { condition in
                        guard let field = SmartFolderConditionField(rawValue: condition.field),
                              let conditionOperator = SmartFolderConditionOperator(rawValue: condition.conditionOperator)
                        else {
                            return nil
                        }

                        return SQLiteSmartFolderConditionSnapshot(
                            field: field,
                            conditionOperator: conditionOperator,
                            value: condition.value
                        )
                    },
                    iconName: folder.iconName,
                    colorHex: folder.colorHex,
                    defaultKey: folder.defaultKey,
                    defaultShowsReadArticles: folder.defaultShowsReadArticles
                )
            }
        }
    }

    private static func fetchFolders(_ db: Database) throws -> [SmartFolderRecord] {
        try SmartFolderRecord.fetchAll(db, sql: """
            SELECT *
            FROM smart_folders
            ORDER BY sortOrder, name COLLATE NOCASE, id COLLATE NOCASE
            """)
    }

    private static func fetchConditions(_ db: Database, folderID: String) throws -> [SmartFolderConditionRecord] {
        try SmartFolderConditionRecord.fetchAll(db, sql: """
            SELECT *
            FROM smart_folder_conditions
            WHERE smartFolderID = ?
            ORDER BY sortOrder, id COLLATE NOCASE
            """, arguments: [folderID])
    }

    private static let defaultFolderDefinitions: [DefaultSmartFolderDefinition] = [
        DefaultSmartFolderDefinition(
            name: "Alle Artikel",
            matchMode: .all,
            defaultKey: "all",
            iconName: "tray.full",
            colorHex: "#3B82F6",
            defaultShowsReadArticles: false,
            conditions: []
        ),
        DefaultSmartFolderDefinition(
            name: "Ungelesen",
            matchMode: .all,
            defaultKey: "unread",
            iconName: "circle.fill",
            colorHex: "#14B8A6",
            defaultShowsReadArticles: false,
            conditions: [
                DefaultSmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.unread.rawValue
                )
            ]
        ),
        DefaultSmartFolderDefinition(
            name: "Mit Stern",
            matchMode: .all,
            defaultKey: "starred",
            iconName: "star.fill",
            colorHex: "#F59E0B",
            defaultShowsReadArticles: true,
            conditions: [
                DefaultSmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.starred.rawValue
                )
            ]
        ),
        DefaultSmartFolderDefinition(
            name: "Heute",
            matchMode: .all,
            defaultKey: "today",
            iconName: "calendar",
            colorHex: "#22C55E",
            defaultShowsReadArticles: false,
            conditions: [
                DefaultSmartFolderCondition(
                    field: .date,
                    conditionOperator: .is,
                    value: SmartFolderDateValue.today.rawValue
                )
            ]
        ),
        DefaultSmartFolderDefinition(
            name: "Ausgeblendet",
            matchMode: .all,
            defaultKey: "hidden",
            iconName: "eye.slash",
            colorHex: "#6B7280",
            defaultShowsReadArticles: true,
            conditions: [
                DefaultSmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.hidden.rawValue
                )
            ]
        ),
        DefaultSmartFolderDefinition(
            name: "Archiviert",
            matchMode: .all,
            defaultKey: "archived",
            iconName: "archivebox",
            colorHex: "#8B5CF6",
            defaultShowsReadArticles: false,
            conditions: [
                DefaultSmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.archived.rawValue
                )
            ]
        ),
        DefaultSmartFolderDefinition(
            name: "Diese Woche",
            matchMode: .all,
            defaultKey: "thisWeek",
            iconName: "calendar",
            colorHex: "#22C55E",
            defaultShowsReadArticles: true,
            conditions: [
                DefaultSmartFolderCondition(
                    field: .date,
                    conditionOperator: .is,
                    value: SmartFolderDateValue.thisWeek.rawValue
                )
            ]
        ),
        DefaultSmartFolderDefinition(
            name: "Gespeichert",
            matchMode: .any,
            defaultKey: "saved",
            iconName: "bookmark",
            colorHex: "#F97316",
            defaultShowsReadArticles: true,
            conditions: [
                DefaultSmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.starred.rawValue
                ),
                DefaultSmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.archived.rawValue
                )
            ]
        )
    ]
}

enum SQLiteSmartFolderStoreError: Error, Equatable {
    case missingFolder
}

private struct DefaultSmartFolderDefinition {
    let name: String
    let matchMode: RuleMatchMode
    let defaultKey: String
    let iconName: String
    let colorHex: String
    let defaultShowsReadArticles: Bool
    let conditions: [DefaultSmartFolderCondition]
}

private struct DefaultSmartFolderCondition {
    let field: SmartFolderConditionField
    let conditionOperator: SmartFolderConditionOperator
    let value: String
}
