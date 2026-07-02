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

    func debugForeignKeys(for tableName: String) throws -> [String] {
        let allowedTableName: String

        switch tableName {
        case "feeds", "articles", "article_statuses", "feed_logs", "tags", "article_tags":
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
