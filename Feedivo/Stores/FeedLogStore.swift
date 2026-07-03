import Foundation
import GRDB

struct FeedLogStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func append(_ log: FeedLogRecord) throws {
        try database.write { db in
            var log = log
            try log.insert(db)
        }
    }

    func logs(feedID: String, limit: Int) throws -> [FeedLogRecord] {
        try database.read { db in
            try FeedLogRecord.fetchAll(db, sql: """
                SELECT *
                FROM feed_logs
                WHERE feedID = ?
                ORDER BY createdAt DESC, id COLLATE NOCASE DESC
                LIMIT ?
                """, arguments: [feedID, max(1, limit)])
        }
    }
}
