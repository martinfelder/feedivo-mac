import Foundation
import GRDB

struct ArticleCounts: Equatable, Sendable {
    var totalCount: Int
    var unreadCount: Int
    var starredCount: Int
    var archivedCount: Int
    var hiddenCount: Int
    var statusCount: Int

    static let empty = ArticleCounts(
        totalCount: 0,
        unreadCount: 0,
        starredCount: 0,
        archivedCount: 0,
        hiddenCount: 0,
        statusCount: 0
    )
}

/// Zentrale Fassade für den produktiven SQLite-Artikelpfad.
///
/// Die spezialisierten Stores bleiben klein und testbar; UI-State und Reader
/// sprechen aber über diese Fassade mit der Artikeldatenbank, statt die
/// einzelnen Store-Typen selbst zu koordinieren.
struct ArticleDatabase {
    private let database: FeedivoDatabase
    private let feedStore: FeedStore
    private let articleStore: ArticleStore
    private let statusStore: ArticleStatusStore
    private let timelineStore: TimelineStore

    init(database: FeedivoDatabase) {
        self.database = database
        self.feedStore = FeedStore(database: database)
        self.articleStore = ArticleStore(database: database)
        self.statusStore = ArticleStatusStore(database: database)
        self.timelineStore = TimelineStore(database: database)
    }

