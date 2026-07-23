import Foundation
import Observation

struct FeedOperationProgress: Equatable {
    var title: String
    var completedCount: Int
    var totalCount: Int

    var countText: String {
        "\(completedCount)/\(totalCount)"
    }
}

struct FeedRefreshStatusSummary: Identifiable, Equatable {
    let id = UUID()
    var newArticleCount: Int
    var failedFeedCount: Int
    var totalFeedCount: Int

    var hasFailures: Bool {
        failedFeedCount > 0
    }

    var isFullFailure: Bool {
        failedFeedCount >= totalFeedCount
    }
}

enum FeedRefreshItemStatus: Equatable, Sendable {
    case pending
    case refreshing
    case succeeded
    case failed
}

struct FeedRefreshItem: Identifiable, Equatable, Sendable {
    var id: UUID {
        feedID
    }

    var feedID: UUID
    var feedTitle: String
    var feedURL: String
    var status: FeedRefreshItemStatus
}

enum FeedRefreshItemStatusBatch {
    static func updatedItems(
        _ items: [FeedRefreshItem],
        feedIDs: Set<UUID>,
        status: FeedRefreshItemStatus
    ) -> [FeedRefreshItem] {
        guard !feedIDs.isEmpty else {
            return items
        }

        return items.map { item in
            guard feedIDs.contains(item.feedID), item.status != status else {
                return item
            }

            var updatedItem = item
            updatedItem.status = status
            return updatedItem
        }
    }
}

@Observable
final class FeedViewModel {
    static let maxConcurrentFeedRefreshes = 6

    private let fetchFeed: @Sendable (String) async throws -> ParsedFeed
    private let fetchFeedConditionally: @Sendable (String, FeedHTTPValidators) async throws -> ConditionalFeedFetchResult
    private let discoverFaviconURL: @Sendable (URL) async -> String?
    private let enrichArticleImages: @Sendable ([ParsedArticle]) async -> [ParsedArticle]
    private let notifyFeedRefresh: ([FeedRefreshNotificationResult]) async -> Void
    private let notifyRuleNotifications: ([RuleNotificationResult]) async -> Void
    private let articleRetentionDefaults: UserDefaults
    private let minimumRefreshStatusDuration: Duration

    var isLoading = false
    var errorMessage: String?
    var operationProgress: FeedOperationProgress?
    private(set) var refreshItems: [FeedRefreshItem] = []
    private(set) var recentRefreshStatus: FeedRefreshStatusSummary?
    /// Ergebnis des letzten `refreshAllFeeds`-Aufrufs. Unterscheidet totalen
    /// Misserfolg (.failure) von teilweisem (.partial) — zuvor wurde jeder
    /// Feed-Fehler als gesamter Refresh-Fehler gewertet (BackgroundRefreshService
    /// zeigte „Fehlgeschlagen", obwohl die meisten Feeds aktualisiert wurden).
    private(set) var lastRefreshOutcome: RefreshOutcome?

    enum RefreshOutcome: Equatable {
        case success
        case partial(failedCount: Int)
        case failure
    }

