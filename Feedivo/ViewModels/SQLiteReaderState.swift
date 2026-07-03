import Foundation
import Observation

@MainActor
@Observable
final class SQLiteReaderState {
    var snapshot: ArticleReaderSnapshot?
    var preparedArticle: ReaderPreparedArticle = .empty
    var errorMessage: String?
    var isLoading = false

    private var loadedArticleID: String?

    func load(articleID: String, database: FeedivoDatabase) {
        loadedArticleID = articleID
        isLoading = true
        errorMessage = nil

        do {
            let loadedSnapshot = try ArticleDatabase(database: database).readerArticle(id: articleID)
            snapshot = loadedSnapshot

            guard let loadedSnapshot else {
                preparedArticle = .empty
                isLoading = false
                return
            }

            let input = ReaderArticleInput.make(from: loadedSnapshot)
            if let cached = ReaderPreparedArticleCache.shared.prepared(for: input) {
                preparedArticle = cached
            } else {
                let prepared = ReaderPreparedArticle(input: input)
                ReaderPreparedArticleCache.shared.store(prepared, for: input)
                preparedArticle = prepared
            }

            isLoading = false
        } catch {
            snapshot = nil
            preparedArticle = .empty
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func toggleRead(database: FeedivoDatabase) {
        guard let snapshot else {
            return
        }

        mutateStatus(database: database) { store in
            try store.setRead(!snapshot.isRead, articleID: snapshot.id, at: Date())
        }
    }

    func toggleStarred(database: FeedivoDatabase) {
        guard let snapshot else {
            return
        }

        mutateStatus(database: database) { store in
            try store.setStarred(!snapshot.isStarred, articleID: snapshot.id, at: Date())
        }
    }

    func toggleArchived(database: FeedivoDatabase) {
        guard let snapshot else {
            return
        }

        mutateStatus(database: database) { store in
            try store.setArchived(!snapshot.isArchived, articleID: snapshot.id, at: Date())
        }
    }

    func toggleOffline(
        database: FeedivoDatabase,
        offlineDownloadService: SQLiteOfflineDownloadService
    ) async {
        guard let articleID = loadedArticleID else {
            return
        }

        if snapshot?.offlineState.isAvailable == true {
            offlineDownloadService.removeOfflineContent(articleID: articleID, database: database)
        } else {
            await offlineDownloadService.saveForOffline(articleID: articleID, database: database)
        }

        load(articleID: articleID, database: database)
    }

    private func mutateStatus(
        database: FeedivoDatabase,
        operation: (ArticleDatabase) throws -> Void
    ) {
        guard let articleID = loadedArticleID else {
            return
        }

        do {
            try operation(ArticleDatabase(database: database))
            load(articleID: articleID, database: database)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
