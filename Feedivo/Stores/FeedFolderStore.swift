import Foundation
import GRDB

struct FeedFolderStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func save(_ folder: FeedFolderRecord) throws {
        try database.write { db in
            var folder = folder
            try folder.save(db)
        }
    }

    func folders() throws -> [FeedFolderRecord] {
        try database.read { db in
            try FeedFolderRecord.fetchAll(db, sql: """
                SELECT *
                FROM feed_folders
                ORDER BY name COLLATE NOCASE, id COLLATE NOCASE
                """)
        }
    }

    func delete(id: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM feed_folders
                    WHERE id = ?
                    """,
                arguments: [id]
            )
        }
    }
}