    init(
        fetchFeed: @escaping @Sendable (String) async throws -> ParsedFeed = FeedService.fetchFeed,
        fetchFeedConditionally: @escaping @Sendable (String, FeedHTTPValidators) async throws -> ConditionalFeedFetchResult = FeedService.fetchFeedConditionally,
        discoverFaviconURL: @escaping @Sendable (URL) async -> String? = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        },
        enrichArticleImages: @escaping @Sendable ([ParsedArticle]) async -> [ParsedArticle] = { articles in
            await FeedService.enrichArticleImagesIfNeeded(in: articles)
        },
        notifyFeedRefresh: @escaping ([FeedRefreshNotificationResult]) async -> Void = { results in
            await FeedNotificationService.presentRefreshSummary(for: results)
        },
        notifyRuleNotifications: @escaping ([RuleNotificationResult]) async -> Void = { results in
            await FeedNotificationService.presentRuleSummary(for: results)
        },
        articleRetentionDefaults: UserDefaults = .standard,
        minimumRefreshStatusDuration: Duration = .milliseconds(700)
    ) {
        self.fetchFeed = fetchFeed
        self.fetchFeedConditionally = fetchFeedConditionally
        self.discoverFaviconURL = discoverFaviconURL
        self.enrichArticleImages = enrichArticleImages
        self.notifyFeedRefresh = notifyFeedRefresh
        self.notifyRuleNotifications = notifyRuleNotifications
        self.articleRetentionDefaults = articleRetentionDefaults
        self.minimumRefreshStatusDuration = minimumRefreshStatusDuration
    }

    /// OPML-Importvorschau. Reiner Delegator: die eigentliche Duplikat-Erkennung
    /// und Erreichbarkeitsprüfung läuft im `SQLiteFeedSubscriptionService`, damit
    /// `FeedViewModel` keine eigene Feed-Abruflogik mehr besitzt.
    ///
    /// Ohne `sqliteDatabase` liefert die Vorschau bewusst eine leere Liste, weil
    /// es keinen produktiven Datenbestand gibt, gegen den geprüft werden könnte.
    @MainActor
    func opmlImportPreviewRows(
        for opmlFeeds: [OPMLFeed],
        sqliteDatabase: FeedivoDatabase? = nil,
        onProgress: ((OPMLImportPreviewProgress) -> Void)? = nil
    ) async -> [OPMLImportPreviewRow] {
        guard let sqliteDatabase else {
            return []
        }

        let service = SQLiteFeedSubscriptionService(
            database: sqliteDatabase,
            fetchFeed: fetchFeed,
            discoverFaviconURL: discoverFaviconURL
        )

        return await service.previewOPMLFeeds(for: opmlFeeds, onProgress: onProgress)
    }

    @MainActor
    func importOPMLFeeds(
        _ opmlFeeds: [OPMLFeed],
        allowsDuplicates: Bool = false,
        refreshAfterImport: Bool = true,
        refreshIntervalMinutes: Int = 60,
        sqliteDatabase: FeedivoDatabase? = nil
    ) async throws -> OPMLImportResult {
        // Statt eines vorgetäuschten Erfolgs (imported: 0) werfen — beide Aufrufer
        // (FirstRunWizard, OPMLImportReview) nutzen `try` und zeigen den Fehler
        // über ihre catch-Pfade sichtbar an.
        guard !isLoading else {
            throw FeedImportError.alreadyRunning
        }

        errorMessage = nil
        isLoading = true
        operationProgress = nil
        defer {
            isLoading = false
            operationProgress = nil
        }

        guard let sqliteDatabase else {
            errorMessage = L10n.feedErrorAddFailed
            return OPMLImportResult(total: opmlFeeds.count, imported: 0, skippedDuplicates: 0)
        }

        let service = SQLiteFeedSubscriptionService(
            database: sqliteDatabase,
            fetchFeed: fetchFeed,
            discoverFaviconURL: discoverFaviconURL
        )
        let sqliteResult = try await service.importOPMLFeeds(
            opmlFeeds,
            allowsDuplicates: allowsDuplicates,
            refreshAfterImport: refreshAfterImport,
            refreshIntervalMinutes: refreshIntervalMinutes
        )
        if !sqliteResult.failedFeedTitles.isEmpty {
            errorMessage = L10n.feedErrorRefreshAllPartial(
                sqliteResult.failedFeedTitles.count,
                feedTitles: sqliteResult.failedFeedTitles.joined(separator: ", ")
            )
        }
        if sqliteResult.imported > 0 {
            SQLiteDataInvalidation.bumpStatusVersion()
        }

        return OPMLImportResult(
            total: sqliteResult.total,
            imported: sqliteResult.imported,
            skippedDuplicates: sqliteResult.skippedDuplicates
        )
    }

    // MARK: - SQLite Feed Actions
    //
    // Produktive Feed-Aktionen, die ausschließlich über SQLite/GRDB-Stores
    // (`FeedStore`, `ArticleStore`, `SQLiteFeedRefreshCoordinator`,
    // `SQLiteRuleStore`, `SQLiteFeedSubscriptionService`) laufen.

    /// SQLite-first Feed hinzufügen. Produktiver Pfad: delegiert an
    /// `SQLiteFeedSubscriptionService.addFeed` und übersetzt nur Fehler sowie
    /// Reentrancy in UI-State (`isLoading`, `errorMessage`). Ohne Datenbank
    /// gibt es keinen produktiven Bestand, gegen den ein Duplikat geprüft werden
    /// könnte — die Methode bleibt dann ohne Wirkung.
    @MainActor
    func addFeed(urlString: String, sqliteDatabase: FeedivoDatabase?, folderName: String? = nil) async {
        let cleanedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedURL.isEmpty else {
            errorMessage = L10n.feedErrorEmptyURL
            return
        }

        guard !isLoading else {
            errorMessage = L10n.feedErrorAlreadyRunning
            return
        }

        guard let sqliteDatabase else {
            errorMessage = L10n.feedErrorAddFailed
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
        }

        do {
            let service = sqliteFeedActionService(for: sqliteDatabase)
            try await service.addFeed(
                urlString: cleanedURL,
                refreshIntervalMinutes: BackgroundRefreshSettings.defaultIntervalMinutes,
                folderName: folderName
            )
            SQLiteDataInvalidation.bumpStatusVersion()
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? L10n.feedErrorAddFailed
        } catch {
            errorMessage = L10n.feedErrorAddFailed
        }
    }

    /// SQLite-first Einzel-Refresh anhand der Feed-ID. ContentView resolved die
    /// Auswahl nur per ID. Regeln werden einmalig aus `SQLiteRuleStore` geholt
    /// und als Snapshots an `SQLiteFeedRefreshService` weitergereicht.
    @MainActor
    func refreshFeed(
        feedID: String,
        sqliteDatabase: FeedivoDatabase?
    ) async {
        guard !isLoading else {
            errorMessage = L10n.feedErrorAlreadyRunning
            return
        }

        guard let sqliteDatabase else {
            errorMessage = L10n.feedErrorAddFailed
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
        }

        let service = sqliteFeedActionService(for: sqliteDatabase)

        do {
            let result = try await service.refreshFeed(
                feedID: feedID,
                ruleSnapshots: sqliteRuleSnapshots(from: sqliteDatabase)
            )
            SQLiteDataInvalidation.bumpStatusVersion()
            await notifyFeedRefresh([
                FeedRefreshNotificationResult(
                    feedTitle: result.refreshResult.feedTitle,
                    newArticleCount: result.refreshResult.insertedArticleIDs.count,
                    isNotificationEnabled: result.isNotificationEnabled
                )
            ])
            await notifyRuleNotifications(result.refreshResult.ruleNotifications)
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? L10n.feedErrorParsingFailed
        } catch {
            errorMessage = L10n.feedErrorParsingFailed
        }
    }

    /// SQLite-first Refresh-All: Snapshots werden aus `FeedStore.feeds()` geladen.
    ///
    /// `isAutomatic` unterscheidet einen vom Nutzer ausgelösten Refresh (Menü,
    /// Menubar-Button) von einem automatischen (App-Start-Refresh,
    /// Hintergrund-Scheduler-Tick). Kollidiert ein automatischer Aufruf mit
    /// einem bereits laufenden Refresh, tritt er still zurück statt eine
    /// nutzersichtbare Fehlermeldung zu setzen — der Nutzer hat in diesem Fall
    /// nichts falsch gemacht, zwei interne Ausloeser sind sich nur in die
    /// Quere gekommen (Root-Cause-Fund 2026-07-23).
    @MainActor
    func refreshAllFeeds(sqliteDatabase: FeedivoDatabase, isAutomatic: Bool = false) async {
        guard !isLoading else {
            if !isAutomatic {
                errorMessage = L10n.feedErrorAlreadyRunning
            }
            return
        }

        let service = sqliteFeedActionService(for: sqliteDatabase)

        let snapshots: [FeedRefreshSnapshot]
        do {
            snapshots = try service.refreshSnapshots()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        guard !snapshots.isEmpty else {
            return
        }

        let ruleSnapshots = sqliteRuleSnapshots(from: sqliteDatabase)

        await refreshAllFeedsWithCoordinator(
            snapshots,
            database: sqliteDatabase,
            ruleSnapshots: ruleSnapshots
        )
    }

    /// Produktiver SQLite-Sammel-Refresh: treibt den `SQLiteFeedRefreshCoordinator`
    /// und übersetzt dessen Ergebnis in UI-State (`refreshItems`, `recentRefreshStatus`,
    /// `lastRefreshOutcome`, Fehler-/Benachrichtigungs-Events). Diese Methode ist
    /// bewusst nicht als Legacy markiert — sie ist der produktive Pfad, den
    /// `refreshAllFeeds(sqliteDatabase:)` nutzt.
    @MainActor
    private func refreshAllFeedsWithCoordinator(
        _ snapshots: [FeedRefreshSnapshot],
        database: FeedivoDatabase,
        ruleSnapshots: [RuleEngine.RuleSnapshot] = []
    ) async {
        if snapshots.isEmpty {
            return
        }

        isLoading = true
        errorMessage = nil
        recentRefreshStatus = nil
        refreshItems = snapshots.map { snapshot in
            FeedRefreshItem(
                feedID: snapshot.id,
                feedTitle: snapshot.title,
                feedURL: snapshot.url,
                status: .pending
            )
        }
        let refreshStatusStart = ContinuousClock().now
        operationProgress = FeedOperationProgress(
            title: L10n.feedProgressRefreshAllTitle,
            completedCount: 0,
            totalCount: snapshots.count
        )

        defer {
            isLoading = false
            operationProgress = nil
        }

        let summary = await sqliteFeedActionService(for: database).refreshAllFeeds(
            snapshots,
            ruleSnapshots: ruleSnapshots,
            batchSize: Self.maxConcurrentFeedRefreshes
        )

        for snapshot in snapshots {
            if summary.succeededFeedIDs.contains(snapshot.id) {
                updateRefreshItemStatus(for: snapshot.id, status: .succeeded)
            } else if summary.failedFeedIDs.contains(snapshot.id) {
                updateRefreshItemStatus(for: snapshot.id, status: .failed)
            }
        }

        SQLiteDataInvalidation.bumpStatusVersion()
        await notifyFeedRefresh(summary.notificationResults)
        await notifyRuleNotifications(summary.ruleNotificationResults)
        await waitForMinimumRefreshStatusDuration(since: refreshStatusStart)

        recentRefreshStatus = FeedRefreshStatusSummary(
            newArticleCount: summary.notificationResults.reduce(0) { $0 + $1.newArticleCount },
            failedFeedCount: summary.failedFeedTitles.count,
            totalFeedCount: snapshots.count
        )

        // Fehlgeschlagene Feeds werden bewusst NICHT zusätzlich über `errorMessage`
        // (-> aufdringlicher Modal-Alert) gemeldet: `recentRefreshStatus`/`refreshItems`
        // oben speisen bereits das rechte-untere Status-Widget mit derselben
        // Pro-Feed-Fehlerliste, das bei Fehlern zudem dauerhaft sichtbar bleibt (siehe
        // `clearRecentRefreshStatus(after:)` in ContentView.swift) — ein Modal wäre hier
        // reine Duplizierung (Nutzer-Report 2026-07-12).
        if summary.failedFeedTitles.isEmpty {
            lastRefreshOutcome = .success
        } else if summary.failedFeedTitles.count < snapshots.count {
            lastRefreshOutcome = .partial(failedCount: summary.failedFeedTitles.count)
        } else {
            lastRefreshOutcome = .failure
        }
    }

    @MainActor
    func clearRecentRefreshStatus() {
        recentRefreshStatus = nil
        refreshItems = []
    }

    private func waitForMinimumRefreshStatusDuration(since start: ContinuousClock.Instant) async {
        guard minimumRefreshStatusDuration > .zero else {
            return
        }

        let elapsed = start.duration(to: ContinuousClock().now)
        guard elapsed < minimumRefreshStatusDuration else {
            return
        }

        try? await Task.sleep(for: minimumRefreshStatusDuration - elapsed)
    }

    private func updateRefreshItemStatus(for feedID: UUID, status: FeedRefreshItemStatus) {
        updateRefreshItemStatuses(for: [feedID], status: status)
    }

    private func updateRefreshItemStatuses(for feedIDs: [UUID], status: FeedRefreshItemStatus) {
        let updatedItems = FeedRefreshItemStatusBatch.updatedItems(
            refreshItems,
            feedIDs: Set(feedIDs),
            status: status
        )
        guard updatedItems != refreshItems else {
            return
        }

        refreshItems = updatedItems
    }

    private func sqliteRuleSnapshots(from database: FeedivoDatabase) -> [RuleEngine.RuleSnapshot] {
        (try? SQLiteRuleStore(database: database).ruleSnapshots()) ?? []
    }

    private func sqliteFeedActionService(for database: FeedivoDatabase) -> SQLiteFeedActionService {
        SQLiteFeedActionService(
            database: database,
            fetchFeed: fetchFeed,
            fetchFeedConditionally: fetchFeedConditionally,
            discoverFaviconURL: discoverFaviconURL
        )
    }

    /// SQLite-first Delete anhand der Feed-ID. Löscht den SQLite-`FeedRecord`
    /// per `FeedStore.delete`.
    @MainActor
    func deleteFeed(
        feedID: String,
        sqliteDatabase: FeedivoDatabase?
    ) {
        errorMessage = nil

        if let sqliteDatabase {
            do {
                try sqliteFeedActionService(for: sqliteDatabase).deleteFeed(feedID: feedID)
                SQLiteDataInvalidation.bumpStatusVersion()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func normalizedFeedURL(_ urlString: String) -> String {
        urlString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func incrementOperationProgress() {
        guard var operationProgress else {
            return
        }

        operationProgress.completedCount = min(
            operationProgress.completedCount + 1,
            operationProgress.totalCount
        )
        self.operationProgress = operationProgress
    }
}

struct OPMLImportResult: Equatable {
    let total: Int
    let imported: Int
    let skippedDuplicates: Int
}

/// Fehler beim OPML-Import. `alreadyRunning` signalisiert Aufrufern, dass bereits
/// ein Import/Refresh läuft — statt wie bisher einen leeren Erfolgs-Result
/// (imported: 0) zurückzugeben, der als Erfolg fehlinterpretiert wurde.
struct FeedImportError: LocalizedError {
    let errorDescription: String?

    static let alreadyRunning = FeedImportError(
        errorDescription: L10n.feedImportAlreadyRunning
    )
}
