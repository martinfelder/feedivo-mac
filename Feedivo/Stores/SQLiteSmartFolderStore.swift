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
                    }
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
}
