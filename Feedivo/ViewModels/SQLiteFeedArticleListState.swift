import Foundation
import GRDB
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
    var sortOption: ArticleSortOption = .newestFirst
    var offset = 0
    var limit = ArticleFetchLimits.mainArticlePage
}

struct SQLiteTimelineLoadResult {
    var loadState: SQLiteFeedArticleListState.LoadState
    var rows: [ArticleListSnapshot]
    var navigationState: SQLiteArticleNavigationState
    var hasMore = false
    var totalUnreadCount = 0
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
    private(set) var hasMore = false
    private(set) var isLoadingMore = false
    private(set) var totalUnreadCount = 0

    private let timelineLoader: TimelineLoader
    private let timelineQueue = SQLiteTimelineLoadQueue()
    private var nextLoadID = 0
    private var latestLoadID = 0
    private var lastRequest: SQLiteTimelineLoadRequest?

    init(timelineLoader: TimelineLoader? = nil) {
        self.timelineLoader = timelineLoader ?? Self.defaultTimelineLoader
    }

    func load(
        feedID: String,
        searchText: String? = nil,
        database: FeedivoDatabase?,
        selectedArticleID: String?,
        sortOption: ArticleSortOption = .newestFirst
    ) {
        startLoad(SQLiteTimelineLoadRequest(
            scope: .feedID(feedID),
            searchText: searchText,
            database: database,
            selectedArticleID: selectedArticleID,
            sortOption: sortOption
        ))
    }

    func load(
        tagID: String,
        searchText: String? = nil,
        database: FeedivoDatabase?,
        selectedArticleID: String?,
        sortOption: ArticleSortOption = .newestFirst
    ) {
        startLoad(SQLiteTimelineLoadRequest(
            scope: .tagID(tagID),
            searchText: searchText,
            database: database,
            selectedArticleID: selectedArticleID,
            sortOption: sortOption
        ))
    }

    func load(
        smartFilter: SmartFilter,
        searchText: String? = nil,
        database: FeedivoDatabase?,
        selectedArticleID: String?,
        sortOption: ArticleSortOption = .newestFirst
    ) {
        startLoad(SQLiteTimelineLoadRequest(
            scope: .smartFilter(smartFilter),
            searchText: searchText,
            database: database,
            selectedArticleID: selectedArticleID,
            sortOption: sortOption
        ))
    }

    func load(
        smartFolder: SQLiteSmartFolderSnapshot,
        searchText: String? = nil,
        database: FeedivoDatabase?,
        selectedArticleID: String?,
        sortOption: ArticleSortOption = .newestFirst
    ) {
        startLoad(SQLiteTimelineLoadRequest(
            scope: .smartFolder(smartFolder),
            searchText: searchText,
            database: database,
            selectedArticleID: selectedArticleID,
            sortOption: sortOption
        ))
    }

