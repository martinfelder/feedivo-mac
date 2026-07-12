import Foundation

/// Gemeinsame SQL-Fragmente für alle Stellen, die `ArticleListSnapshot` aus
/// `articles`/`feeds`/`article_statuses`/`article_offline` laden. Vorher war dieser
/// 16-Spalten-SELECT 6-fach unabhängig kopiert — genau diese Duplikation hat bereits einen
/// `faviconURL`-Bug verursacht (siehe CLAUDE.md-Gotcha "Duplizierte SQL-SELECT-Listen").
enum ArticleListSQL {
    static let selectColumns = """
        a.id,
        a.feedID,
        f.title AS feedTitle,
        f.faviconURL AS faviconURL,
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
        s.isHidden,
        COALESCE(o.state, 'none') AS offlineStateRaw
        """

    static let standardFromJoin = """
        FROM articles a
        JOIN feeds f ON f.id = a.feedID
        JOIN article_statuses s ON s.articleID = a.id
        LEFT JOIN article_offline o ON o.articleID = a.id
        """
}
