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
    private var activeLoadToken = UUID()
    private var activeLoadTask: Task<Void, Never>?

    func load(articleID: String, database: FeedivoDatabase) {
        activeLoadTask?.cancel()

        loadedArticleID = articleID
        isLoading = true
        errorMessage = nil
        snapshot = nil
        preparedArticle = .empty

        let loadToken = UUID()
        activeLoadToken = loadToken

        activeLoadTask = Task { [database, articleID, loadToken] in
            var loadedSnapshot: ArticleReaderSnapshot?
            var preparedArticleForSnapshot = ReaderPreparedArticle.empty
            var loadError: String?

            do {
                let loadedData = try await Task.detached(priority: .userInitiated) {
                    try ArticleDatabase(database: database).readerArticle(id: articleID)
                }.value

                loadedSnapshot = loadedData

                if let snapshot = loadedSnapshot {
                    let input = ReaderArticleInput.make(from: snapshot)
                    if let cached = ReaderPreparedArticleCache.shared.prepared(for: input) {
                        preparedArticleForSnapshot = cached
                    } else {
                        preparedArticleForSnapshot = await Task.detached(priority: .userInitiated) {
                            ReaderPreparedArticle(input: input)
                        }.value
                        ReaderPreparedArticleCache.shared.store(preparedArticleForSnapshot, for: input)
                    }
                }
            } catch {
                loadError = error.localizedDescription
            }

            guard !Task.isCancelled,
                  self.loadedArticleID == articleID,
                  self.activeLoadToken == loadToken
            else {
                return
            }

            if let loadedSnapshot {
                self.snapshot = loadedSnapshot
                self.preparedArticle = preparedArticleForSnapshot
            } else {
                self.snapshot = nil
                self.preparedArticle = .empty
            }

            self.errorMessage = loadError
            self.isLoading = false
            self.activeLoadTask = nil
            self.activeLoadToken = loadToken
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
