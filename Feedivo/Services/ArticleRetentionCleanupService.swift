import Foundation
import GRDB
import OSLog

enum ArticleRetentionCleanupService {
    @MainActor
    @discardableResult
    static func removeExpiredSQLiteArticles(
        database: FeedivoDatabase,
        isEnabled: Bool,
        retentionDays: Int,
        minimumArticlesPerFeed: Int = ArticleRetentionSettings.defaultMinimumArticlesPerFeed,
        includeProtectedArticles: Bool = false,
        now: Date = Date(),
        deindexForSpotlight: ([String]) -> Void = { SpotlightIndexingService.deindexArticles(ids: $0) }
    ) throws -> Int {
        let globalConfiguration = ArticleRetentionConfiguration(
            isEnabled: isEnabled,
            retentionDays: retentionDays,
            minimumArticlesPerFeed: minimumArticlesPerFeed,
            includeProtectedArticles: includeProtectedArticles,
            now: now
        )
        let feedConfigurations = try sqliteFeedRetentionConfigurations(
            in: database,
            globalConfiguration: globalConfiguration,
            now: now
        )

        var removedArticleIDs: [String] = []
        let removedCount = try database.write { db in
            let candidates = try SQLiteArticleRetentionCandidate.fetchAll(db, sql: """
                SELECT
                    a.id,
                    a.feedID,
                    a.publishedAt,
                    a.arrivedAt,
                    s.isStarred,
                    s.isArchived
                FROM articles a
                JOIN article_statuses s ON s.articleID = a.id
                """)

            let protectedArticleIDs = protectedSQLiteArticleIDs(
                candidates,
                feedConfigurations: feedConfigurations,
                globalConfiguration: globalConfiguration
            )
            let expiredCandidates = candidates.filter { candidate in
                let configuration = feedConfigurations[candidate.feedID] ?? globalConfiguration
                guard !protectedArticleIDs.contains(candidate.id) else {
                    return false
                }

                return shouldRemove(
                    candidate,
                    cutoffDate: configuration.cutoffDate,
                    isEnabled: configuration.isEnabled,
                    includeProtectedArticles: configuration.includeProtectedArticles
                )
            }

            guard !expiredCandidates.isEmpty else {
                return 0
            }

            let articleIDs = expiredCandidates.map(\.id)
            let changedFeedIDs = Set(expiredCandidates.map(\.feedID))

            try saveSQLiteIdentityHistory(for: articleIDs, now: now, db: db)
            try deleteSQLiteArticles(articleIDs, db: db)
            try recalculateSQLiteUnreadCounts(for: changedFeedIDs, db: db)

            removedArticleIDs = articleIDs
            return articleIDs.count
        }

        if removedCount > 0 {
            SQLiteDataInvalidationSignal.shared.bumpStatusVersion()
            deindexForSpotlight(removedArticleIDs)
            CloudSyncEngine.notifyPendingChangesAvailable(database: database)
        }

        return removedCount
    }

