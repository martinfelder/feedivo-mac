import Foundation
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

    init(database: FeedivoDatabase) {
        self.database = database
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
                let result = try upsert(input, db: db)
                articleIDs.append(result.articleID)
                if result.wasInserted {
                    insertedArticleIDs.append(result.articleID)
                } else {
                    updatedArticleIDs.append(result.articleID)
                }
            }

            return ArticleUpsertResult(
                insertedArticleIDs: insertedArticleIDs,
                updatedArticleIDs: updatedArticleIDs,
                articleIDs: articleIDs
            )
        }
    }

    func readerArticle(id: String) throws -> ArticleReaderSnapshot? {
        try database.read { db in
            try ArticleReaderSnapshot.fetchOne(db, sql: """
                SELECT
                    a.id,
                    a.feedID,
                    f.title AS feedTitle,
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
                    feedTitle: feedTitle
                )
            }
        }
    }

    func searchArticles(
        matching query: String,
        includeHidden: Bool = false,
        limit: Int = 100
    ) throws -> [ArticleListSnapshot] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }

        let safeLimit = max(1, limit)
        let hiddenClause = includeHidden ? "" : "AND s.isHidden = 0"

        return try database.read { db in
            try ArticleListSnapshot.fetchAll(db, sql: """
                SELECT
                    a.id,
                    a.feedID,
                    f.title AS feedTitle,
                    a.title,
                    a.summary,
                    a.link,
                    a.imageURL,
                    a.publishedAt,
                    a.arrivedAt,
                    a.estimatedReadingMinutes,
                    s.isRead,
                    s.isStarred,
                    s.isArchived,
                    s.isHidden
                FROM article_search search
                JOIN articles a ON a.rowid = search.rowid
                JOIN feeds f ON f.id = a.feedID
                JOIN article_statuses s ON s.articleID = a.id
                WHERE article_search MATCH ?
                    \(hiddenClause)
                ORDER BY COALESCE(a.publishedAt, a.arrivedAt) DESC, a.arrivedAt DESC
                LIMIT ?
                """, arguments: [trimmedQuery, safeLimit])
        }
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

        if let tagID = state.tagID?.uuidString {
            whereClauses.append("""
                (
                    EXISTS (
                        SELECT 1
                        FROM article_tags at
                        WHERE at.articleID = a.id
                            AND at.tagID = ?
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM feed_tags ft
                        WHERE ft.feedID = a.feedID
                            AND ft.tagID = ?
                    )
                )
                """)
            _ = arguments.append(contentsOf: [tagID, tagID])
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
                    a.id,
                    a.feedID,
                    f.title AS feedTitle,
                    a.title,
                    a.summary,
                    a.link,
                    a.imageURL,
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
                \(searchJoinSQL)
                \(whereSQL)
                ORDER BY COALESCE(a.publishedAt, a.arrivedAt) DESC, a.arrivedAt DESC
                LIMIT ?
                """, arguments: arguments)
        }
    }

    private func upsert(_ input: ArticleUpsertInput, db: Database) throws -> (articleID: String, wasInserted: Bool) {
        let sourceID = input.sourceID.trimmedNonEmpty
        let link = input.link.trimmedNonEmpty

        if let articleID = try findExistingArticleID(input: input, db: db) {
            let sourceIDAssignment = sourceID == nil ? "" : "sourceID = COALESCE(sourceID, ?),"
            var arguments = StatementArguments()
            if let sourceID {
                _ = arguments.append(contentsOf: [sourceID])
            }
            _ = arguments.append(contentsOf: [
                link,
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
                        link = ?,
                        title = ?,
                        summary = ?,
                        content = ?,
                        imageURL = ?,
                        author = ?,
                        publishedAt = ?,
                        updatedAt = ?,
                        estimatedReadingMinutes = ?
                    WHERE id = ?
                    """,
                arguments: arguments
            )
            return (articleID, false)
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

        var status = ArticleStatusRecord(articleID: articleID, dateArrived: input.arrivedAt)
        try status.insert(db)

        return (articleID, true)
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
}

private enum ArticleStoreError: Error {
    case emptyBatch
}

extension ArticleReaderSnapshot: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        feedID = row["feedID"]
        feedTitle = row["feedTitle"]
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
