import Foundation
import CryptoKit
import GRDB

struct ArticleUpsertInput: Equatable, Sendable {
    var feedID: String
    var sourceID: String?
    var link: String?
    var title: String
    var summary: String?
    var content: String?
    var imageURL: String?
    var author: String?
    var publishedAt: Date?
    var arrivedAt: Date
    var estimatedReadingMinutes: Int?

    init(
        feedID: String,
        sourceID: String? = nil,
        link: String? = nil,
        title: String,
        summary: String? = nil,
        content: String? = nil,
        imageURL: String? = nil,
        author: String? = nil,
        publishedAt: Date? = nil,
        arrivedAt: Date = Date(),
        estimatedReadingMinutes: Int? = nil
    ) {
        self.feedID = feedID
        self.sourceID = sourceID
        self.link = link
        self.title = title
        self.summary = summary
        self.content = content
        self.imageURL = imageURL
        self.author = author
        self.publishedAt = publishedAt
        self.arrivedAt = arrivedAt
        self.estimatedReadingMinutes = estimatedReadingMinutes
    }
}

struct ArticleUpsertResult: Equatable, Sendable {
    var insertedArticleIDs: [String]
    var updatedArticleIDs: [String]
    var articleIDs: [String]
}

struct ArticleStore {
    private let database: FeedivoDatabase
    private let userDefaults: UserDefaults

    init(database: FeedivoDatabase, userDefaults: UserDefaults = .standard) {
        self.database = database
        self.userDefaults = userDefaults
    }

    func upsert(_ input: ArticleUpsertInput) throws -> String {
        let result = try upsert([input])
        guard let articleID = result.articleIDs.first else {
            throw ArticleStoreError.emptyBatch
        }
        return articleID
    }

    func upsert(_ inputs: [ArticleUpsertInput]) throws -> ArticleUpsertResult {
        try database.write { db in
            var insertedArticleIDs: [String] = []
            var updatedArticleIDs: [String] = []
            var articleIDs: [String] = []

            for input in inputs {
                switch try upsert(input, db: db) {
                case .inserted(let articleID):
                    articleIDs.append(articleID)
                    insertedArticleIDs.append(articleID)
                case .updated(let articleID):
                    articleIDs.append(articleID)
                    updatedArticleIDs.append(articleID)
                case .skipped:
                    break
                }
            }

            return ArticleUpsertResult(
                insertedArticleIDs: insertedArticleIDs,
                updatedArticleIDs: updatedArticleIDs,
                articleIDs: articleIDs
            )
        }
    }

    /// Einzelabruf per ID (Feature 21.1, Menubar-Dropdown), Standard-Pattern
    /// analog zu `FeedStore.feed(id:)`.
    func article(id: String) throws -> ArticleRecord? {
        try database.read { db in
            try ArticleRecord.fetchOne(db, key: id)
        }
    }