    func feedExistsAsync(id: String) async throws -> Bool {
        try await database.readAsync { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM feeds WHERE id = ?)",
                arguments: [id]
            ) ?? false
        }
    }

    func timelineArticles(
        scope: TimelineScope,
        searchText: String? = nil,
        includeRead: Bool = true,
        includeHidden: Bool = false,
        limit: Int = 500
    ) throws -> [ArticleListSnapshot] {
        try timelineStore.articles(
            scope: scope,
            searchText: searchText,
            includeRead: includeRead,
            includeHidden: includeHidden,
            limit: limit
        )
    }

    func timelineArticlesAsync(
        scope: TimelineScope,
        searchText: String? = nil,
        includeRead: Bool = true,
        includeHidden: Bool = false,
        sortOption: ArticleSortOption = .newestFirst,
        limit: Int = 500,
        offset: Int = 0
    ) async throws -> [ArticleListSnapshot] {
        try await timelineStore.articlesAsync(
            scope: scope,
            searchText: searchText,
            includeRead: includeRead,
            includeHidden: includeHidden,
            sortOption: sortOption,
            limit: limit,
            offset: offset
        )
    }

    func fetchArticles(
        feedID: String,
        includeRead: Bool = true,
        includeHidden: Bool = false,
        limit: Int = 500
    ) throws -> [ArticleListSnapshot] {
        try fetchArticles(
            whereSQL: "a.feedID = ?",
            arguments: [feedID],
            includeRead: includeRead,
            includeHidden: includeHidden,
            limit: limit
        )
    }

    func fetchArticles(
        feedIDs: Set<String>,
        includeRead: Bool = true,
        includeHidden: Bool = false,
        limit: Int = 500
    ) throws -> [ArticleListSnapshot] {
        guard !feedIDs.isEmpty else {
            return []
        }

        let sortedFeedIDs = feedIDs.sorted()
        let placeholders = Self.placeholders(count: sortedFeedIDs.count)
        return try fetchArticles(
            whereSQL: "a.feedID IN (\(placeholders))",
            arguments: StatementArguments(sortedFeedIDs),
            includeRead: includeRead,
            includeHidden: includeHidden,
            limit: limit
        )
    }

    func fetchArticles(
        articleIDs: Set<String>,
        includeHidden: Bool = true,
        limit: Int = 500
    ) throws -> [ArticleListSnapshot] {
        guard !articleIDs.isEmpty else {
            return []
        }

        let sortedArticleIDs = articleIDs.sorted()
        let placeholders = Self.placeholders(count: sortedArticleIDs.count)
        return try fetchArticles(
            whereSQL: "a.id IN (\(placeholders))",
            arguments: StatementArguments(sortedArticleIDs),
            includeRead: true,
            includeHidden: includeHidden,
            limit: limit
        )
    }

    func fetchUnreadArticles(
        feedIDs: Set<String>,
        includeHidden: Bool = false,
        limit: Int = 500
    ) throws -> [ArticleListSnapshot] {
        try fetchArticles(
            feedIDs: feedIDs,
            includeRead: false,
            includeHidden: includeHidden,
            limit: limit
        )
    }

    /// Neueste ungelesene Artikel über ALLE Feeds hinweg, für das
    /// Menubar-Dropdown (Feature 21.1). Nutzt intern `fetchUnreadArticles`
    /// mit allen bekannten Feed-IDs statt einer Teilmenge.
    func newestUnread(limit: Int) throws -> [ArticleListSnapshot] {
        let allFeedIDs = try feedStore.feeds().map(\.id)
        guard !allFeedIDs.isEmpty else {
            return []
        }

        return try fetchUnreadArticles(feedIDs: Set(allFeedIDs), limit: limit)
    }

    func searchArticles(
        state: ArticleSearchWindowState,
        includeHidden: Bool = false,
        limit: Int = 500
    ) throws -> [ArticleListSnapshot] {
        try articleStore.searchArticles(
            state: state,
            includeHidden: includeHidden,
            limit: limit
        )
    }

    func articleCounts(feedIDs: Set<String>) throws -> ArticleCounts {
        guard !feedIDs.isEmpty else {
            return .empty
        }

        let sortedFeedIDs = feedIDs.sorted()
        let placeholders = Self.placeholders(count: sortedFeedIDs.count)
        let arguments = StatementArguments(sortedFeedIDs)

        return try database.read { db in
            try ArticleCountsRow.fetchOne(db, sql: """
                SELECT
                    COUNT(a.id) AS totalCount,
                    SUM(CASE WHEN s.isRead = 0 AND s.isHidden = 0 THEN 1 ELSE 0 END) AS unreadCount,
                    SUM(CASE WHEN s.isStarred = 1 THEN 1 ELSE 0 END) AS starredCount,
                    SUM(CASE WHEN s.isArchived = 1 THEN 1 ELSE 0 END) AS archivedCount,
                    SUM(CASE WHEN s.isHidden = 1 THEN 1 ELSE 0 END) AS hiddenCount,
                    COUNT(s.articleID) AS statusCount
                FROM articles a
                JOIN article_statuses s ON s.articleID = a.id
                WHERE a.feedID IN (\(placeholders))
                """, arguments: arguments)?
                .counts ?? .empty
        }
    }

    func readerArticle(id: String) throws -> ArticleReaderSnapshot? {
        try articleStore.readerArticle(id: id)
    }

    func setRead(_ isRead: Bool, articleID: String, at date: Date?) throws {
        try statusStore.setRead(isRead, articleID: articleID, at: date)
    }

    func setStarred(_ isStarred: Bool, articleID: String, at date: Date?) throws {
        try statusStore.setStarred(isStarred, articleID: articleID, at: date)
    }

    func setArchived(_ isArchived: Bool, articleID: String, at date: Date?) throws {
        try statusStore.setArchived(isArchived, articleID: articleID, at: date)
    }

    private func fetchArticles(
        whereSQL baseWhereSQL: String,
        arguments baseArguments: StatementArguments,
        includeRead: Bool,
        includeHidden: Bool,
        limit: Int
    ) throws -> [ArticleListSnapshot] {
        var whereClauses = [baseWhereSQL]
        var arguments = baseArguments

        if !includeRead {
            whereClauses.append("s.isRead = 0")
        }

        if !includeHidden {
            whereClauses.append("s.isHidden = 0")
        }

        _ = arguments.append(contentsOf: [max(1, limit)])

        return try database.read { db in
            try ArticleListSnapshot.fetchAll(db, sql: """
                SELECT
                    \(ArticleListSQL.selectColumns)
                \(ArticleListSQL.standardFromJoin)
                WHERE \(whereClauses.joined(separator: " AND "))
                ORDER BY COALESCE(a.publishedAt, a.arrivedAt) DESC, a.arrivedAt DESC
                LIMIT ?
                """, arguments: arguments)
        }
    }

    private static func placeholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }
}

private struct ArticleCountsRow: FetchableRecord {
    let counts: ArticleCounts

    init(row: Row) throws {
        counts = ArticleCounts(
            totalCount: row["totalCount"] ?? 0,
            unreadCount: row["unreadCount"] ?? 0,
            starredCount: row["starredCount"] ?? 0,
            archivedCount: row["archivedCount"] ?? 0,
            hiddenCount: row["hiddenCount"] ?? 0,
            statusCount: row["statusCount"] ?? 0
        )
    }
}