    /// Führt eine Bereinigung aus (manuell oder automatisch: App-Start, Zeitplan,
    /// App-Beenden, Feed-/Retention-Einstellungsänderung) und hält Ergebnis/Fehler
    /// persistent in `UserDefaults` UND in der `cleanup_runs`-History fest (Feature
    /// 17.3a). Feuert bei tatsächlich gelöschten Artikeln zusätzlich das
    /// `CleanupToastSignal` für den In-App-Toast. Vorher landeten Fehler des
    /// automatischen Pfads ausschließlich im Apple-Systemlog, ohne jede Sichtbarkeit in
    /// der App selbst (Befund C, Nutzer-Report 2026-07-13).
    @discardableResult
    @MainActor
    static func runAutomaticCleanup(
        database: FeedivoDatabase,
        isEnabled: Bool,
        retentionDays: Int,
        minimumArticlesPerFeed: Int = ArticleRetentionSettings.defaultMinimumArticlesPerFeed,
        includeProtectedArticles: Bool = false,
        triggerSource: CleanupRunTrigger,
        userDefaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> Result<Int, Error> {
        // Feed-Log-Bereinigung läuft immer mit, unabhängig vom Artikel-
        // Aufbewahrung-Schalter (isEnabled) — rein internes Housekeeping ohne
        // History-/Toast-Sichtbarkeit (Feature feed_logs-Retention).
        let feedLogCutoff = Calendar.current.date(
            byAdding: .day,
            value: -FeedLogRetentionSettings.retentionDays(in: userDefaults),
            to: now
        ) ?? now
        do {
            try FeedLogStore(database: database).deleteOlderThan(feedLogCutoff)
        } catch {
            AppLogger.dataAccess.error("Feed-Log-Bereinigung: \(error.localizedDescription, privacy: .public)")
        }

        // Verwaiste eingehende Artikelstatus-Updates bereinigen (iCloud Sync Phase 2b) — läuft
        // wie die Feed-Log-Bereinigung immer mit, unabhängig von `isEnabled` (Artikel-
        // Aufbewahrung): eine deaktivierte Artikel-Aufbewahrung würde sonst dazu führen, dass
        // niemals abgeholte verwaiste Status (z. B. für einen längst deabonnierten Feed)
        // unbegrenzt wachsen. Nutzt `retentionDays`, falls Artikel-Aufbewahrung aktiv ist,
        // sonst einen festen 90-Tage-Fallback.
        let orphanCutoffDays = isEnabled ? retentionDays : 90
        let orphanCutoff = Calendar.current.date(byAdding: .day, value: -orphanCutoffDays, to: now) ?? now
        do {
            try OrphanedArticleStatusUpdateStore(database: database).deleteOlderThan(orphanCutoff)
        } catch {
            AppLogger.dataAccess.error("Bereinigung verwaister Artikelstatus-Updates: \(error.localizedDescription, privacy: .public)")
        }

        do {
            let removedCount = try removeExpiredSQLiteArticles(
                database: database,
                isEnabled: isEnabled,
                retentionDays: retentionDays,
                minimumArticlesPerFeed: minimumArticlesPerFeed,
                includeProtectedArticles: includeProtectedArticles,
                now: now
            )
            recordAutomaticCleanupSuccess(removedCount: removedCount, now: now, userDefaults: userDefaults)
            try? CleanupRunHistoryStore(database: database).record(
                triggerSource: triggerSource,
                deletedCount: removedCount,
                succeeded: true,
                errorMessage: nil,
                now: now
            )
            if removedCount > 0 {
                CleanupToastSignal.notify(deletedCount: removedCount, in: userDefaults)
            }
            return .success(removedCount)
        } catch {
            recordAutomaticCleanupFailure(error.localizedDescription, now: now, userDefaults: userDefaults)
            try? CleanupRunHistoryStore(database: database).record(
                triggerSource: triggerSource,
                deletedCount: 0,
                succeeded: false,
                errorMessage: error.localizedDescription,
                now: now
            )
            AppLogger.dataAccess.error("Automatisches Retention-Cleanup: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    static func recordAutomaticCleanupSuccess(
        removedCount: Int,
        now: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(now.timeIntervalSince1970, forKey: ArticleRetentionSettings.lastAutomaticCleanupDateKey)
        userDefaults.set(ArticleRetentionSettings.statusSuccess, forKey: ArticleRetentionSettings.lastAutomaticCleanupStatusKey)
        userDefaults.set(removedCount, forKey: ArticleRetentionSettings.lastAutomaticCleanupRemovedCountKey)
        userDefaults.removeObject(forKey: ArticleRetentionSettings.lastAutomaticCleanupErrorKey)
    }

    static func recordAutomaticCleanupFailure(
        _ message: String,
        now: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(now.timeIntervalSince1970, forKey: ArticleRetentionSettings.lastAutomaticCleanupDateKey)
        userDefaults.set(ArticleRetentionSettings.statusFailed, forKey: ArticleRetentionSettings.lastAutomaticCleanupStatusKey)
        userDefaults.set(message, forKey: ArticleRetentionSettings.lastAutomaticCleanupErrorKey)
    }

    private static func shouldRemove(
        _ article: SQLiteArticleRetentionCandidate,
        cutoffDate: Date,
        isEnabled: Bool = true,
        includeProtectedArticles: Bool = false
    ) -> Bool {
        guard isEnabled else {
            return false
        }

        guard article.effectiveDate < cutoffDate else {
            return false
        }

        if includeProtectedArticles {
            return true
        }

        return !article.isStarred && !article.isArchived
    }

    private static func protectedSQLiteArticleIDs(
        _ candidates: [SQLiteArticleRetentionCandidate],
        feedConfigurations: [String: ArticleRetentionConfiguration],
        globalConfiguration: ArticleRetentionConfiguration
    ) -> Set<String> {
        let groupedCandidates = Dictionary(grouping: candidates, by: \.feedID)
        var protectedIDs = Set<String>()

        for (feedID, feedCandidates) in groupedCandidates {
            let minimumCount = (feedConfigurations[feedID] ?? globalConfiguration).minimumArticlesPerFeed
            guard minimumCount > 0 else {
                continue
            }

            let candidatesToKeep = feedCandidates
                .sorted(by: sqliteRetentionSort)
                .prefix(minimumCount)
            protectedIDs.formUnion(candidatesToKeep.map(\.id))
        }

        return protectedIDs
    }

    private static func sqliteRetentionSort(
        _ lhs: SQLiteArticleRetentionCandidate,
        _ rhs: SQLiteArticleRetentionCandidate
    ) -> Bool {
        let lhsDate = lhs.effectiveDate
        let rhsDate = rhs.effectiveDate
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        return lhs.id < rhs.id
    }

    private static func sqliteFeedRetentionConfigurations(
        in database: FeedivoDatabase,
        globalConfiguration: ArticleRetentionConfiguration,
        now: Date
    ) throws -> [String: ArticleRetentionConfiguration] {
        let feeds = try database.read { db in
            try FeedRecord.fetchAll(db)
        }
        var configurations: [String: ArticleRetentionConfiguration] = [:]

        for feed in feeds {
            if feed.articleRetentionOverridesGlobalSetting {
                configurations[feed.id] = ArticleRetentionConfiguration(
                    isEnabled: feed.articleRetentionIsEnabled,
                    retentionDays: feed.articleRetentionDays,
                    minimumArticlesPerFeed: feed.articleRetentionMinimumArticles,
                    includeProtectedArticles: feed.articleRetentionIncludesProtectedArticles,
                    now: now
                )
            } else {
                configurations[feed.id] = globalConfiguration
            }
        }

        return configurations
    }

    private static func deleteSQLiteArticles(_ articleIDs: [String], db: Database) throws {
        for chunk in articleIDs.chunked(into: 400) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let arguments = StatementArguments(chunk)

            try CloudSyncArticleStatusMapping.enqueueDeletionIfSynced(articleIDs: chunk, db: db)

            try db.execute(
                sql: "DELETE FROM article_statuses WHERE articleID IN (\(placeholders))",
                arguments: arguments
            )
            try db.execute(
                sql: "DELETE FROM articles WHERE id IN (\(placeholders))",
                arguments: arguments
            )
        }
    }

    private static func saveSQLiteIdentityHistory(for articleIDs: [String], now: Date, db: Database) throws {
        for chunk in articleIDs.chunked(into: 400) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let arguments = StatementArguments(chunk)
            let candidates = try SQLiteArticleIdentityHistoryCandidate.fetchAll(db, sql: """
                SELECT
                    a.id,
                    a.feedID,
                    a.sourceID,
                    a.link,
                    a.title,
                    a.publishedAt,
                    s.isRead,
                    s.isStarred,
                    s.isArchived,
                    s.isHidden,
                    s.readAt,
                    s.starredAt,
                    s.archivedAt,
                    s.hiddenAt,
                    s.dateArrived
                FROM articles a
                JOIN article_statuses s ON s.articleID = a.id
                WHERE a.id IN (\(placeholders))
                """, arguments: arguments)

            for candidate in candidates {
                try candidate.saveHistory(now: now, db: db)
            }
        }
    }

    private static func recalculateSQLiteUnreadCounts(for feedIDs: Set<String>, db: Database) throws {
        for feedID in feedIDs {
            let unreadCount = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM article_statuses s
                JOIN articles a ON a.id = s.articleID
                WHERE a.feedID = ?
                    AND s.isRead = 0
                    AND s.isHidden = 0
                """, arguments: [feedID]) ?? 0

            try db.execute(
                sql: """
                    UPDATE feeds
                    SET unreadCount = ?, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [unreadCount, Date(), feedID]
            )
        }
    }
}

