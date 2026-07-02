import Foundation
import Observation

@MainActor
@Observable
final class SQLiteFeedArticleListState {
    enum LoadState: Equatable {
        case idle
        case missingSQLiteDatabase
        case missingFeed
        case loaded
        case failed(String)
    }

    var loadState: LoadState = .idle
    var rows: [ArticleListSnapshot] = []
    var navigationState = SQLiteArticleNavigationState.empty

    private enum CurrentScope {
        case feedURL(String)
        case tagID(String)
    }

    private var currentScope: CurrentScope?
    private var currentSelectedArticleID: String?

    func load(
        swiftDataFeedURL: String,
        database: FeedivoDatabase?,
        selectedArticleID: String?
    ) {
        currentScope = .feedURL(swiftDataFeedURL)
        currentSelectedArticleID = selectedArticleID

        guard let database else {
            rows = []
            navigationState = .empty
            loadState = .missingSQLiteDatabase
            return
        }

        do {
            guard let feed = try FeedStore(database: database).feed(url: swiftDataFeedURL) else {
                rows = []
                navigationState = .empty
                loadState = .missingFeed
                return
            }

            try loadTimeline(scope: .feed(feed.id), database: database, selectedArticleID: selectedArticleID)
        } catch {
            rows = []
            navigationState = .empty
            loadState = .failed(error.localizedDescription)
        }
    }

    func load(
        tagID: String,
        database: FeedivoDatabase?,
        selectedArticleID: String?
    ) {
        currentScope = .tagID(tagID)
        currentSelectedArticleID = selectedArticleID

        guard let database else {
            rows = []
            navigationState = .empty
            loadState = .missingSQLiteDatabase
            return
        }

        do {
            try loadTimeline(scope: .tag(tagID), database: database, selectedArticleID: selectedArticleID)
        } catch {
            rows = []
            navigationState = .empty
            loadState = .failed(error.localizedDescription)
        }
    }

    func toggleRead(articleID: String, database: FeedivoDatabase) {
        guard let row = rows.first(where: { $0.id == articleID }) else {
            return
        }

        mutateStatus(articleID: articleID, database: database) { store in
            try store.setRead(!row.isRead, articleID: articleID, at: Date())
        }
    }

    func toggleStarred(articleID: String, database: FeedivoDatabase) {
        guard let row = rows.first(where: { $0.id == articleID }) else {
            return
        }

        mutateStatus(articleID: articleID, database: database) { store in
            try store.setStarred(!row.isStarred, articleID: articleID, at: Date())
        }
    }

    func toggleArchived(articleID: String, database: FeedivoDatabase) {
        guard let row = rows.first(where: { $0.id == articleID }) else {
            return
        }

        mutateStatus(articleID: articleID, database: database) { store in
            try store.setArchived(!row.isArchived, articleID: articleID, at: Date())
        }
    }

    private func mutateStatus(
        articleID: String,
        database: FeedivoDatabase,
        operation: (ArticleStatusStore) throws -> Void
    ) {
        do {
            try operation(ArticleStatusStore(database: database))
            currentSelectedArticleID = articleID

            guard let currentScope else {
                return
            }

            switch currentScope {
            case let .feedURL(feedURL):
                load(
                    swiftDataFeedURL: feedURL,
                    database: database,
                    selectedArticleID: currentSelectedArticleID
                )
            case let .tagID(tagID):
                load(
                    tagID: tagID,
                    database: database,
                    selectedArticleID: currentSelectedArticleID
                )
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func loadTimeline(
        scope: TimelineScope,
        database: FeedivoDatabase,
        selectedArticleID: String?
    ) throws {
        rows = try TimelineStore(database: database).articles(
            scope: scope,
            includeRead: true,
            includeHidden: false,
            limit: 500
        )
        navigationState = SQLiteArticleNavigationState(
            articleIDs: rows.map(\.id),
            selectedArticleID: selectedArticleID
        )
        loadState = .loaded
    }
}