    func loadMore() {
        guard hasMore,
              !isLoadingMore,
              var request = lastRequest
        else {
            return
        }

        request.offset = rows.count
        isLoadingMore = true
        let expectedLoadID = latestLoadID

        Task { @MainActor in
            do {
                let result = try await timelineLoader(request)
                guard expectedLoadID == latestLoadID else {
                    return
                }

                let knownIDs = Set(rows.map(\.id))
                rows.append(contentsOf: result.rows.filter { !knownIDs.contains($0.id) })
                hasMore = result.hasMore
                navigationState = SQLiteArticleNavigationState(
                    articleIDs: rows.map(\.id),
                    selectedArticleID: request.selectedArticleID
                )
                loadState = .loaded
                isLoadingMore = false
            } catch {
                guard expectedLoadID == latestLoadID else {
                    return
                }
                loadState = .failed(error.localizedDescription)
                isLoadingMore = false
            }
        }
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

        let didMutate = mutateStatus(
            articleID: articleID,
            database: database,
            operation: { store in
                try store.setRead(newValue, articleID: articleID, at: Date())
            },
            applyLocally: { row in
                row.isRead = newValue
            }
        )
        guard didMutate else {
            return
        }
        if !row.isHidden {
            totalUnreadCount = max(0, totalUnreadCount + (newValue ? -1 : 1))
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

        let didMutate = mutateStatus(
            articleID: articleID,
            database: database,
            operation: { store in
                try store.setRead(true, articleID: articleID, at: Date())
            },
            applyLocally: { row in
                row.isRead = true
            }
        )
        guard didMutate else {
            return false
        }
        if !row.isHidden {
            totalUnreadCount = max(0, totalUnreadCount - 1)
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

    // Kein reload() nach einem fehlgeschlagenen Loeschen: reload() wuerde
    // ueber startLoad() den gerade gesetzten .failed-Zustand sofort wieder
    // ueberschreiben (startLoad setzt loadState = .idle, danach ggf. .loaded),
    // und die Fehlermeldung waere fuer den Nutzer nie sichtbar gewesen.
    @discardableResult
    func deleteArticle(
        articleID: String,
        database: FeedivoDatabase,
        deindexForSpotlight: ([String]) -> Void = { SpotlightIndexingService.deindexArticles(ids: $0) }
    ) -> Bool {
        do {
            try database.write { db in
                try CloudSyncArticleStatusMapping.enqueueDeletionIfSynced(articleIDs: [articleID], db: db)
                // feedID VOR dem DELETE lesen — danach ist die Zeile weg und
                // rebuildFeedUnreadCount(forArticleID:) könnte den Feed nicht
                // mehr finden (dieselbe Reihenfolge wie bei der Artikel-ID-
                // Historie weiter oben in dieser Datei).
                let feedID = try String.fetchOne(db, sql: "SELECT feedID FROM articles WHERE id = ?", arguments: [articleID])
                try db.execute(sql: "DELETE FROM articles WHERE id = ?", arguments: [articleID])
                if let feedID {
                    try SQLiteUnreadCountService.rebuildFeedUnreadCount(feedID: feedID, db: db)
                }
            }
            CloudSyncEngine.notifyPendingChangesAvailable(database: database)
            deindexForSpotlight([articleID])
            if let deletedRow = rows.first(where: { $0.id == articleID }),
               !deletedRow.isRead,
               !deletedRow.isHidden {
                totalUnreadCount = max(0, totalUnreadCount - 1)
            }
            rows.removeAll { $0.id == articleID }
            return true
        } catch {
            loadState = .failed(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    private func mutateStatus(
        articleID: String,
        database: FeedivoDatabase,
        operation: (ArticleDatabase) throws -> Void,
        applyLocally: (inout ArticleListSnapshot) -> Void
    ) -> Bool {
        do {
            try operation(ArticleDatabase(database: database))

            guard let index = rows.firstIndex(where: { $0.id == articleID }) else {
                return false
            }

            applyLocally(&rows[index])
            return true
        } catch {
            loadState = .failed(error.localizedDescription)
            return false
        }
    }

    private func startLoad(_ request: SQLiteTimelineLoadRequest) {
        nextLoadID += 1
        let loadID = nextLoadID
        latestLoadID = loadID
        loadState = .idle
        hasMore = false
        isLoadingMore = false
        lastRequest = request

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
                self.hasMore = result.hasMore
                self.totalUnreadCount = result.totalUnreadCount
                self.loadState = result.loadState
            case let .failure(error):
                guard operation.id == self.latestLoadID else {
                    return
                }

                self.rows = []
                self.navigationState = .empty
                self.hasMore = false
                self.totalUnreadCount = 0
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
                navigationState: .empty,
                hasMore: false
            )
        }

        let articleDatabase = ArticleDatabase(database: database)
        if case let .feedID(feedID) = request.scope,
           try await articleDatabase.feedExistsAsync(id: feedID) == false {
            return SQLiteTimelineLoadResult(
                loadState: .missingFeed,
                rows: [],
                navigationState: .empty,
                hasMore: false
            )
        }

        let timelineScope = request.scope.timelineScope
        let fetchedRows = try await articleDatabase.timelineArticlesAsync(
            scope: timelineScope,
            searchText: request.searchText,
            includeRead: true,
            includeHidden: request.scope.includeHidden,
            sortOption: request.sortOption,
            limit: request.limit + 1,
            offset: request.offset
        )
        let hasMore = fetchedRows.count > request.limit
        let rows = hasMore ? Array(fetchedRows.prefix(request.limit)) : fetchedRows
        let totalUnreadCount: Int
        if request.offset == 0 {
            totalUnreadCount = try await TimelineStore(database: database).countAsync(
                scope: timelineScope,
                searchText: request.searchText,
                includeRead: false,
                includeHidden: request.scope.includeHidden
            )
        } else {
            // Beim Nachladen bleibt der bereits ermittelte Gesamtzähler gültig;
            // eine zweite COUNT-Abfrage pro Seite wäre reine Zusatzarbeit.
            totalUnreadCount = 0
        }
        let navigationState = SQLiteArticleNavigationState(
            articleIDs: rows.map(\.id),
            selectedArticleID: request.selectedArticleID
        )
        return SQLiteTimelineLoadResult(
            loadState: .loaded,
            rows: rows,
            navigationState: navigationState,
            hasMore: hasMore,
            totalUnreadCount: totalUnreadCount
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