private struct SQLiteArticleRetentionCandidate: FetchableRecord {
    let id: String
    let feedID: String
    let publishedAt: Date?
    let arrivedAt: Date
    let isStarred: Bool
    let isArchived: Bool

    /// Fallback auf `arrivedAt` (NOT NULL, immer vorhanden), wenn der Feed kein
    /// parsbares Veröffentlichungsdatum liefert — sonst blieben solche Artikel
    /// dauerhaft von der Bereinigung ausgenommen (Befund B, Nutzer-Report
    /// 2026-07-13). Gleiche COALESCE(publishedAt, arrivedAt)-Idiomatik wie
    /// bereits in ArticleStore.swift für die Artikel-Sortierung etabliert.
    var effectiveDate: Date {
        publishedAt ?? arrivedAt
    }

    init(row: Row) throws {
        id = row["id"]
        feedID = row["feedID"]
        publishedAt = row["publishedAt"]
        arrivedAt = row["arrivedAt"]
        isStarred = row["isStarred"]
        isArchived = row["isArchived"]
    }
}

private struct SQLiteArticleIdentityHistoryCandidate: FetchableRecord {
    let id: String
    let feedID: String
    let sourceID: String?
    let link: String?
    let title: String
    let publishedAt: Date?
    let isRead: Bool
    let isStarred: Bool
    let isArchived: Bool
    let isHidden: Bool
    let readAt: Date?
    let starredAt: Date?
    let archivedAt: Date?
    let hiddenAt: Date?
    let dateArrived: Date

