import Foundation
import GRDB

struct SQLiteOfflineStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func offline(articleID: String) throws -> ArticleOfflineRecord? {
        try database.read { db in
            try ArticleOfflineRecord.fetchOne(db, key: articleID)
        }
    }

    func markRequested(articleID: String, at date: Date = Date()) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO article_offline (articleID, state, requestedAt, savedAt, errorMessage)
                    VALUES (?, ?, ?, NULL, NULL)
                    ON CONFLICT(articleID) DO UPDATE SET
                        requestedAt = excluded.requestedAt,
                        errorMessage = NULL
                    """,
                arguments: [articleID, ArticleOfflineState.none.rawValue, date]
            )
        }
    }

    func markSaved(
        articleID: String,
        state: ArticleOfflineState,
        content: String,
        at date: Date = Date()
    ) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO article_offline (articleID, state, content, requestedAt, savedAt, errorMessage)
                    VALUES (?, ?, ?, ?, ?, NULL)
                    ON CONFLICT(articleID) DO UPDATE SET
                        state = excluded.state,
                        content = excluded.content,
                        savedAt = excluded.savedAt,
                        errorMessage = NULL
                    """,
                arguments: [articleID, state.rawValue, content, date, date]
            )
        }
        SQLiteDataInvalidation.bumpStatusVersion()
    }

    func markFailed(articleID: String, errorMessage: String, at date: Date = Date()) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO article_offline (articleID, state, content, requestedAt, savedAt, errorMessage)
                    VALUES (?, ?, NULL, ?, NULL, ?)
                    ON CONFLICT(articleID) DO UPDATE SET
                        state = excluded.state,
                        content = NULL,
                        requestedAt = excluded.requestedAt,
                        savedAt = NULL,
                        errorMessage = excluded.errorMessage
                    """,
                arguments: [articleID, ArticleOfflineState.failed.rawValue, date, errorMessage]
            )
        }
        SQLiteDataInvalidation.bumpStatusVersion()
    }

    func remove(articleID: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO article_offline (articleID, state, content, requestedAt, savedAt, errorMessage)
                    VALUES (?, ?, NULL, NULL, NULL, NULL)
                    ON CONFLICT(articleID) DO UPDATE SET
                        state = excluded.state,
                        content = NULL,
                        requestedAt = NULL,
                        savedAt = NULL,
                        errorMessage = NULL
                    """,
                arguments: [articleID, ArticleOfflineState.none.rawValue]
            )
        }
        SQLiteDataInvalidation.bumpStatusVersion()
    }

    func summary() throws -> OfflineArticleStorageSummary {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT content
                FROM article_offline
                WHERE state IN (?, ?)
                    AND content IS NOT NULL
                """, arguments: [ArticleOfflineState.feedContent.rawValue, ArticleOfflineState.fullText.rawValue])

            return rows.reduce(OfflineArticleStorageSummary(articleCount: 0, sizeInBytes: 0)) { summary, row in
                let content: String = row["content"]
                return OfflineArticleStorageSummary(
                    articleCount: summary.articleCount + 1,
                    sizeInBytes: summary.sizeInBytes + Int64(content.data(using: .utf8)?.count ?? 0)
                )
            }
        }
    }

    @discardableResult
    func clearSavedCopies() throws -> Int {
        try database.write { db in
            let removedCount = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM article_offline
                    WHERE state IN (?, ?)
                    """,
                arguments: [ArticleOfflineState.feedContent.rawValue, ArticleOfflineState.fullText.rawValue]
            ) ?? 0

            try db.execute(
                sql: """
                    UPDATE article_offline
                    SET state = ?,
                        content = NULL,
                        savedAt = NULL,
                        errorMessage = NULL
                    WHERE state IN (?, ?)
                    """,
                arguments: [ArticleOfflineState.none.rawValue, ArticleOfflineState.feedContent.rawValue, ArticleOfflineState.fullText.rawValue]
            )

            if removedCount > 0 {
                SQLiteDataInvalidation.bumpStatusVersion()
            }
            return removedCount
        }
    }
}

@MainActor
final class SQLiteOfflineDownloadService {
    private let fetcher: OfflineArticleContentFetching
    private let imageCache: OfflineArticleImageCaching

