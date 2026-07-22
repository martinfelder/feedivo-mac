import Foundation
import GRDB

enum TimelineScope: Equatable, Sendable {
    case all
    case feed(String)
    case tag(String)
    case smartFilter(SmartFilter)
    case smartFolder(SQLiteSmartFolderSnapshot)
}

struct TimelineStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func articles(
        scope: TimelineScope,
        searchText: String? = nil,
        includeRead: Bool,
        includeHidden: Bool,
        sortOption: ArticleSortOption = .newestFirst,
        limit: Int,
        offset: Int = 0
    ) throws -> [ArticleListSnapshot] {
        let query = makeArticlesQuery(
            scope: scope,
            searchText: searchText,
            includeRead: includeRead,
            includeHidden: includeHidden,
            sortOption: sortOption,
            limit: limit,
            offset: offset
        )

        return try database.read { db in
            try ArticleListSnapshot.fetchAll(db, sql: query.sql, arguments: query.arguments)
        }
    }

    func articlesAsync(
        scope: TimelineScope,
        searchText: String? = nil,
        includeRead: Bool,
        includeHidden: Bool,
        sortOption: ArticleSortOption = .newestFirst,
        limit: Int,
        offset: Int = 0
    ) async throws -> [ArticleListSnapshot] {
        let query = makeArticlesQuery(
            scope: scope,
            searchText: searchText,
            includeRead: includeRead,
            includeHidden: includeHidden,
            sortOption: sortOption,
            limit: limit,
            offset: offset
        )

        return try await database.readAsync { db in
            try ArticleListSnapshot.fetchAll(db, sql: query.sql, arguments: query.arguments)
        }
    }

    private func makeArticlesQuery(
        scope: TimelineScope,
        searchText: String?,
        includeRead: Bool,
        includeHidden: Bool,
        sortOption: ArticleSortOption,
        limit: Int,
        offset: Int
    ) -> (sql: String, arguments: StatementArguments) {
        let safeLimit = max(1, limit)
        let safeOffset = max(0, offset)
        let searchExpression = searchText.flatMap(Self.makeFTSMatchExpression)
        var whereClauses: [String] = []
        var arguments = StatementArguments()

        switch scope {
        case .all:
            break
        case let .feed(feedID):
            whereClauses.append("a.feedID = ?")
            _ = arguments.append(contentsOf: [feedID])
        case let .tag(tagID):
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
        case let .smartFilter(smartFilter):
            appendSmartFilterWhereClause(
                smartFilter,
                whereClauses: &whereClauses,
                arguments: &arguments
            )
        case let .smartFolder(folder):
            appendSmartFolderWhereClause(
                folder,
                whereClauses: &whereClauses,
                arguments: &arguments
            )
        }

        if !includeRead {
            whereClauses.append("s.isRead = 0")
        }

        if !includeHidden {
            whereClauses.append("s.isHidden = 0")
        }

        if let searchExpression {
            whereClauses.append("article_search MATCH ?")
            _ = arguments.append(contentsOf: [searchExpression])
        }

        let searchJoinSQL = searchExpression == nil ? "" : "JOIN article_search ON article_search.rowid = a.rowid"
        let whereSQL = whereClauses.isEmpty ? "" : "WHERE \(whereClauses.joined(separator: " AND "))"
        _ = arguments.append(contentsOf: [safeLimit, safeOffset])

        return (
            sql: """
            SELECT
                \(ArticleListSQL.selectColumns)
            \(ArticleListSQL.standardFromJoin)
            \(searchJoinSQL)
            \(whereSQL)
            ORDER BY \(Self.orderBySQL(for: sortOption))
            LIMIT ? OFFSET ?
            """,
            arguments: arguments
        )
    }

    private nonisolated static func orderBySQL(for sortOption: ArticleSortOption) -> String {
        switch sortOption {
        case .newestFirst:
            "COALESCE(a.publishedAt, a.arrivedAt) DESC, a.arrivedAt DESC, a.id ASC"
        case .oldestFirst:
            "COALESCE(a.publishedAt, a.arrivedAt) ASC, a.arrivedAt ASC, a.id ASC"
        case .feed:
            "f.title COLLATE NOCASE ASC, COALESCE(a.publishedAt, a.arrivedAt) DESC, a.id ASC"
        case .title:
            "a.title COLLATE NOCASE ASC, COALESCE(a.publishedAt, a.arrivedAt) DESC, a.id ASC"
        case .shortReadingTimeFirst:
            "a.estimatedReadingMinutes IS NULL ASC, a.estimatedReadingMinutes ASC, COALESCE(a.publishedAt, a.arrivedAt) DESC, a.id ASC"
        }
    }

    func unreadCount(feedID: String) throws -> Int {
        try database.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM articles a
                JOIN article_statuses s ON s.articleID = a.id
                WHERE a.feedID = ?
                    AND s.isRead = 0
                    AND s.isHidden = 0
                """, arguments: [feedID]) ?? 0
        }
    }

    @discardableResult
    func markRead(
        scope: TimelineScope,
        searchText: String?,
        includeHidden: Bool,
        option: ArticleMarkReadOption,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> Int {
        try database.write { db in
            var whereClauses: [String] = ["s.isRead = 0"]
            var arguments = StatementArguments()
            appendScopeWhereClause(
                scope,
                whereClauses: &whereClauses,
                arguments: &arguments
            )

            if !includeHidden {
                whereClauses.append("s.isHidden = 0")
            }

            let searchExpression = searchText.flatMap(Self.makeFTSMatchExpression)
            if let searchExpression {
                whereClauses.append("article_search MATCH ?")
                _ = arguments.append(contentsOf: [searchExpression])
            }

            appendMarkReadOptionWhereClause(
                option,
                now: now,
                calendar: calendar,
                whereClauses: &whereClauses,
                arguments: &arguments
            )

            let searchJoinSQL = searchExpression == nil ? "" : "JOIN article_search ON article_search.rowid = a.rowid"
            let whereSQL = "WHERE \(whereClauses.joined(separator: " AND "))"
            let matchingArticleSQL = """
                SELECT a.id
                FROM articles a
                JOIN feeds f ON f.id = a.feedID
                JOIN article_statuses s ON s.articleID = a.id
                \(searchJoinSQL)
                \(whereSQL)
                """
            let affectedFeedIDs = try String.fetchAll(db, sql: """
                SELECT DISTINCT feedID
                FROM articles
                WHERE id IN (\(matchingArticleSQL))
                """, arguments: arguments)

            guard !affectedFeedIDs.isEmpty else {
                return 0
            }

            let readAt = now
            try db.execute(
                sql: """
                    UPDATE article_statuses
                    SET isRead = 1, readAt = ?
                    WHERE articleID IN (\(matchingArticleSQL))
                    """,
                arguments: StatementArguments([readAt]) + arguments
            )
            let changedCount = db.changesCount

            try db.execute(
                sql: """
                    UPDATE article_identity_history
                    SET isRead = 1, readAt = ?
                    WHERE lastArticleID IN (\(matchingArticleSQL))
                    """,
                arguments: StatementArguments([readAt]) + arguments
            )

            for feedID in affectedFeedIDs {
                try SQLiteUnreadCountService.rebuildFeedUnreadCount(feedID: feedID, db: db)
            }

            return changedCount
        }
    }

    func count(
        scope: TimelineScope,
        searchText: String? = nil,
        includeRead: Bool,
        includeHidden: Bool
    ) throws -> Int {
        let query = makeCountQuery(
            scope: scope,
            searchText: searchText,
            includeRead: includeRead,
            includeHidden: includeHidden
        )

        return try database.read { db in
            try Int.fetchOne(db, sql: query.sql, arguments: query.arguments) ?? 0
        }
    }

    func countAsync(
        scope: TimelineScope,
        searchText: String? = nil,
        includeRead: Bool,
        includeHidden: Bool
    ) async throws -> Int {
        let query = makeCountQuery(
            scope: scope,
            searchText: searchText,
            includeRead: includeRead,
            includeHidden: includeHidden
        )

        return try await database.readAsync { db in
            try Int.fetchOne(db, sql: query.sql, arguments: query.arguments) ?? 0
        }
    }

    private func makeCountQuery(
        scope: TimelineScope,
        searchText: String?,
        includeRead: Bool,
        includeHidden: Bool
    ) -> (sql: String, arguments: StatementArguments) {
        var whereClauses: [String] = []
        var arguments = StatementArguments()
        appendScopeWhereClause(scope, whereClauses: &whereClauses, arguments: &arguments)

        if !includeRead {
            whereClauses.append("s.isRead = 0")
        }

        if !includeHidden {
            whereClauses.append("s.isHidden = 0")
        }

        let searchExpression = searchText.flatMap(Self.makeFTSMatchExpression)
        if let searchExpression {
            whereClauses.append("article_search MATCH ?")
            _ = arguments.append(contentsOf: [searchExpression])
        }

        let whereSQL = whereClauses.isEmpty ? "" : "WHERE \(whereClauses.joined(separator: " AND "))"
        let searchJoinSQL = searchExpression == nil ? "" : "JOIN article_search ON article_search.rowid = a.rowid"
        return (
            sql: """
            SELECT COUNT(*)
            FROM articles a
            JOIN feeds f ON f.id = a.feedID
            JOIN article_statuses s ON s.articleID = a.id
            \(searchJoinSQL)
            \(whereSQL)
            """,
            arguments: arguments
        )
    }

    func readUnreadCounts(
        scope: TimelineScope,
        includeHidden: Bool
    ) throws -> SmartFolderMixedCounts {
        var whereClauses: [String] = []
        var arguments = StatementArguments()
        appendScopeWhereClause(
            scope,
            whereClauses: &whereClauses,
            arguments: &arguments
        )

        if !includeHidden {
            whereClauses.append("s.isHidden = 0")
        }

        let whereSQL = whereClauses.isEmpty ? "" : "WHERE \(whereClauses.joined(separator: " AND "))"

        return try database.read { db in
            try SmartFolderMixedCounts.fetchOne(db, sql: """
                SELECT
                    COALESCE(SUM(CASE WHEN s.isRead = 1 THEN 1 ELSE 0 END), 0) AS read,
                    COALESCE(SUM(CASE WHEN s.isRead = 0 THEN 1 ELSE 0 END), 0) AS unread
                FROM articles a
                JOIN feeds f ON f.id = a.feedID
                JOIN article_statuses s ON s.articleID = a.id
                \(whereSQL)
                """, arguments: arguments) ?? .empty
        }
    }

    private func appendScopeWhereClause(
        _ scope: TimelineScope,
        whereClauses: inout [String],
        arguments: inout StatementArguments
    ) {
        switch scope {
        case .all:
            break
        case let .feed(feedID):
            whereClauses.append("a.feedID = ?")
            _ = arguments.append(contentsOf: [feedID])
        case let .tag(tagID):
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
        case let .smartFilter(smartFilter):
            appendSmartFilterWhereClause(
                smartFilter,
                whereClauses: &whereClauses,
                arguments: &arguments
            )
        case let .smartFolder(folder):
            appendSmartFolderWhereClause(
                folder,
                whereClauses: &whereClauses,
                arguments: &arguments
            )
        }
    }

    private func appendMarkReadOptionWhereClause(
        _ option: ArticleMarkReadOption,
        now: Date,
        calendar: Calendar,
        whereClauses: inout [String],
        arguments: inout StatementArguments
    ) {
        let dateComponent: Calendar.Component
        let value: Int

        switch option {
        case .allVisible:
            return
        case .olderThanOneDay:
            dateComponent = .day
            value = 1
        case .olderThanTwoDays:
            dateComponent = .day
            value = 2
        case .olderThanThreeDays:
            dateComponent = .day
            value = 3
        case .olderThanFourDays:
            dateComponent = .day
            value = 4
        case .olderThanOneWeek:
            dateComponent = .weekOfYear
            value = 1
        case .olderThanTwoWeeks:
            dateComponent = .weekOfYear
            value = 2
        }

        guard let cutoffDate = calendar.date(byAdding: dateComponent, value: -value, to: now) else {
            whereClauses.append("0 = 1")
            return
        }

        whereClauses.append("a.publishedAt IS NOT NULL AND a.publishedAt < ?")
        _ = arguments.append(contentsOf: [cutoffDate])
    }

    private func appendSmartFilterWhereClause(
        _ smartFilter: SmartFilter,
        whereClauses: inout [String],
        arguments: inout StatementArguments
    ) {
        switch smartFilter {
        case .allArticles:
            break
        case .unread:
            whereClauses.append("s.isRead = 0")
        case .starred:
            whereClauses.append("s.isStarred = 1")
        case .today:
            let startOfToday = Calendar.current.startOfDay(for: Date())
            let startOfTomorrow = Calendar.current.date(
                byAdding: .day,
                value: 1,
                to: startOfToday
            ) ?? startOfToday.addingTimeInterval(24 * 60 * 60)
            whereClauses.append("a.publishedAt >= ? AND a.publishedAt < ?")
            _ = arguments.append(contentsOf: [startOfToday, startOfTomorrow])
        case .hidden:
            whereClauses.append("s.isHidden = 1")
        }
    }

    private func appendSmartFolderWhereClause(
        _ folder: SQLiteSmartFolderSnapshot,
        whereClauses: inout [String],
        arguments: inout StatementArguments
    ) {
        let conditionClauses = folder.conditions.compactMap { condition in
            smartFolderConditionSQL(condition, arguments: &arguments)
        }

        guard !conditionClauses.isEmpty else {
            return
        }

        let separator = folder.matchMode == .any ? " OR " : " AND "
        whereClauses.append("(\(conditionClauses.joined(separator: separator)))")
    }

    private func smartFolderConditionSQL(
        _ condition: SQLiteSmartFolderConditionSnapshot,
        arguments: inout StatementArguments
    ) -> String? {
        switch condition.field {
        case .tag:
            return tagConditionSQL(condition, arguments: &arguments)
        case .feed:
            return feedConditionSQL(condition, arguments: &arguments)
        case .feedFolder:
            return stringConditionSQL(
                sqlExpression: "f.folderName",
                conditionOperator: condition.conditionOperator,
                value: condition.value,
                arguments: &arguments
            )
        case .date:
            return dateConditionSQL(condition, arguments: &arguments)
        case .status:
            return statusConditionSQL(condition, arguments: &arguments)
        case .title:
            return stringConditionSQL(
                sqlExpression: "a.title",
                conditionOperator: condition.conditionOperator,
                value: condition.value,
                arguments: &arguments
            )
        case .text:
            return textConditionSQL(condition, arguments: &arguments)
        case .author:
            return stringConditionSQL(
                sqlExpression: "a.author",
                conditionOperator: condition.conditionOperator,
                value: condition.value,
                arguments: &arguments
            )
        }
    }

    private func tagConditionSQL(
        _ condition: SQLiteSmartFolderConditionSnapshot,
        arguments: inout StatementArguments
    ) -> String? {
        let trimmedValue = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        switch condition.conditionOperator {
        case .is, .isNot:
            let hasTagSQL = """
                (
                    EXISTS (
                        SELECT 1
                        FROM article_tags at
                        JOIN tags t ON t.id = at.tagID
                        WHERE at.articleID = a.id
                            AND (at.tagID = ? OR lower(t.name) = lower(?))
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM feed_tags ft
                        JOIN tags t ON t.id = ft.tagID
                        WHERE ft.feedID = a.feedID
                            AND (ft.tagID = ? OR lower(t.name) = lower(?))
                    )
                )
                """
            _ = arguments.append(contentsOf: [trimmedValue, trimmedValue, trimmedValue, trimmedValue])

            return condition.conditionOperator == .isNot
                ? "NOT \(hasTagSQL)"
                : hasTagSQL
        case .contains, .notContains, .startsWith, .endsWith:
            let pattern = Self.likePattern(for: condition.conditionOperator, value: trimmedValue)
            let hasTagSQL = """
                (
                    EXISTS (
                        SELECT 1
                        FROM article_tags at
                        JOIN tags t ON t.id = at.tagID
                        WHERE at.articleID = a.id
                            AND lower(t.name) LIKE ? ESCAPE '\\'
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM feed_tags ft
                        JOIN tags t ON t.id = ft.tagID
                        WHERE ft.feedID = a.feedID
                            AND lower(t.name) LIKE ? ESCAPE '\\'
                    )
                )
                """
            _ = arguments.append(contentsOf: [pattern, pattern])

            return condition.conditionOperator == .notContains
                ? "NOT \(hasTagSQL)"
                : hasTagSQL
        case .olderThanDays:
            return nil
        }
    }

    private func feedConditionSQL(
        _ condition: SQLiteSmartFolderConditionSnapshot,
        arguments: inout StatementArguments
    ) -> String? {
        let trimmedValue = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        switch condition.conditionOperator {
        case .is, .isNot:
            let matchesFeedSQL = "(a.feedID = ? OR lower(f.title) = lower(?))"
            _ = arguments.append(contentsOf: [trimmedValue, trimmedValue])

            return condition.conditionOperator == .isNot
                ? "NOT \(matchesFeedSQL)"
                : matchesFeedSQL
        case .contains, .notContains, .startsWith, .endsWith:
            let pattern = Self.likePattern(for: condition.conditionOperator, value: trimmedValue)
            let matchesFeedSQL = "lower(f.title) LIKE ? ESCAPE '\\'"
            _ = arguments.append(contentsOf: [pattern])

            return condition.conditionOperator == .notContains
                ? "NOT (\(matchesFeedSQL))"
                : matchesFeedSQL
        case .olderThanDays:
            return nil
        }
    }

    private func statusConditionSQL(
        _ condition: SQLiteSmartFolderConditionSnapshot,
        arguments: inout StatementArguments
    ) -> String? {
        guard condition.conditionOperator != .olderThanDays,
              let statusValue = SmartFolderStatusValue(rawValue: condition.value)
        else {
            return nil
        }

        let sqlExpression: String
        let expectedValue: Int
        switch statusValue {
        case .unread:
            sqlExpression = "s.isRead"
            expectedValue = 0
        case .read:
            sqlExpression = "s.isRead"
            expectedValue = 1
        case .starred:
            sqlExpression = "s.isStarred"
            expectedValue = 1
        case .archived:
            sqlExpression = "s.isArchived"
            expectedValue = 1
        case .hidden:
            sqlExpression = "s.isHidden"
            expectedValue = 1
        }

        _ = arguments.append(contentsOf: [expectedValue])
        let matchesStatusSQL = "\(sqlExpression) = ?"
        return condition.conditionOperator == .isNot
            ? "NOT (\(matchesStatusSQL))"
            : matchesStatusSQL
    }

    private func dateConditionSQL(
        _ condition: SQLiteSmartFolderConditionSnapshot,
        arguments: inout StatementArguments
    ) -> String? {
        let calendar = Calendar.current
        let now = Date()

        switch condition.conditionOperator {
        case .is, .isNot:
            guard let dateValue = SmartFolderDateValue(rawValue: condition.value) else {
                return nil
            }

            let range: (Date, Date)
            switch dateValue {
            case .today:
                let start = calendar.startOfDay(for: now)
                let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 60 * 60)
                range = (start, end)
            case .thisWeek:
                let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
                let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start.addingTimeInterval(7 * 24 * 60 * 60)
                range = (start, end)
            }

            _ = arguments.append(contentsOf: [range.0, range.1])
            let matchesRangeSQL = "(a.publishedAt >= ? AND a.publishedAt < ?)"
            return condition.conditionOperator == .isNot
                ? "NOT \(matchesRangeSQL)"
                : matchesRangeSQL
        case .olderThanDays:
            guard let days = Int(condition.value),
                  let threshold = calendar.date(byAdding: .day, value: -days, to: now)
            else {
                return nil
            }

            _ = arguments.append(contentsOf: [threshold])
            return "a.publishedAt < ?"
        case .contains, .notContains, .startsWith, .endsWith:
            return nil
        }
    }

    private func textConditionSQL(
        _ condition: SQLiteSmartFolderConditionSnapshot,
        arguments: inout StatementArguments
    ) -> String? {
        switch condition.conditionOperator {
        case .contains:
            guard let searchExpression = Self.makeFTSMatchExpression(from: condition.value) else {
                return nil
            }

            _ = arguments.append(contentsOf: [searchExpression])
            return """
                EXISTS (
                    SELECT 1
                    FROM article_search
                    WHERE article_search.rowid = a.rowid
                        AND article_search MATCH ?
                )
                """
        case .is, .isNot, .notContains, .startsWith, .endsWith:
            return stringConditionSQL(
                sqlExpression: "COALESCE(a.title, '') || ' ' || COALESCE(a.summary, '') || ' ' || COALESCE(a.content, '')",
                conditionOperator: condition.conditionOperator,
                value: condition.value,
                arguments: &arguments
            )
        case .olderThanDays:
            return nil
        }
    }

    private func stringConditionSQL(
        sqlExpression: String,
        conditionOperator: SmartFolderConditionOperator,
        value: String,
        arguments: inout StatementArguments
    ) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        switch conditionOperator {
        case .is:
            _ = arguments.append(contentsOf: [trimmedValue])
            return "lower(\(sqlExpression)) = lower(?)"
        case .isNot:
            _ = arguments.append(contentsOf: [trimmedValue])
            return "(\(sqlExpression) IS NULL OR lower(\(sqlExpression)) != lower(?))"
        case .contains:
            _ = arguments.append(contentsOf: [Self.likePattern(for: .contains, value: trimmedValue)])
            return "lower(\(sqlExpression)) LIKE ? ESCAPE '\\'"
        case .notContains:
            _ = arguments.append(contentsOf: [Self.likePattern(for: .notContains, value: trimmedValue)])
            return "(\(sqlExpression) IS NULL OR lower(\(sqlExpression)) NOT LIKE ? ESCAPE '\\')"
        case .startsWith:
            _ = arguments.append(contentsOf: [Self.likePattern(for: .startsWith, value: trimmedValue)])
            return "lower(\(sqlExpression)) LIKE ? ESCAPE '\\'"
        case .endsWith:
            _ = arguments.append(contentsOf: [Self.likePattern(for: .endsWith, value: trimmedValue)])
            return "lower(\(sqlExpression)) LIKE ? ESCAPE '\\'"
        case .olderThanDays:
            return nil
        }
    }

    private nonisolated static func escapeLikePattern(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private nonisolated static func likePattern(for conditionOperator: SmartFolderConditionOperator, value: String) -> String {
        let escaped = escapeLikePattern(value).lowercased()
        switch conditionOperator {
        case .startsWith:
            return "\(escaped)%"
        case .endsWith:
            return "%\(escaped)"
        default:
            return "%\(escaped)%"
        }
    }

    private nonisolated static func makeFTSMatchExpression(from searchText: String) -> String? {
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

        return tokens
            .map { "\($0)*" }
            .joined(separator: " ")
    }
}

extension ArticleListSnapshot: FetchableRecord {
    init(row: Row) throws {
        id = row["id"]
        feedID = row["feedID"]
        feedTitle = row["feedTitle"]
        title = row["title"]
        summary = row["summary"]
        link = row["link"]
        imageURL = row["imageURL"]
        publishedAt = row["publishedAt"]
        arrivedAt = row["arrivedAt"]
        estimatedReadingMinutes = row["estimatedReadingMinutes"]
        isRead = row["isRead"]
        isStarred = row["isStarred"]
        isArchived = row["isArchived"]
        isHidden = row["isHidden"]
        faviconURL = row["faviconURL"]
    }
}
