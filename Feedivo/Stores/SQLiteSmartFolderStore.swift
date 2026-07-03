import Foundation
import GRDB

struct SQLiteSmartFolderStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func save(_ folder: SmartFolderRecord, conditions: [SmartFolderConditionRecord]) throws {
        try database.write { db in
            var folder = folder
            try folder.save(db)

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
            }
        }
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
        }
    }

    func duplicate(id: String, copyName: String) throws -> SmartFolderRecord {
        try database.write { db in
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
                colorHex: source.colorHex
            )
            try duplicate.insert(db)

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
            }

            return duplicate
        }
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
            }
        }
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
                    colorHex: definition.colorHex
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

    func delete(id: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM smart_folders
                    WHERE id = ?
                    """,
                arguments: [id]
            )
        }
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
                    defaultKey: folder.defaultKey
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
            conditions: []
        ),
        DefaultSmartFolderDefinition(
            name: "Ungelesen",
            matchMode: .all,
            defaultKey: "unread",
            iconName: "circle.fill",
            colorHex: "#14B8A6",
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
    let conditions: [DefaultSmartFolderCondition]
}

private struct DefaultSmartFolderCondition {
    let field: SmartFolderConditionField
    let conditionOperator: SmartFolderConditionOperator
    let value: String
}