    /// Aktualisiert gezielt nur die `imageURL`-Spalte eines bereits
    /// existierenden Artikels — kein voller Upsert. Genutzt von der
    /// nachgelagerten Bild-Anreicherung nach einem Feed-Refresh
    /// (Optimierungsliste Punkt 3,
    /// docs/performance/feed-refresh-optimierungsliste.md), wo der Artikel
    /// bereits vollständig gespeichert ist und nur sein Bild nachträglich
    /// gefunden wurde.
    func updateImageURL(articleID: String, imageURL: String) throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE articles SET imageURL = ? WHERE id = ?",
                arguments: [imageURL, articleID]
            )
        }
    }

    func readerArticle(id: String) throws -> ArticleReaderSnapshot? {
        try database.read { db in
            var snapshot = try ArticleReaderSnapshot.fetchOne(db, sql: """
                SELECT
                    a.id,
                    a.feedID,
                    f.title AS feedTitle,
                    f.folderName AS folderName,
                    a.title,
                    a.link,
                    a.summary,
                    a.content,
                    a.imageURL,
                    a.author,
                    a.publishedAt,
                    a.arrivedAt,
                    a.estimatedReadingMinutes,
                    s.isRead,
                    s.isStarred,
                    s.isArchived,
                    s.isHidden
                FROM articles a
                JOIN feeds f ON f.id = a.feedID
                JOIN article_statuses s ON s.articleID = a.id
                WHERE a.id = ?
                """, arguments: [id])

            if let articleID = snapshot?.id,
               let feedID = snapshot?.feedID {
                snapshot?.tags = try Self.readerTags(articleID: articleID, feedID: feedID, db: db)
            }

            return snapshot
        }
    }

    func feedPropertiesMetrics(
        feedID: String,
        recentCutoffDate: Date,
        now: Date = Date()
    ) throws -> FeedPropertiesArticleMetricsSnapshot {
        try database.read { db in
            let latestArticle = try latestArticleForFeed(feedID: feedID, db: db)
            let recentArticleCount = try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM articles
                WHERE feedID = ?
                    AND publishedAt IS NOT NULL
                    AND publishedAt >= ?
                    AND publishedAt <= ?
                """, arguments: [feedID, recentCutoffDate, now]) ?? 0

            return FeedPropertiesArticleMetricsSnapshot(
                latestArticle: latestArticle,
                recentArticleCount: recentArticleCount
            )
        }
    }

    func ruleSnapshots(articleIDs: [String], feedTitle: String) throws -> [RuleEngine.ArticleRuleSnapshot] {
        guard !articleIDs.isEmpty else {
            return []
        }

        return try database.read { db in
            let placeholders = Array(repeating: "?", count: articleIDs.count).joined(separator: ", ")
            let records = try ArticleRecord.fetchAll(db, sql: """
                SELECT *
                FROM articles
                WHERE id IN (\(placeholders))
                """, arguments: StatementArguments(articleIDs))
            let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })

            return articleIDs.compactMap { articleID in
                guard let record = recordsByID[articleID] else {
                    return nil
                }

                return RuleEngine.ArticleRuleSnapshot(
                    id: record.id,
                    title: record.title,
                    summary: record.summary,
                    author: record.author,
                    link: record.link,
                    feedTitle: feedTitle
                )
            }
        }
    }

    func recentlyPublishedCount(articleIDs: [String], since: Date) throws -> Int {
        guard !articleIDs.isEmpty else {
            return 0
        }

        return try database.read { db in
            let placeholders = Array(repeating: "?", count: articleIDs.count).joined(separator: ", ")
            let arguments = StatementArguments(articleIDs) + StatementArguments([since])
            return try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM articles
                WHERE id IN (\(placeholders))
                    AND publishedAt IS NOT NULL
                    AND publishedAt >= ?
                """, arguments: arguments) ?? 0
        }
    }

    private func latestArticleForFeed(feedID: String, db: Database) throws -> ArticleListSnapshot? {
        if let datedArticle = try ArticleListSnapshot.fetchOne(db, sql: """
            SELECT
                \(ArticleListSQL.selectColumns)
            \(ArticleListSQL.standardFromJoin)
            WHERE a.feedID = ?
                AND a.publishedAt IS NOT NULL
            ORDER BY a.publishedAt DESC, a.arrivedAt DESC
            LIMIT 1
            """, arguments: [feedID]) {
            return datedArticle
        }

        return try ArticleListSnapshot.fetchOne(db, sql: """
            SELECT
                \(ArticleListSQL.selectColumns)
            \(ArticleListSQL.standardFromJoin)
            WHERE a.feedID = ?
            ORDER BY a.arrivedAt DESC
            LIMIT 1
            """, arguments: [feedID])
    }

    func searchArticles(
        state: ArticleSearchWindowState,
        includeHidden: Bool = false,
        limit: Int = 100
    ) throws -> [ArticleListSnapshot] {
        let safeLimit = max(1, limit)
        let ftsExpression = Self.makeFTSMatchExpression(from: state.searchText, field: state.field)
        var whereClauses: [String] = []
        var arguments = StatementArguments()

        if let ftsExpression {
            whereClauses.append("article_search MATCH ?")
            _ = arguments.append(contentsOf: [ftsExpression])
        }

        if let feedID = state.feedID?.uuidString {
            whereClauses.append("a.feedID = ?")
            _ = arguments.append(contentsOf: [feedID])
        }

        if !state.tagIDs.isEmpty {
            // Gemeinsame Subquery für beide Verknüpfungsmodi: alle Tags, die
            // entweder direkt am Artikel oder am zugehörigen Feed hängen.
            // "Mind. einer" prüft per EXISTS, ob mindestens einer der
            // ausgewählten Tags darin vorkommt; "Alle" zählt per COUNT(DISTINCT),
            // ob wirklich jeder ausgewählte Tag darin vorkommt.
            let tagIDStrings = state.tagIDs.map(\.uuidString)
            let placeholders = tagIDStrings.map { _ in "?" }.joined(separator: ", ")
            let combinedTagsSubquery = """
                SELECT tagID FROM article_tags WHERE articleID = a.id
                UNION
                SELECT tagID FROM feed_tags WHERE feedID = a.feedID
                """

            switch state.tagMatchMode {
            case .any:
                whereClauses.append("""
                    EXISTS (
                        SELECT 1 FROM (\(combinedTagsSubquery)) t
                        WHERE t.tagID IN (\(placeholders))
                    )
                    """)
                for tagIDString in tagIDStrings {
                    _ = arguments.append(contentsOf: [tagIDString])
                }
            case .all:
                whereClauses.append("""
                    (
                        SELECT COUNT(DISTINCT t.tagID) FROM (\(combinedTagsSubquery)) t
                        WHERE t.tagID IN (\(placeholders))
                    ) = ?
                    """)
                for tagIDString in tagIDStrings {
                    _ = arguments.append(contentsOf: [tagIDString])
                }
                _ = arguments.append(contentsOf: [tagIDStrings.count])
            }
        }

        Self.appendDateFilterWhereClause(
            state.dateFilter,
            now: state.now,
            calendar: state.calendar,
            whereClauses: &whereClauses,
            arguments: &arguments
        )
        Self.appendStatusFilterWhereClause(
            state.statusFilter,
            whereClauses: &whereClauses
        )

        if !includeHidden {
            whereClauses.append("s.isHidden = 0")
        }

        let searchJoinSQL = ftsExpression == nil ? "" : "JOIN article_search ON article_search.rowid = a.rowid"
        let whereSQL = whereClauses.isEmpty ? "" : "WHERE \(whereClauses.joined(separator: " AND "))"
        _ = arguments.append(contentsOf: [safeLimit])

        return try database.read { db in
            try ArticleListSnapshot.fetchAll(db, sql: """
                SELECT
                    \(ArticleListSQL.selectColumns)
                \(ArticleListSQL.standardFromJoin)
                \(searchJoinSQL)
                \(whereSQL)
                ORDER BY COALESCE(a.publishedAt, a.arrivedAt) DESC, a.arrivedAt DESC
                LIMIT ?
                """, arguments: arguments)
        }
    }

    private enum UpsertOutcome {
        case inserted(articleID: String)
        case updated(articleID: String)
        case skipped
    }

    private func upsert(_ input: ArticleUpsertInput, db: Database) throws -> UpsertOutcome {
        let sourceID = input.sourceID.trimmedNonEmpty
        let link = input.link.trimmedNonEmpty

        if let articleID = try findExistingArticleID(input: input, db: db) {
            let sourceIDAssignment = sourceID == nil ? "" : "sourceID = COALESCE(sourceID, ?),"

            // Manche Websites ändern nachträglich die Permalink-Struktur eines
            // Artikels (z. B. bei einer Überarbeitung) — der neue Link kann dabei
            // zufällig mit dem bereits gespeicherten Link eines ANDEREN,
            // unabhängigen Artikels desselben Feeds kollidieren (realer Fall:
            // googlewatchblog.de, 2026-08-05, siehe CLAUDE.md-Gotcha). Ein
            // ungeprüftes UPDATE würde dann die partielle UNIQUE-Index-
            // Beschränkung `idx_articles_feed_link_unique` (feedID, link)
            // verletzen und die komplette Batch-Transaktion zurückrollen,
            // wodurch der GESAMTE Feed-Refresh bei jedem Versuch erneut
            // fehlschlägt. In diesem Fall wird der Link bewusst NICHT
            // überschrieben — alle anderen Felder werden trotzdem aktualisiert.
            let linkBelongsToDifferentArticle: Bool
            if let link {
                linkBelongsToDifferentArticle = try String.fetchOne(db, sql: """
                    SELECT id FROM articles WHERE feedID = ? AND link = ? AND id != ?
                    """, arguments: [input.feedID, link, articleID]) != nil
            } else {
                linkBelongsToDifferentArticle = false
            }
            let linkAssignment = linkBelongsToDifferentArticle ? "" : "link = ?,"

            var arguments = StatementArguments()
            if let sourceID {
                _ = arguments.append(contentsOf: [sourceID])
            }
            if !linkBelongsToDifferentArticle {
                _ = arguments.append(contentsOf: [link])
            }
            _ = arguments.append(contentsOf: [
                input.title,
                input.summary,
                input.content,
                input.imageURL,
                input.author,
                input.publishedAt,
                Date(),
                input.estimatedReadingMinutes,
                articleID
            ])

            try db.execute(
                sql: """
                    UPDATE articles
                    SET \(sourceIDAssignment)
                        \(linkAssignment)
                        title = ?,
                        summary = ?,
                        content = ?,
                        imageURL = COALESCE(?, imageURL),
                        author = ?,
                        publishedAt = ?,
                        updatedAt = ?,
                        estimatedReadingMinutes = ?
                    WHERE id = ?
                    """,
                arguments: arguments
            )
            try saveIdentityHistory(forArticleID: articleID, input: input, db: db)
            return .updated(articleID: articleID)
        }

        let history = try findIdentityHistory(input: input, db: db)
        if let history, history.wasRemovedByRetention {
            let configuration = try currentRetentionConfiguration(forFeedID: input.feedID, db: db)
            let effectiveDate = input.publishedAt ?? history.firstSeenAt
            if configuration.isEnabled, effectiveDate < configuration.cutoffDate {
                // Artikel wurde bewusst bereinigt und ist nach aktuellen Einstellungen
                // weiterhin abgelaufen — nicht wieder einfügen.
                return .skipped
            }
        }

        let articleID = UUID().uuidString
        var article = ArticleRecord(
            id: articleID,
            feedID: input.feedID,
            sourceID: sourceID,
            link: link,
            title: input.title,
            summary: input.summary,
            content: input.content,
            imageURL: input.imageURL,
            author: input.author,
            publishedAt: input.publishedAt,
            arrivedAt: input.arrivedAt,
            updatedAt: Date(),
            estimatedReadingMinutes: input.estimatedReadingMinutes
        )
        try article.insert(db)

        let syncStableID = CloudSyncArticleStatusMapping.stableRecordName(
            feedID: input.feedID,
            sourceID: sourceID,
            link: link,
            titleHash: Self.titleHash(input.title)
        )
        var status = ArticleStatusRecord(
            articleID: articleID,
            isRead: history?.isRead ?? false,
            isStarred: history?.isStarred ?? false,
            isArchived: history?.isArchived ?? false,
            isHidden: history?.isHidden ?? false,
            readAt: history?.readAt,
            starredAt: history?.starredAt,
            archivedAt: history?.archivedAt,
            hiddenAt: history?.hiddenAt,
            dateArrived: history?.firstSeenAt ?? input.arrivedAt,
            syncStableID: syncStableID
        )
        try status.insert(db)
        try Self.applyOrphanedStatusUpdateIfPresent(articleID: articleID, syncStableID: syncStableID, db: db)
        try saveIdentityHistory(forArticleID: articleID, input: input, status: status, db: db)

        return .inserted(articleID: articleID)
    }

    /// Übernimmt einen wartenden, verwaisten Artikelstatus (iCloud Sync Phase 2b) — ein
    /// Status, der per iCloud ankam, BEVOR der zugehörige Artikel lokal existierte. Läuft
    /// direkt nach dem Insert der frischen `article_statuses`-Zeile, in derselben
    /// Transaktion. Sucht über `syncStableID` (geräteübergreifend deterministisch), NICHT
    /// über die lokale `articleID` (die ist auf jedem Gerät zufällig und deshalb für diesen
    /// Abgleich ungeeignet — siehe Design-Begründung in
    /// `CloudSyncArticleStatusMapping.stableRecordName`). `statusSyncUpdatedAt` wird bewusst
    /// auf `orphan.receivedAt` gesetzt (lokaler Empfangszeitpunkt des Orphans, nicht der
    /// ursprüngliche `CKRecord.modificationDate` des Absenders) — akzeptierte, dokumentierte
    /// Vereinfachung: ein Folgekonflikt auf genau diesem Status unmittelbar nach der
    /// Reconciliation könnte dadurch in einem schmalen Zeitfenster fälschlich "lokal
    /// gewinnt" statt "Server gewinnt" auflösen. Siehe Design-Spec
    /// docs/superpowers/specs/2026-07-25-icloud-sync-phase2b-design.md, Abschnitt 4.
    static func applyOrphanedStatusUpdateIfPresent(articleID: String, syncStableID: String, db: Database) throws {
        guard let orphan = try OrphanedArticleStatusUpdateRecord.fetchOne(db, key: syncStableID) else { return }

        try db.execute(
            sql: """
                UPDATE article_statuses
                SET isRead = ?, isStarred = ?, readAt = ?, starredAt = ?, statusSyncUpdatedAt = ?
                WHERE articleID = ?
                """,
            arguments: [orphan.isRead, orphan.isStarred, orphan.readAt, orphan.starredAt, orphan.receivedAt, articleID]
        )
        try orphan.delete(db)
    }

    private func currentRetentionConfiguration(forFeedID feedID: String, db: Database) throws -> ArticleRetentionConfiguration {
        let now = Date()
        guard
            let feed = try FeedRecord.fetchOne(db, key: feedID),
            feed.articleRetentionOverridesGlobalSetting
        else {
            return ArticleRetentionConfiguration(
                isEnabled: userDefaults.object(forKey: ArticleRetentionSettings.isEnabledKey) as? Bool
                    ?? ArticleRetentionSettings.defaultIsEnabled,
                retentionDays: userDefaults.object(forKey: ArticleRetentionSettings.retentionDaysKey) as? Int
                    ?? ArticleRetentionSettings.defaultRetentionDays,
                minimumArticlesPerFeed: userDefaults.object(forKey: ArticleRetentionSettings.minimumArticlesPerFeedKey) as? Int
                    ?? ArticleRetentionSettings.defaultMinimumArticlesPerFeed,
                includeProtectedArticles: userDefaults.object(forKey: ArticleRetentionSettings.includesProtectedArticlesKey) as? Bool
                    ?? ArticleRetentionSettings.defaultIncludesProtectedArticles,
                now: now
            )
        }

        return ArticleRetentionConfiguration(
            isEnabled: feed.articleRetentionIsEnabled,
            retentionDays: feed.articleRetentionDays,
            minimumArticlesPerFeed: feed.articleRetentionMinimumArticles,
            includeProtectedArticles: feed.articleRetentionIncludesProtectedArticles,
            now: now
        )
    }

    private func findExistingArticleID(input: ArticleUpsertInput, db: Database) throws -> String? {
        if let sourceID = input.sourceID.trimmedNonEmpty {
            let articleID = try String.fetchOne(db, sql: """
                SELECT id
                FROM articles
                WHERE feedID = ? AND sourceID = ?
                LIMIT 1
                """, arguments: [input.feedID, sourceID])
            if let articleID {
                return articleID
            }
        }

        if let link = input.link.trimmedNonEmpty {
            return try String.fetchOne(db, sql: """
                SELECT id
                FROM articles
                WHERE feedID = ? AND link = ?
                LIMIT 1
                """, arguments: [input.feedID, link])
        }

        return nil
    }

    private func findIdentityHistory(input: ArticleUpsertInput, db: Database) throws -> ArticleIdentityHistoryRecord? {
        if let sourceID = input.sourceID.trimmedNonEmpty {
            let record = try ArticleIdentityHistoryRecord.fetchOne(db, sql: """
                SELECT *
                FROM article_identity_history
                WHERE feedID = ? AND sourceID = ?
                LIMIT 1
                """, arguments: [input.feedID, sourceID])
            if let record {
                return record
            }
        }

        if let link = input.link.trimmedNonEmpty {
            let record = try ArticleIdentityHistoryRecord.fetchOne(db, sql: """
                SELECT *
                FROM article_identity_history
                WHERE feedID = ? AND link = ?
                LIMIT 1
                """, arguments: [input.feedID, link])
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
            """, arguments: [input.feedID, Self.titleHash(input.title)])
    }

    private func saveIdentityHistory(forArticleID articleID: String, input: ArticleUpsertInput, db: Database) throws {
        guard let status = try ArticleStatusRecord.fetchOne(db, key: articleID) else {
            return
        }

        try saveIdentityHistory(forArticleID: articleID, input: input, status: status, db: db)
    }

    private func saveIdentityHistory(
        forArticleID articleID: String,
        input: ArticleUpsertInput,
        status: ArticleStatusRecord,
        db: Database
    ) throws {
        let now = Date()
        let sourceID = input.sourceID.trimmedNonEmpty
        let link = input.link.trimmedNonEmpty
        let titleHash = Self.titleHash(input.title)
        let existing = try findIdentityHistory(input: input, db: db)
        var history = existing ?? ArticleIdentityHistoryRecord(
            id: UUID().uuidString,
            feedID: input.feedID,
            sourceID: sourceID,
            link: link,
            titleHash: titleHash,
            publishedAt: input.publishedAt,
            firstSeenAt: status.dateArrived,
            lastSeenAt: now,
            lastArticleID: articleID,
            isRead: status.isRead,
            isStarred: status.isStarred,
            isArchived: status.isArchived,
            isHidden: status.isHidden,
            readAt: status.readAt,
            starredAt: status.starredAt,
            archivedAt: status.archivedAt,
            hiddenAt: status.hiddenAt
        )

        history.sourceID = history.sourceID ?? sourceID
        history.link = history.link ?? link
        history.titleHash = titleHash
        history.publishedAt = input.publishedAt ?? history.publishedAt
        history.lastSeenAt = now
        history.lastArticleID = articleID
        history.isRead = status.isRead
        history.isStarred = status.isStarred
        history.isArchived = status.isArchived
        history.isHidden = status.isHidden
        history.readAt = status.readAt
        history.starredAt = status.starredAt
        history.archivedAt = status.archivedAt
        history.hiddenAt = status.hiddenAt
        history.wasRemovedByRetention = false

        try history.save(db)
    }

    static func titleHash(_ title: String) -> String {
        let normalizedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let digest = SHA256.hash(data: Data(normalizedTitle.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func appendDateFilterWhereClause(
        _ dateFilter: ArticleSearchDateFilter,
        now: Date,
        calendar: Calendar,
        whereClauses: inout [String],
        arguments: inout StatementArguments
    ) {
        switch dateFilter {
        case .anytime:
            return
        case .today:
            let startOfDay = calendar.startOfDay(for: now)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
                ?? startOfDay.addingTimeInterval(24 * 60 * 60)
            whereClauses.append("a.publishedAt >= ? AND a.publishedAt < ?")
            _ = arguments.append(contentsOf: [startOfDay, endOfDay])
        case .thisWeek:
            let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
            guard let weekInterval else {
                return
            }
            whereClauses.append("a.publishedAt >= ? AND a.publishedAt < ?")
            _ = arguments.append(contentsOf: [weekInterval.start, weekInterval.end])
        }
    }

    private static func appendStatusFilterWhereClause(
        _ statusFilter: ArticleSearchStatusFilter,
        whereClauses: inout [String]
    ) {
        switch statusFilter {
        case .all:
            return
        case .unread:
            whereClauses.append("s.isRead = 0")
        case .read:
            whereClauses.append("s.isRead = 1")
        case .starred:
            whereClauses.append("s.isStarred = 1")
        case .archived:
            whereClauses.append("s.isArchived = 1")
        }
    }

    private static func makeFTSMatchExpression(
        from searchText: String,
        field: ArticleSearchField
    ) -> String? {
        let trimmedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        let separator = try! NSRegularExpression(pattern: #"[^\p{L}\p{N}]+"#)
        let searchRange = NSRange(trimmedText.startIndex..<trimmedText.endIndex, in: trimmedText)
        let tokenText = separator.stringByReplacingMatches(
            in: trimmedText,
            range: searchRange,
            withTemplate: " "
        )
        let tokens = tokenText
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 }

        guard !tokens.isEmpty else {
            return nil
        }

        let tokenExpression = tokens
            .map { "\($0)*" }
            .joined(separator: " ")

        switch field {
        case .all:
            return "{title summary content} : \(tokenExpression)"
        case .title:
            return "title : \(tokenExpression)"
        case .summary:
            return "summary : \(tokenExpression)"
        case .content:
            return "content : \(tokenExpression)"
        }
    }

    private static func readerTags(articleID: String, feedID: String, db: Database) throws -> [ReaderArticleTagMetadata] {
        let records = try TagRecord.fetchAll(db, sql: """
            SELECT DISTINCT t.*
            FROM tags t
            WHERE EXISTS (
                SELECT 1
                FROM article_tags at
                WHERE at.articleID = ?
                    AND at.tagID = t.id
            )
            OR EXISTS (
                SELECT 1
                FROM feed_tags ft
                WHERE ft.feedID = ?
                    AND ft.tagID = t.id
            )
            ORDER BY t.name COLLATE NOCASE, t.id COLLATE NOCASE
            """, arguments: [articleID, feedID])

        return records.map(ReaderArticleTagMetadata.init(record:))
    }
}

private enum ArticleStoreError: Error {
    case emptyBatch
}

extension ArticleReaderSnapshot: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        feedID = row["feedID"]
        feedTitle = row["feedTitle"]
        folderName = row["folderName"]
        title = row["title"]
        link = row["link"]
        summary = row["summary"]
        content = row["content"]
        imageURL = row["imageURL"]
        author = row["author"]
        publishedAt = row["publishedAt"]
        arrivedAt = row["arrivedAt"]
        estimatedReadingMinutes = row["estimatedReadingMinutes"]
        isRead = row["isRead"]
        isStarred = row["isStarred"]
        isArchived = row["isArchived"]
        isHidden = row["isHidden"]
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
