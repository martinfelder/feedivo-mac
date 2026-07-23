import Foundation
import GRDB

struct FeedivoDatabase {
    enum DebugTableInspectionError: Error {
        case unsupportedTableName(String)
    }

    private let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    static func open(at fileURL: URL) throws -> FeedivoDatabase {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let queue = try DatabaseQueue(path: fileURL.path, configuration: configuration)
        try FeedivoDatabaseMigrator.migrator.migrate(queue)
        return FeedivoDatabase(writer: queue)
    }

    static func inMemoryForTests() throws -> FeedivoDatabase {
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let queue = try DatabaseQueue(configuration: configuration)
        try FeedivoDatabaseMigrator.migrator.migrate(queue)
        return FeedivoDatabase(writer: queue)
    }

    func read<Value>(_ block: (Database) throws -> Value) throws -> Value {
        try writer.read(block)
    }

    /// Führt einen Read auf GRDBs eigener Datenbank-Queue aus. Aufrufer können
    /// dadurch nur die Ergebnisübernahme auf dem Main Actor halten, ohne die
    /// eigentliche SQL-Abfrage dort zu blockieren.
    func readAsync<Value: Sendable>(
        _ block: @escaping @Sendable (Database) throws -> Value
    ) async throws -> Value {
        try await writer.read(block)
    }

    func write<Value>(_ block: (Database) throws -> Value) throws -> Value {
        try writer.write(block)
    }

    func debugTableNames() throws -> Set<String> {
        try read { database in
            let rows = try Row.fetchAll(database, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table'
                """)
            return Set(rows.compactMap { row in row["name"] as String? })
        }
    }

    func debugIndexNames() throws -> Set<String> {
        try read { database in
            let rows = try Row.fetchAll(database, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'index'
                """)
            return Set(rows.compactMap { row in row["name"] as String? })
        }
    }

    func debugTriggerNames() throws -> Set<String> {
        try read { database in
            let rows = try Row.fetchAll(database, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'trigger'
                """)
            return Set(rows.compactMap { row in row["name"] as String? })
        }
    }

    func debugForeignKeys(for tableName: String) throws -> [String] {
        let allowedTableName: String

        switch tableName {
        case "feeds",
             "articles",
             "article_statuses",
             "feed_logs",
             "tags",
             "article_tags",
             "feed_tags",
             "feed_folders",
             "rules",
             "rule_conditions",
             "smart_folders",
             "smart_folder_conditions":
            allowedTableName = tableName
        default:
            throw DebugTableInspectionError.unsupportedTableName(tableName)
        }

        return try read { database in
            let rows = try Row.fetchAll(database, sql: "PRAGMA foreign_key_list(\(allowedTableName))")
            return rows.compactMap { row in row["table"] as String? }
        }
    }
}
