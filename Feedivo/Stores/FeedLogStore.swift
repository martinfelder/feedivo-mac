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

    /// Alle Feeds, deren letzter Aktualisierungsversuch fehlgeschlagen ist,
    /// inkl. Länge der aktuellen Fehlerserie — Grundlage für das
    /// Feed-Status-Diagnose-Fenster (`FeedRefreshDiagnosticsWindowView`).
    /// Synchrone Variante für Tests; `failureDiagnosticsAsync()` für den
    /// UI-Aufruf (analog `FeedStore.sidebarFeeds()`/`sidebarFeedsAsync()`).
    func failureDiagnostics() throws -> [FeedFailureDiagnostic] {
        try database.read { db in try Self.queryFailureDiagnostics(db) }
    }

    func failureDiagnosticsAsync() async throws -> [FeedFailureDiagnostic] {
        try await database.readAsync { db in try Self.queryFailureDiagnostics(db) }
    }

    /// Zwei CTEs: `latest` ermittelt den letzten Log-Eintrag je Feed
    /// (analog `latest_feed_logs` in `FeedStore.sidebarFeeds()`), `ordered`+
    /// `streaks` zählen die Länge der aktuellen Fehlerserie — läuft von den
    /// neuesten Einträgen je Feed rückwärts (laufende Summe der
    /// "ist kein Fehler"-Flags) und stoppt beim ersten Nicht-Fehler-Eintrag
    /// (`successBoundary = 0`). Gedeckelt durch die konfigurierbare
    /// `feed_logs`-Aufbewahrungsdauer (siehe `FeedLogRetentionSettings`) —
    /// bei einem seit über 30 Tagen kaputten Feed zählt nur die innerhalb
    /// der Aufbewahrungsfrist protokollierten Fehlschläge (bewusste,
    /// dokumentierte Einschränkung, siehe Design-Spec).
    private static func queryFailureDiagnostics(_ db: Database) throws -> [FeedFailureDiagnostic] {
        try SQLRequest<FeedFailureDiagnostic>(sql: """
            WITH ordered AS (
                SELECT
                    feedID,
                    level,
                    createdAt,
                    id,
                    SUM(CASE WHEN level != 'error' THEN 1 ELSE 0 END) OVER (
                        PARTITION BY feedID
                        ORDER BY createdAt DESC, id COLLATE NOCASE DESC
                        ROWS UNBOUNDED PRECEDING
                    ) AS successBoundary
                FROM feed_logs
            ),
            streaks AS (
                SELECT feedID, COUNT(*) AS consecutiveFailureCount
                FROM ordered
                WHERE successBoundary = 0 AND level = 'error'
                GROUP BY feedID
            ),
            latest AS (
                SELECT
                    feedID, level, message, httpStatusCode, createdAt,
                    ROW_NUMBER() OVER (
                        PARTITION BY feedID ORDER BY createdAt DESC, id COLLATE NOCASE DESC
                    ) AS rn
                FROM feed_logs
            )
            SELECT
                f.id AS feedID,
                f.title AS feedTitle,
                f.url AS feedURL,
                f.websiteURL AS feedWebsiteURL,
                f.faviconURL AS feedFaviconURL,
                l.createdAt AS lastAttemptAt,
                l.message AS errorMessage,
                l.httpStatusCode AS httpStatusCode,
                COALESCE(s.consecutiveFailureCount, 1) AS consecutiveFailureCount
            FROM feeds f
            JOIN latest l ON l.feedID = f.id AND l.rn = 1
            LEFT JOIN streaks s ON s.feedID = f.id
            WHERE l.level = 'error'
            ORDER BY l.createdAt DESC
            """, cached: true).fetchAll(db)
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

extension FeedFailureDiagnostic: FetchableRecord {
    // nonisolated noetig, da das App-Target SWIFT_DEFAULT_ACTOR_ISOLATION =
    // MainActor setzt — ohne diese Annotation waere die FetchableRecord-
    // Konformität MainActor-isoliert und SQLRequest<FeedFailureDiagnostic>s
    // generischer, Sendable-vorausgesetzter fetchAll(_:)-Pfad wuerde nicht
    // kompilieren.
    nonisolated init(row: Row) throws {
        feedID = row["feedID"]
        feedTitle = row["feedTitle"]
        feedURL = row["feedURL"]
        feedWebsiteURL = row["feedWebsiteURL"]
        feedFaviconURL = row["feedFaviconURL"]
        lastAttemptAt = row["lastAttemptAt"]
        errorMessage = row["errorMessage"]
        httpStatusCode = row["httpStatusCode"]
        consecutiveFailureCount = row["consecutiveFailureCount"]
    }
}
