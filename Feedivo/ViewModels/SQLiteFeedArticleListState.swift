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
        case smartFilter(SmartFilter)
        case smartFolder(SQLiteSmartFolderSnapshot)
    }

    private var currentScope: CurrentScope?
    private var currentSearchText: String?
    private var currentSelectedArticleID: String?

    func load(
        swiftDataFeedURL: String,
        searchText: String? = nil,
        database: FeedivoDatabase?,
        selectedArticleID: String?
    ) {
        currentScope = .feedURL(swiftDataFeedURL)
        currentSearchText = searchText
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

            try loadTimeline(
                scope: .feed(feed.id),
                searchText: searchText,
                database: database,
                selectedArticleID: selectedArticleID
            )
        } catch {
            rows = []
            navigationState = .empty
            loadState = .failed(error.localizedDescription)
        }
    }

    func load(
        tagID: String,
        searchText: String? = nil,
        database: FeedivoDatabase?,
        selectedArticleID: String?
    ) {
        currentScope = .tagID(tagID)
        currentSearchText = searchText
        currentSelectedArticleID = selectedArticleID

        guard let database else {
            rows = []
            navigationState = .empty
            loadState = .missingSQLiteDatabase
            return
        }

        do {
            try loadTimeline(
                scope: .tag(tagID),
                searchText: searchText,
                database: database,
                selectedArticleID: selectedArticleID
            )
        } catch {
            rows = []
            navigationState = .empty
            loadState = .failed(error.localizedDescription)
        }
    }

    func load(
        smartFilter: SmartFilter,
        searchText: String? = nil,
        database: FeedivoDatabase?,
        selectedArticleID: String?
    ) {
        currentScope = .smartFilter(smartFilter)
        currentSearchText = searchText
        currentSelectedArticleID = selectedArticleID

        guard let database else {
            rows = []
            navigationState = .empty
            loadState = .missingSQLiteDatabase
            return
        }

        do {
            try loadTimeline(
                scope: .smartFilter(smartFilter),
                searchText: searchText,
                database: database,
                selectedArticleID: selectedArticleID,
                includeHidden: smartFilter == .hidden
            )
        } catch {
            rows = []
            navigationState = .empty
            loadState = .failed(error.localizedDescription)
        }
    }

    func load(
        smartFolder: SQLiteSmartFolderSnapshot,
        searchText: String? = nil,
        database: FeedivoDatabase?,
        selectedArticleID: String?
    ) {
        currentScope = .smartFolder(smartFolder)
        currentSearchText = searchText
        currentSelectedArticleID = selectedArticleID

        guard let database else {
            rows = []
            navigationState = .empty
            loadState = .missingSQLiteDatabase
            return
        }

        do {
            try loadTimeline(
                scope: .smartFolder(smartFolder),
                searchText: searchText,
                database: database,
                selectedArticleID: selectedArticleID,
                includeHidden: smartFolder.includesHiddenArticles
            )
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
                    searchText: currentSearchText,
                    database: database,
                    selectedArticleID: currentSelectedArticleID
                )
            case let .tagID(tagID):
                load(
                    tagID: tagID,
                    searchText: currentSearchText,
                    database: database,
                    selectedArticleID: currentSelectedArticleID
                )
            case let .smartFilter(smartFilter):
                load(
                    smartFilter: smartFilter,
                    searchText: currentSearchText,
                    database: database,
                    selectedArticleID: currentSelectedArticleID
                )
            case let .smartFolder(smartFolder):
                load(
                    smartFolder: smartFolder,
                    searchText: currentSearchText,
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
        searchText: String?,
        database: FeedivoDatabase,
        selectedArticleID: String?,
        includeHidden: Bool = false
    ) throws {
        rows = try TimelineStore(database: database).articles(
            scope: scope,
            searchText: searchText,
            includeRead: true,
            includeHidden: includeHidden,
            limit: 500
        )
        navigationState = SQLiteArticleNavigationState(
            articleIDs: rows.map(\.id),
            selectedArticleID: selectedArticleID
        )
        loadState = .loaded
    }
}

private extension SQLiteSmartFolderSnapshot {
    var includesHiddenArticles: Bool {
        conditions.contains { condition in
            condition.field == .status
                && condition.value == SmartFolderStatusValue.hidden.rawValue
                && condition.conditionOperator != .isNot
        }
    }
}