    init() {
        self.fetcher = URLSessionOfflineArticleContentFetcher()
        self.imageCache = ImageCacheService.shared
    }

    init(fetcher: OfflineArticleContentFetching) {
        self.fetcher = fetcher
        self.imageCache = ImageCacheService.shared
    }

    init(fetcher: OfflineArticleContentFetching, imageCache: OfflineArticleImageCaching) {
        self.fetcher = fetcher
        self.imageCache = imageCache
    }

    func saveForOffline(articleID: String, database: FeedivoDatabase) async {
        let offlineStore = SQLiteOfflineStore(database: database)

        do {
            try offlineStore.markRequested(articleID: articleID)
            guard let snapshot = try ArticleStore(database: database).readerArticle(id: articleID) else {
                try offlineStore.markFailed(
                    articleID: articleID,
                    errorMessage: OfflineDownloadError.missingOriginalURL.localizedDescription
                )
                return
            }

            if let feedContent = normalizedText(snapshot.content) {
                try offlineStore.markSaved(articleID: articleID, state: .feedContent, content: feedContent)
                await cacheArticleImages(imageURL: snapshot.imageURL, content: feedContent)
                return
            }

            guard let url = originalURL(for: snapshot) else {
                try offlineStore.markFailed(
                    articleID: articleID,
                    errorMessage: OfflineDownloadError.missingOriginalURL.localizedDescription
                )
                return
            }

            let downloadedContent = try await fetcher.content(from: url)
            guard let normalizedContent = normalizedText(downloadedContent) else {
                try offlineStore.markFailed(
                    articleID: articleID,
                    errorMessage: OfflineDownloadError.emptyDownloadedContent.localizedDescription
                )
                return
            }

            try offlineStore.markSaved(articleID: articleID, state: .fullText, content: normalizedContent)
            await cacheArticleImages(imageURL: snapshot.imageURL, content: normalizedContent)
        } catch {
            try? offlineStore.markFailed(articleID: articleID, errorMessage: error.localizedDescription)
        }
    }

    @discardableResult
    func archiveForOffline(articleID: String, database: FeedivoDatabase) async -> Bool {
        let offlineStore = SQLiteOfflineStore(database: database)
        let existing = try? offlineStore.offline(articleID: articleID)

        if existing?.state.isAvailable != true {
            await saveForOffline(articleID: articleID, database: database)
        }

        guard (try? offlineStore.offline(articleID: articleID))?.state.isAvailable == true else {
            return false
        }

        try? ArticleStatusStore(database: database).setArchived(true, articleID: articleID, at: Date())
        return true
    }

    func removeOfflineContent(articleID: String, database: FeedivoDatabase) {
        try? SQLiteOfflineStore(database: database).remove(articleID: articleID)
        try? ArticleStatusStore(database: database).setArchived(false, articleID: articleID, at: nil)
    }

    private func originalURL(for snapshot: ArticleReaderSnapshot) -> URL? {
        guard let link = snapshot.link,
              let url = URL(string: link),
              url.scheme != nil
        else {
            return nil
        }

        return url
    }

    private func cacheArticleImages(imageURL: String?, content: String) async {
        let urls = await imageURLs(imageURL: imageURL, content: content)
        guard !urls.isEmpty else {
            return
        }

        await imageCache.cacheImages(from: urls)
    }

    private func imageURLs(imageURL: String?, content: String) async -> [URL] {
        let contentBlocks = await Task.detached(priority: .userInitiated) {
            ReaderContentRenderer.blocks(summary: nil, content: content, fallbackImageURL: nil)
        }.value

        var urls: [URL] = []
        var seenURLs = Set<String>()

        func appendURL(_ urlString: String?) {
            guard let normalizedURLString = normalizedText(urlString),
                  let url = URL(string: normalizedURLString),
                  url.scheme != nil,
                  !seenURLs.contains(url.absoluteString)
            else {
                return
            }

            seenURLs.insert(url.absoluteString)
            urls.append(url)
        }

        appendURL(imageURL)
        for block in contentBlocks {
            if case .image(let urlString) = block {
                appendURL(urlString)
            }
        }

        return urls
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
