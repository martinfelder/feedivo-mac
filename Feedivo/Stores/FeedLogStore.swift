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

    /// Letzter Abrufversuch je Feed — unabhängig vom Ergebnis (Erfolg, „Nicht
    /// geändert" ODER Fehler), da `SQLiteFeedRefreshService.refresh` in allen
    /// drei Fällen einen `FeedLogRecord` schreibt. Grundlage für
    /// `FeedRefreshThrottle` in `SQLiteFeedRefreshCoordinator` — eine
    /// gruppierte Query statt einer Einzelabfrage pro Feed (analog der
    /// `latest_feed_logs`-CTE in `FeedStore.sidebarFeeds()`).
    func latestAttemptTimes() throws -> [String: Date] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT feedID, MAX(createdAt) AS lastAttemptAt
                FROM feed_logs
                GROUP BY feedID
                """)
            var result: [String: Date] = [:]
            for row in rows {
                guard let feedID = row["feedID"] as String?,
                      let lastAttemptAt = row["lastAttemptAt"] as Date? else {
                    continue
                }
                result[feedID] = lastAttemptAt
            }
            return result
        }
    }

    /// Löscht alle feed_logs-Einträge, die älter sind als cutoffDate
    /// (Feature feed_logs-Retention) — reines Housekeeping ohne
    /// Nebenbedingungen, anders als die Artikel-Bereinigung (keine
    /// Identity-History, keine Schutz-Ausnahmen wie Stern/Archiv).
    @discardableResult
    func deleteOlderThan(_ cutoffDate: Date) throws -> Int {
        try database.write { db in
            try db.execute(sql: "DELETE FROM feed_logs WHERE createdAt < ?", arguments: [cutoffDate])
            return db.changesCount
        }
    }
}
