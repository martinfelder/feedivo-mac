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

    private func upsert(_ input: ArticleUpsertInput, db: Database) throws -> (articleID: String, wasInserted: Bool) {
        let sourceID = input.sourceID.trimmedNonEmpty
        let link = input.link.trimmedNonEmpty

        if let articleID = try findExistingArticleID(input: input, db: db) {
            let sourceIDAssignment = sourceID == nil ? "" : "sourceID = COALESCE(sourceID, ?),"
            var arguments = StatementArguments()
            if let sourceID {
                arguments.append(contentsOf: [sourceID])
            }
            arguments.append(contentsOf: [
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