    init(row: Row) throws {
        id = row["id"]
        feedID = row["feedID"]
        sourceID = row["sourceID"]
        link = row["link"]
        title = row["title"]
        publishedAt = row["publishedAt"]
        isRead = row["isRead"]
        isStarred = row["isStarred"]
        isArchived = row["isArchived"]
        isHidden = row["isHidden"]
        readAt = row["readAt"]
        starredAt = row["starredAt"]
        archivedAt = row["archivedAt"]
        hiddenAt = row["hiddenAt"]
        dateArrived = row["dateArrived"]
    }

    func saveHistory(now: Date, db: Database) throws {
        if let existing = try existingHistory(db: db) {
            var history = existing
            history.sourceID = history.sourceID ?? sourceID.trimmedNonEmpty
            history.link = history.link ?? link.trimmedNonEmpty
            history.titleHash = ArticleStore.titleHash(title)
            history.publishedAt = publishedAt ?? history.publishedAt
            history.lastSeenAt = now
            history.lastArticleID = id
            history.isRead = isRead
            history.isStarred = isStarred
            history.isArchived = isArchived
            history.isHidden = isHidden
            history.readAt = readAt
            history.starredAt = starredAt
            history.archivedAt = archivedAt
            history.hiddenAt = hiddenAt
            history.wasRemovedByRetention = true
            try history.save(db)
            return
        }

        var history = ArticleIdentityHistoryRecord(
            id: UUID().uuidString,
            feedID: feedID,
            sourceID: sourceID.trimmedNonEmpty,
            link: link.trimmedNonEmpty,
            titleHash: ArticleStore.titleHash(title),
            publishedAt: publishedAt,
            firstSeenAt: dateArrived,
            lastSeenAt: now,
            lastArticleID: id,
            isRead: isRead,
            isStarred: isStarred,
            isArchived: isArchived,
            isHidden: isHidden,
            readAt: readAt,
            starredAt: starredAt,
            archivedAt: archivedAt,
            hiddenAt: hiddenAt,
            wasRemovedByRetention: true
        )
        try history.insert(db)
    }

    private func existingHistory(db: Database) throws -> ArticleIdentityHistoryRecord? {
        if let sourceID = sourceID.trimmedNonEmpty {
            let record = try ArticleIdentityHistoryRecord.fetchOne(db, sql: """
                SELECT *
                FROM article_identity_history
                WHERE feedID = ? AND sourceID = ?
                LIMIT 1
                """, arguments: [feedID, sourceID])
            if let record {
                return record
            }
        }

        if let link = link.trimmedNonEmpty {
            let record = try ArticleIdentityHistoryRecord.fetchOne(db, sql: """
                SELECT *
                FROM article_identity_history
                WHERE feedID = ? AND link = ?
                LIMIT 1
                """, arguments: [feedID, link])
            if let record {
                return record
            }
        }

        return try ArticleIdentityHistoryRecord.fetchOne(db, sql: """
            SELECT *
            FROM article_identity_history
            WHERE feedID = ? AND titleHash = ?
            ORDER BY lastSeenAt DESC
            LIMIT 1
            """, arguments: [feedID, ArticleStore.titleHash(title)])
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else {
            return [self]
        }

        return stride(from: 0, to: count, by: size).map { startIndex in
            Array(self[startIndex..<Swift.min(startIndex + size, count)])
        }
    }
}

private extension Optional where Wrapped == String {
    var trimmedNonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

struct ArticleRetentionConfiguration {
    let isEnabled: Bool
    let cutoffDate: Date
    let minimumArticlesPerFeed: Int
    let includeProtectedArticles: Bool

    init(
        isEnabled: Bool,
        retentionDays: Int,
        minimumArticlesPerFeed: Int,
        includeProtectedArticles: Bool,
        now: Date
    ) {
        self.isEnabled = isEnabled
        self.cutoffDate = ArticleRetentionSettings.cutoffDate(
            retentionDays: retentionDays,
            now: now
        )
        self.minimumArticlesPerFeed = ArticleRetentionSettings.clampedMinimumArticlesPerFeed(minimumArticlesPerFeed)
        self.includeProtectedArticles = includeProtectedArticles
    }
}
