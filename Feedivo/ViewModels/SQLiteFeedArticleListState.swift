import Foundation
import Observation

enum SQLiteTimelineLoadScope: Equatable {
    case feedID(String)
    case tagID(String)
    case smartFilter(SmartFilter)
    case smartFolder(SQLiteSmartFolderSnapshot)

    var includeHidden: Bool {
        switch self {
        case .feedID, .tagID:
            false
        case let .smartFilter(smartFilter):
            smartFilter == .hidden
        case let .smartFolder(smartFolder):
            smartFolder.includesHiddenArticles
        }
    }
}

struct SQLiteTimelineLoadRequest {
    var scope: SQLiteTimelineLoadScope
    var searchText: String?
    var database: FeedivoDatabase?
    var selectedArticleID: String?
}

struct SQLiteTimelineLoadResult {
    var loadState: SQLiteFeedArticleListState.LoadState
    var rows: [ArticleListSnapshot]
    var navigationState: SQLiteArticleNavigationState
}

@MainActor
private final class SQLiteTimelineLoadOperation {
    typealias Loader = SQLiteFeedArticleListState.TimelineLoader
    typealias ResultHandler = (Result<SQLiteTimelineLoadResult, Error>, SQLiteTimelineLoadOperation) -> Void

    let id: Int
    let request: SQLiteTimelineLoadRequest
    var isCanceled = false
    var isFinished = false

    private let loader: Loader
    private let resultHandler: ResultHandler

    init(
        id: Int,
        request: SQLiteTimelineLoadRequest,
        loader: @escaping Loader,
        resultHandler: @escaping ResultHandler
    ) {
        self.id = id
        self.request = request
        self.loader = loader
        self.resultHandler = resultHandler
    }

    func run(_ completion: @escaping (SQLiteTimelineLoadOperation) -> Void) {
        Task { @MainActor in
            var didCallCompletion = false

            func callCompletionIfNeeded() {
                guard !didCallCompletion else {
                    return
                }
                didCallCompletion = true
                completion(self)
            }

            guard !isCanceled else {
                isFinished = true
                callCompletionIfNeeded()
                return
            }

            do {
                let result = try await loader(request)
                guard !isCanceled else {
                    isFinished = true
                    callCompletionIfNeeded()
                    return
                }

                isFinished = true
                resultHandler(.success(result), self)
                callCompletionIfNeeded()
            } catch {
                guard !isCanceled else {
                    isFinished = true
                    callCompletionIfNeeded()
                    return
                }

                isFinished = true
                resultHandler(.failure(error), self)
                callCompletionIfNeeded()
            }
        }
    }
}

@MainActor
private final class SQLiteTimelineLoadQueue {
    private var pendingRequests: [SQLiteTimelineLoadOperation] = []
    private var currentRequest: SQLiteTimelineLoadOperation?

    func replacePendingWithLatest(_ operation: SQLiteTimelineLoadOperation) {
        cancelAllRequests()
        pendingRequests = [operation]
        runNextRequestIfNeeded()
    }

    private func cancelAllRequests() {
        for pendingRequest in pendingRequests {
            pendingRequest.isCanceled = true
        }
        currentRequest?.isCanceled = true
        pendingRequests = []
    }

    private func runNextRequestIfNeeded() {
        removeCanceledAndFinishedRequests()
        guard currentRequest == nil, let requestToRun = pendingRequests.first else {
            return
        }

        currentRequest = requestToRun
        pendingRequests.removeFirst()
        requestToRun.run { [weak self] finishedRequest in
            guard let self else {
                return
            }

            if self.currentRequest === finishedRequest {
                self.currentRequest = nil
            }
            self.runNextRequestIfNeeded()
        }
    }

    private func removeCanceledAndFinishedRequests() {
        pendingRequests = pendingRequests.filter { !$0.isCanceled && !$0.isFinished }
    }
}

@MainActor
@Observable
final class SQLiteFeedArticleListState {
    typealias TimelineLoader = @MainActor (SQLiteTimelineLoadRequest) async throws -> SQLiteTimelineLoadResult

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

    private let timelineLoader: TimelineLoader
    private let timelineQueue = SQLiteTimelineLoadQueue()
    private var nextLoadID = 0
    private var latestLoadID = 0

    init(timelineLoader: TimelineLoader? = nil) {
        self.timelineLoader = timelineLoader ?? Self.defaultTimelineLoader
    }

    func load(
        feedID: String,
        searchText: String? = nil,
        database: FeedivoDatabase?,
        selectedArticleID: String?
    ) {
        startLoad(SQLiteTimelineLoadRequest(
            scope: .feedID(feedID),
            searchText: searchText,
            database: database,
            selectedArticleID: selectedArticleID
        ))
    }

    func load(
        tagID: String,
        searchText: String? = nil,
        database: FeedivoDatabase?,
        selectedArticleID: String?
    ) {
        startLoad(SQLiteTimelineLoadRequest(
            scope: .tagID(tagID),
            searchText: searchText,
            database: database,
            selectedArticleID: selectedArticleID
        ))
    }

    func load(
        smartFilter: SmartFilter,
        searchText: String? = nil,
        database: FeedivoDatabase?,
        selectedArticleID: String?
    ) {
        startLoad(SQLiteTimelineLoadRequest(
            scope: .smartFilter(smartFilter),
            searchText: searchText,
            database: database,
            selectedArticleID: selectedArticleID
        ))
    }

