import Foundation
import GRDB

struct FeedStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    /// Markiert `feedID` als ausstehende Sync-Änderung, falls iCloud Sync aktiv ist. Läuft
    /// bewusst INNERHALB derselben `database.write`-Transaktion wie die fachliche Mutation
    /// (atomar — kein Zwischenzustand, in dem der Feed geändert, aber nicht als sync-pending
    /// markiert ist). Analog zu `TagStore.enqueuePendingSync`.
    private func enqueuePendingSync(_ db: Database, feedID: String, changeType: CloudSyncChangeType, changedFields: [String]? = nil) throws {
        guard CloudSyncSettings.isEnabled() else { return }
        try CloudSyncPendingChangeStore.enqueue(db, recordType: CloudSyncFeedMapping.recordType, recordName: feedID, changeType: changeType, changedFields: changedFields)
    }

    func save(_ feed: FeedRecord) throws {
        try database.write { db in
            var feed = feed
            try feed.save(db)
            try enqueuePendingSync(db, feedID: feed.id, changeType: .save)
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func feed(id: String) throws -> FeedRecord? {
        try database.read { db in
            try FeedRecord.fetchOne(db, key: id)
        }
    }

    func feeds() throws -> [FeedRecord] {
        try database.read { db in
            try FeedRecord.fetchAll(db, sql: """
                SELECT *
                FROM feeds
                ORDER BY title COLLATE NOCASE, url COLLATE NOCASE
                """)
        }
    }

    func renameFeed(id: String, displayTitle: String) throws {
        let title = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw FeedStoreError.emptyTitle
        }

        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE feeds
                    SET title = ?,
                        originalTitle = COALESCE(NULLIF(originalTitle, ''), title),
                        updatedAt = ?,
                        configUpdatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [title, Date(), Date(), id]
            )

            if db.changesCount == 0 {
                throw FeedStoreError.missingFeed
            }

            try enqueuePendingSync(db, feedID: id, changeType: .save, changedFields: ["title"])
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func restoreOriginalTitle(id: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE feeds
                    SET title = COALESCE(NULLIF(originalTitle, ''), title),
                        updatedAt = ?,
                        configUpdatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [Date(), Date(), id]
            )

            if db.changesCount == 0 {
                throw FeedStoreError.missingFeed
            }

            try enqueuePendingSync(db, feedID: id, changeType: .save, changedFields: ["title"])
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func updateRefreshInterval(id: String, minutes: Int) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE feeds
                    SET refreshIntervalMinutes = ?, updatedAt = ?, configUpdatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [BackgroundRefreshSettings.clampedIntervalMinutes(minutes), Date(), Date(), id]
            )

            if db.changesCount == 0 {
                throw FeedStoreError.missingFeed
            }

            try enqueuePendingSync(db, feedID: id, changeType: .save, changedFields: ["refreshIntervalMinutes"])
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func updateFolderName(id: String, folderName: String?) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE feeds
                    SET folderName = ?, updatedAt = ?, configUpdatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [FeedFolderOrganizer.normalizedFolderName(folderName), Date(), Date(), id]
            )

            if db.changesCount == 0 {
                throw FeedStoreError.missingFeed
            }

            try enqueuePendingSync(db, feedID: id, changeType: .save, changedFields: ["folderName"])
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func updateNotificationEnabled(id: String, isEnabled: Bool) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE feeds
                    SET isNotificationEnabled = ?, updatedAt = ?, configUpdatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [isEnabled, Date(), Date(), id]
            )

            if db.changesCount == 0 {
                throw FeedStoreError.missingFeed
            }

            try enqueuePendingSync(db, feedID: id, changeType: .save, changedFields: ["isNotificationEnabled"])
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func updateRetentionSettings(
        id: String,
        overridesGlobal: Bool,
        isEnabled: Bool,
        days: Int,
        minimumArticles: Int,
        includesProtectedArticles: Bool
    ) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE feeds
                    SET articleRetentionOverridesGlobalSetting = ?,
                        articleRetentionIsEnabled = ?,
                        articleRetentionDays = ?,
                        articleRetentionMinimumArticles = ?,
                        articleRetentionIncludesProtectedArticles = ?,
                        updatedAt = ?,
                        configUpdatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [
                    overridesGlobal,
                    isEnabled,
                    ArticleRetentionSettings.clampedRetentionDays(days),
                    ArticleRetentionSettings.clampedMinimumArticlesPerFeed(minimumArticles),
                    includesProtectedArticles,
                    Date(),
                    Date(),
                    id
                ]
            )

            if db.changesCount == 0 {
                throw FeedStoreError.missingFeed
            }

            try enqueuePendingSync(db, feedID: id, changeType: .save, changedFields: ["articleRetentionOverridesGlobalSetting", "articleRetentionIsEnabled", "articleRetentionDays", "articleRetentionMinimumArticles", "articleRetentionIncludesProtectedArticles"])
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func delete(id: String) throws {
        try database.write { db in
            try enqueuePendingSync(db, feedID: id, changeType: .delete)

            // Artikel-IDs VOR dem eigentlichen DELETE lesen — die FK-Kaskade entfernt
            // articles/article_statuses unsichtbar für den Anwendungscode, danach wäre
            // hier nichts mehr abfragbar (iCloud Sync Phase 2b, Löschpropagierung).
            let articleIDs = try String.fetchAll(db, sql: "SELECT id FROM articles WHERE feedID = ?", arguments: [id])
            try CloudSyncArticleStatusMapping.enqueueDeletionIfSynced(articleIDs: articleIDs, db: db)

            try db.execute(
                sql: """
                    DELETE FROM feeds
                    WHERE id = ?
                    """,
                arguments: [id]
            )
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func updateAfterRefresh(
        feedID: String,
        title: String?,
        websiteURL: String?,
        validators: FeedHTTPValidators,
        unreadCount: Int,
        refreshedAt: Date,
        faviconURL: String? = nil
    ) throws {
        try database.write { db in
            let trimmedTitle = title.trimmedNonEmpty
            let titleAssignment = trimmedTitle == nil ? "" : "title = ?,"
            var arguments = StatementArguments()
            if let trimmedTitle {
                arguments.append(contentsOf: [trimmedTitle])
            }
            arguments.append(contentsOf: [
                websiteURL.trimmedNonEmpty,
                faviconURL.trimmedNonEmpty,
                refreshedAt,
                validators.eTag,
                validators.lastModified,
                validators.contentHash,
                validators.lastStatusCode,
                unreadCount,
                refreshedAt,
                feedID
            ])

            try db.execute(
                sql: """
                    UPDATE feeds
                    SET \(titleAssignment)
                        websiteURL = COALESCE(?, websiteURL),
                        faviconURL = COALESCE(?, faviconURL),
                        lastRefreshedAt = ?,
                        lastETag = ?,
                        lastModified = ?,
                        lastBodyHash = ?,
                        lastHTTPStatusCode = ?,
                        unreadCount = ?,
                        updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: arguments
            )
        }
    }

    func setUnreadCount(_ unreadCount: Int, feedID: String) throws {
        try database.write { db in
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

    func sidebarFeeds() throws -> [FeedSidebarSnapshot] {
        try database.read { db in try Self.querySidebarFeeds(db) }
    }

    /// Async-Variante für Aufrufer auf dem MainActor (z. B. `ContentView.
    /// reloadFeedSnapshots()`) — läuft auf GRDBs eigener DB-Queue statt den
    /// MainActor für die Dauer der Query zu blockieren.
    func sidebarFeedsAsync() async throws -> [FeedSidebarSnapshot] {
        try await database.readAsync { db in try Self.querySidebarFeeds(db) }
    }

    /// Aggregiert `unreadCount` weiterhin LIVE aus `article_statuses` statt
    /// aus der denormalisierten Spalte `feeds.unreadCount` zu lesen — bewusst
    /// so belassen (Performance-Vergleich mit NetNewsWire, 2026-07-28): ein
    /// Umstieg auf die Spalte wurde geprüft und wieder verworfen, siehe
    /// `SQLiteSidebarStateTests.loadIgnoresStaleFeedUnreadCountCache()`, die
    /// exakt das Gegenteil testet und bereits vor diesem Versuch bestand.
    /// Zusammen mit dem Architektur-Kommentar in
    /// `SQLiteUnreadCountService.swift` ist das ein bewusster
    /// Korrektheit-vor-Performance-Trade-off: die CTE ist seit dem
    /// 2026-07-16-Fix mit ~26ms bei 500 Feeds bereits schnell genug, ein
    /// veralteter `feeds.unreadCount`-Wert (z. B. durch eine künftig neu
    /// hinzukommende Mutationsstelle, die die Spalte vergisst) soll aber nie
    /// ein falsches Sidebar-Badge zeigen können.
    private static func querySidebarFeeds(_ db: Database) throws -> [FeedSidebarSnapshot] {
        let snapshots = try SQLRequest<FeedSidebarSnapshot>(sql: """
            WITH unread_counts AS (
                SELECT a.feedID AS feedID, COUNT(*) AS unreadCount
                FROM articles a
                JOIN article_statuses s ON s.articleID = a.id
                WHERE s.isRead = 0 AND s.isHidden = 0
                GROUP BY a.feedID
            ),
            latest_feed_logs AS (
                SELECT feedID, level,
                       ROW_NUMBER() OVER (PARTITION BY feedID ORDER BY createdAt DESC) AS rn
                FROM feed_logs
            )
            SELECT
                f.id,
                f.title,
                f.url,
                f.faviconURL,
                f.folderName,
                f.sortIndex,
                COALESCE(uc.unreadCount, 0) AS unreadCount,
                COALESCE(ll.level = 'error', 0) AS hasRecentError
            FROM feeds f
            LEFT JOIN unread_counts uc ON uc.feedID = f.id
            LEFT JOIN latest_feed_logs ll ON ll.feedID = f.id AND ll.rn = 1
            ORDER BY f.sortIndex, f.title COLLATE NOCASE, f.id COLLATE NOCASE
            """, cached: true).fetchAll(db)
        return snapshots.sorted {
            if $0.sortIndex != $1.sortIndex {
                return $0.sortIndex < $1.sortIndex
            }
            let titleOrder = $0.title.localizedStandardCompare($1.title)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }

            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
    }

    func sidebarFeeds(showsReadFeeds: Bool) throws -> [FeedSidebarSnapshot] {
        let snapshots = try sidebarFeeds()
        guard !showsReadFeeds else {
            return snapshots
        }

        return snapshots.filter { $0.unreadCount > 0 }
    }

    /// Weist den Feed ggf. einem neuen Ordner zu (nil = "Ohne Ordner") und
    /// positioniert ihn an targetIndex innerhalb der Ziel-Gruppe (0-basiert,
    /// wird auf 0...anzahlAndererFeedsInDerGruppe geklemmt). Nummeriert
    /// anschließend NUR die Ziel-Gruppe 0...n-1 neu durch — die Quell-Gruppe
    /// (falls der Feed den Ordner wechselt) behält ihre bestehenden
    /// sortIndex-Werte samt Lücke; das ist harmlos, da nur die relative
    /// Reihenfolge zählt, nicht die absoluten Werte.
    func moveFeed(id: String, toFolderName: String?, targetIndex: Int) throws {
        let trimmedFolderName = toFolderName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveFolderName = (trimmedFolderName?.isEmpty ?? true) ? nil : trimmedFolderName

        try database.write { db in
            let otherFeedIDs: [String]
            if let effectiveFolderName {
                otherFeedIDs = try String.fetchAll(
                    db,
                    sql: """
                        SELECT id FROM feeds
                        WHERE folderName = ? COLLATE NOCASE AND id != ?
                        ORDER BY sortIndex
                        """,
                    arguments: [effectiveFolderName, id]
                )
            } else {
                otherFeedIDs = try String.fetchAll(
                    db,
                    sql: """
                        SELECT id FROM feeds
                        WHERE folderName IS NULL AND id != ?
                        ORDER BY sortIndex
                        """,
                    arguments: [id]
                )
            }

            var orderedIDs = otherFeedIDs
            let clampedIndex = min(max(targetIndex, 0), orderedIDs.count)
            orderedIDs.insert(id, at: clampedIndex)

            let now = Date()
            for (index, feedID) in orderedIDs.enumerated() {
                if feedID == id {
                    try db.execute(
                        sql: """
                            UPDATE feeds
                            SET sortIndex = ?, folderName = ?, updatedAt = ?, configUpdatedAt = ?
                            WHERE id = ?
                            """,
                        arguments: [index, effectiveFolderName, now, now, feedID]
                    )
                } else {
                    try db.execute(
                        sql: "UPDATE feeds SET sortIndex = ?, configUpdatedAt = ? WHERE id = ?",
                        arguments: [index, now, feedID]
                    )
                }
                try enqueuePendingSync(db, feedID: feedID, changeType: .save, changedFields: ["sortIndex"])
            }
        }
        CloudSyncEngine.notifyPendingChangesAvailable(database: database)
    }

    func opmlFeedsForExport() throws -> [OPMLFeed] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT
                    f.id,
                    f.title,
                    f.url,
                    f.websiteURL,
                    f.folderName,
                    GROUP_CONCAT(t.name, '\u{1F}') AS tagNames
                FROM feeds f
                LEFT JOIN feed_tags ft ON ft.feedID = f.id
                LEFT JOIN tags t ON t.id = ft.tagID
                GROUP BY f.id
                ORDER BY f.title COLLATE NOCASE, f.id COLLATE NOCASE
                """)

            return rows.map { row in
                let tagList = (row["tagNames"] as String?)
                    .map { $0.split(separator: "\u{1F}").map(String.init) }
                    ?? []

                return OPMLFeed(
                    title: row["title"],
                    xmlURL: row["url"],
                    htmlURL: row["websiteURL"],
                    folderName: row["folderName"],
                    description: nil,
                    tagNames: tagList.sorted {
                        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                    }
                )
            }
        }
    }
}

// Fehler beim Umbenennen eines Feeds. `.databaseUnavailable` wird nicht von
// dieser Store-Methode selbst geworfen (die Datenbank ist hier bereits
// injiziert), sondern ausschließlich vom UI-seitigen Aufrufer
// (`SidebarView.renameFeed`), falls die `\.feedivoDatabase`-Environment fehlt.
// `.missingFeed` bleibt ohne eigenen Text — über die aktuellen Aufrufpfade
// nicht erreichbar und bislang nirgends speziell behandelt.
enum FeedStoreError: Error, Equatable, LocalizedError {
    case emptyTitle
    case missingFeed
    case databaseUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyTitle: L10n.feedRenameEmptyName
        case .missingFeed: nil
        case .databaseUnavailable: L10n.feedRenameDatabaseUnavailable
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

extension FeedSidebarSnapshot: FetchableRecord {
    // nonisolated noetig, da das App-Target SWIFT_DEFAULT_ACTOR_ISOLATION =
    // MainActor setzt — ohne diese Annotation waere die FetchableRecord-
    // Konformität MainActor-isoliert und SQLRequest<FeedSidebarSnapshot>s
    // generischer, Sendable-vorausgesetzter fetchAll(_:)-Pfad wuerde nicht
    // kompilieren.
    nonisolated init(row: Row) throws {
        id = row["id"]
        title = row["title"]
        faviconURL = row["faviconURL"]
        folderName = row["folderName"]
        sortIndex = row["sortIndex"]
        unreadCount = row["unreadCount"]
        hasRecentError = row["hasRecentError"]
    }
}
