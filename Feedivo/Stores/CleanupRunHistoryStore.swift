import Foundation
import GRDB

// Ein Store pro Tabelle (Projektkonvention, siehe FeedLogStore). Hält nur die neuesten
// maxEntries Läufe — ältere werden bei jedem neuen Eintrag automatisch entfernt, damit
// die History der Einstellungen-Liste nie unbegrenzt wächst.
struct CleanupRunHistoryStore {
    static let maxEntries = 10

    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func record(
        triggerSource: CleanupRunTrigger,
        deletedCount: Int,
        succeeded: Bool,
        errorMessage: String?,
        now: Date = Date()
    ) throws {
        try database.write { db in
            var run = CleanupRunRecord(
                executedAt: now,
                deletedCount: deletedCount,
                triggerSource: triggerSource.rawValue,
                succeeded: succeeded,
                errorMessage: errorMessage
            )
            try run.insert(db)

            try db.execute(sql: """
                DELETE FROM cleanup_runs
                WHERE id NOT IN (
                    SELECT id FROM cleanup_runs
                    ORDER BY executedAt DESC
                    LIMIT ?
                )
                """, arguments: [Self.maxEntries])
        }
    }

    func recentRuns() throws -> [CleanupRunRecord] {
        try database.read { db in
            try CleanupRunRecord
                .order(Column("executedAt").desc)
                .limit(Self.maxEntries)
                .fetchAll(db)
        }
    }
}