    func load(
        smartFolder: SQLiteSmartFolderSnapshot,
        searchText: String? = nil,
        database: FeedivoDatabase?,
        selectedArticleID: String?
    ) {
        startLoad(SQLiteTimelineLoadRequest(
            scope: .smartFolder(smartFolder),
            searchText: searchText,
            database: database,
            selectedArticleID: selectedArticleID
        ))
    }

    // Bewusst keine erneute Scope-Abfrage nach einer Status-Aenderung: Ein
    // Reload wuerde die Filterbedingung des aktuellen Scopes (z. B. "status
    // ist ungelesen" beim Smart Folder "Ungelesen") sofort erneut anwenden
    // und den gerade bearbeiteten Artikel aus der Liste entfernen. Feeds
    // haben keine solche Bedingung, weshalb Artikel dort schon immer sichtbar
    // blieben - die lokale Mutation gleicht dieses Verhalten fuer alle Scopes
    // an, bis der Nutzer die Liste aktiv neu laedt (Scope-Wechsel, Refresh).
    func toggleRead(articleID: String, database: FeedivoDatabase) {
        guard let row = rows.first(where: { $0.id == articleID }) else {
            return
        }
        let newValue = !row.isRead

        mutateStatus(articleID: articleID, database: database) { store in
            try store.setRead(newValue, articleID: articleID, at: Date())
        } applyLocally: { row in
            row.isRead = newValue
        }
    }

    func markReadIfNeeded(
        articleID: String?,
        database: FeedivoDatabase?,
        isEnabled: Bool
    ) -> Bool {
        guard isEnabled,
              let articleID,
              let database,
              let row = rows.first(where: { $0.id == articleID }),
              !row.isRead
        else {
            return false
        }

        mutateStatus(articleID: articleID, database: database) { store in
            try store.setRead(true, articleID: articleID, at: Date())
        } applyLocally: { row in
            row.isRead = true
        }
        return true
    }

    func toggleStarred(articleID: String, database: FeedivoDatabase) {
        guard let row = rows.first(where: { $0.id == articleID }) else {
            return
        }
        let newValue = !row.isStarred

        mutateStatus(articleID: articleID, database: database) { store in
            try store.setStarred(newValue, articleID: articleID, at: Date())
        } applyLocally: { row in
            row.isStarred = newValue
        }
    }

    func toggleArchived(articleID: String, database: FeedivoDatabase) {
        guard let row = rows.first(where: { $0.id == articleID }) else {
            return
        }
        let newValue = !row.isArchived

        mutateStatus(articleID: articleID, database: database) { store in
            try store.setArchived(newValue, articleID: articleID, at: Date())
        } applyLocally: { row in
            row.isArchived = newValue
        }
    }

    private func mutateStatus(
        articleID: String,
        database: FeedivoDatabase,
        operation: (ArticleDatabase) throws -> Void,
        applyLocally: (inout ArticleListSnapshot) -> Void
    ) {
        do {
            try operation(ArticleDatabase(database: database))

            guard let index = rows.firstIndex(where: { $0.id == articleID }) else {
                return
            }

            applyLocally(&rows[index])
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func startLoad(_ request: SQLiteTimelineLoadRequest) {
        nextLoadID += 1
        let loadID = nextLoadID
        latestLoadID = loadID
        loadState = .idle

        let operation = SQLiteTimelineLoadOperation(
            id: loadID,
            request: request,
            loader: timelineLoader
        ) { [weak self] result, operation in
            guard let self, operation.id == self.latestLoadID, !operation.isCanceled else {
                return
            }

            switch result {
            case let .success(result):
                self.rows = result.rows
                self.navigationState = result.navigationState
                self.loadState = result.loadState
            case let .failure(error):
                guard operation.id == self.latestLoadID else {
                    return
                }

                self.rows = []
                self.navigationState = .empty
                self.loadState = .failed(error.localizedDescription)
            }
        }

        timelineQueue.replacePendingWithLatest(operation)
    }

    private static func defaultTimelineLoader(_ request: SQLiteTimelineLoadRequest) async throws -> SQLiteTimelineLoadResult {
        guard let database = request.database else {
            return SQLiteTimelineLoadResult(
                loadState: .missingSQLiteDatabase,
                rows: [],
                navigationState: .empty
            )
        }

        let articleDatabase = ArticleDatabase(database: database)
        if case let .feedID(feedID) = request.scope,
           try !articleDatabase.feedExists(id: feedID) {
            return SQLiteTimelineLoadResult(
                loadState: .missingFeed,
                rows: [],
                navigationState: .empty
            )
        }

        let timelineScope = request.scope.timelineScope
        let rows = try articleDatabase.timelineArticles(
            scope: timelineScope,
            searchText: request.searchText,
            includeRead: true,
            includeHidden: request.scope.includeHidden,
            limit: 500
        )
        let navigationState = SQLiteArticleNavigationState(
            articleIDs: rows.map(\.id),
            selectedArticleID: request.selectedArticleID
        )
        return SQLiteTimelineLoadResult(
            loadState: .loaded,
            rows: rows,
            navigationState: navigationState
        )
    }
}

private extension SQLiteTimelineLoadScope {
    var timelineScope: TimelineScope {
        switch self {
        case let .feedID(feedID):
            .feed(feedID)
        case let .tagID(tagID):
            .tag(tagID)
        case let .smartFilter(smartFilter):
            .smartFilter(smartFilter)
        case let .smartFolder(smartFolder):
            .smartFolder(smartFolder)
        }
    }
}
