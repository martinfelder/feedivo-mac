import Foundation
import Observation
import SwiftData

struct FeedOperationProgress: Equatable {
    var title: String
    var completedCount: Int
    var totalCount: Int

    var fractionCompleted: Double {
        guard totalCount > 0 else {
            return 0
        }

        return Double(completedCount) / Double(totalCount)
    }

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

enum OPMLImportFeedStatus: Equatable {
    case available
    case duplicate
    case unreachable
}

struct OPMLImportPreviewRow: Identifiable, Equatable {
    let id = UUID()
    var feed: OPMLFeed
    var status: OPMLImportFeedStatus
    var isSelected: Bool
}

struct OPMLImportPreviewProgress: Equatable {
    var currentFeedTitle: String
    var currentIndex: Int
    var totalCount: Int

    var displayText: String {
        "Feed \(currentIndex) von \(totalCount) wird geprüft: \(currentFeedTitle)"
    }
}

private struct FeedRefreshResult {
    var feedNotification: FeedRefreshNotificationResult
    var ruleNotifications: [RuleNotificationResult]
}

private enum FeedRefreshOutcome {
    case success(FeedRefreshResult)
    case failure(String)
}

enum StoredArticleRefreshFieldUpdate {
    static func replacement(for existingValue: String?, from parsedValue: String?) -> String? {
        guard let parsedValue = nonEmptyText(parsedValue),
              existingValue != parsedValue
        else {
            return nil
        }

        return parsedValue
    }

    static func missingReplacement(for existingValue: @autoclosure () -> String?, from parsedValue: String?) -> String? {
        guard let parsedValue = nonEmptyText(parsedValue),
              isMissingText(existingValue())
        else {
            return nil
        }

        return parsedValue
    }

    private static func nonEmptyText(_ text: String?) -> String? {
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedText, !trimmedText.isEmpty else {
            return nil
        }

        return text
    }

    private static func isMissingText(_ text: String?) -> Bool {
        text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
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

    @MainActor
    func opmlImportPreviewRows(
        for opmlFeeds: [OPMLFeed],
        existingFeeds: [Feed],
        onProgress: ((OPMLImportPreviewProgress) -> Void)? = nil
    ) async -> [OPMLImportPreviewRow] {
        var knownFeedURLs = Set(existingFeeds.map { normalizedFeedURL($0.url) })

        // Phase 1 — sequenziell: Duplikat-Status feststellen und Abruf-Bedarf
        // sammeln. Das URL-Set darf nicht concurrent mutiert werden, daher bleibt
        // diese Phase bewusst seriell. Der onProgress-Callback wird hier pro
        // Feed in Original-Reihenfolge aufgerufen (bestehendes Verhalten: eine
        // Meldung je Feed vor dem Abruf). Die Reihenfolge der zurückgegebenen
        // Rows entspricht der Reihenfolge von `opmlFeeds`.
        struct PendingFeed {
            let index: Int
            let cleanedURL: String
        }
        var pending: [PendingFeed] = []
        // Indexiertes Ergebnis-Array, damit die Abrufe in Phase 2 parallel laufen
        // können, ohne die Original-Reihenfolge zu verlieren.
        var rowsByIndex = Array<OPMLImportPreviewRow?>(repeating: nil, count: opmlFeeds.count)

        for (index, opmlFeed) in opmlFeeds.enumerated() {
            onProgress?(
                OPMLImportPreviewProgress(
                    currentFeedTitle: opmlFeed.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    currentIndex: index + 1,
                    totalCount: opmlFeeds.count
                )
            )
            let cleanedURL = opmlFeed.xmlURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedURL = normalizedFeedURL(cleanedURL)
            let isDuplicate = !knownFeedURLs.insert(normalizedURL).inserted

            if isDuplicate {
                rowsByIndex[index] = OPMLImportPreviewRow(
                    feed: opmlFeed,
                    status: .duplicate,
                    isSelected: false
                )
            } else {
                pending.append(PendingFeed(index: index, cleanedURL: cleanedURL))
            }
        }

        // Phase 2 — parallel: Erreichbarkeit prüfen, in begrenzten Gruppen
        // (gleiche Drosselung wie importOPMLFeeds/refreshAllFeeds). Ergebnisse
        // werden indexiert in `rowsByIndex` einsortiert, nicht in eine gemeinsam
        // mutierte Liste appendet — so bleibt die Original-Reihenfolge erhalten.
        //
        // Fortschritts-Updates in Phase 2: Pro abgeschlossenem Abruf feuern wir
        // onProgress. `completedFetches` ist ein monotoner MainActor-Zähler, der
        // unabhängig von der Completion-Reihenfolge der Tasks deterministisch
        // 1..k hochzählt. Ohne diese Updates würde der Fortschrittsbalken während
        // der langsamen Abruf-Phase (dem Punkt der Parallelisierung) sichtbar
        // „einfrieren" — Phase 1 ist reine Duplikat-Schau ohne Netzwerk-I/O.
        var completedFetches = 0
        for batch in feedBatches(from: pending) {
            await withTaskGroup(of: (Int, OPMLImportFeedStatus).self) { group in
                for item in batch {
                    group.addTask { @MainActor in
                        do {
                            _ = try await self.fetchFeed(item.cleanedURL)
                            return (item.index, .available)
                        } catch {
                            return (item.index, .unreachable)
                        }
                    }
                }
                for await (index, status) in group {
                    completedFetches += 1
                    let isSelected = (status == .available)
                    rowsByIndex[index] = OPMLImportPreviewRow(
                        feed: opmlFeeds[index],
                        status: status,
                        isSelected: isSelected
                    )
                    // currentIndex nutzt den deterministischen MainActor-Zähler
                    // (1..k), nicht den Index im opmlFeeds-Array — so bleibt die
                    // Progress-Anzeige stabil unabhängig davon, welcher Task
                    // zuerst fertig wird. totalCount bezieht sich wie in Phase 1
                    // auf alle Feeds im OPML-Import.
                    onProgress?(
                        OPMLImportPreviewProgress(
                            currentFeedTitle: opmlFeeds[index].title.trimmingCharacters(in: .whitespacesAndNewlines),
                            currentIndex: completedFetches,
                            totalCount: opmlFeeds.count
                        )
                    )
                }
            }
        }

        return rowsByIndex.compactMap { $0 }
    }

    @MainActor
    func importOPMLFeeds(
        _ opmlFeeds: [OPMLFeed],
        existingFeeds: [Feed],
        allowsDuplicates: Bool = false,
        refreshAfterImport: Bool = true,
        refreshIntervalMinutes: Int = 60,
        context: ModelContext
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

        var knownFeedURLs = Set(existingFeeds.map { normalizedFeedURL($0.url) })
        var importedCount = 0
        var skippedDuplicateCount = 0
        var failedFeedTitles: [String] = []

        // Phase 1: Deduplizierung und Feed-Erstellung (sequenziell — URL-Set darf nicht concurrent mutiert werden)
        var feedsToRefresh: [Feed] = []
        for opmlFeed in opmlFeeds {
            let cleanedURL = opmlFeed.xmlURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedURL.isEmpty else {
                continue
            }

            let normalizedURL = normalizedFeedURL(cleanedURL)
            guard allowsDuplicates || knownFeedURLs.insert(normalizedURL).inserted else {
                skippedDuplicateCount += 1
                continue
            }

            let feed = Feed(
                url: cleanedURL,
                title: opmlFeed.title.trimmingCharacters(in: .whitespacesAndNewlines),
                siteURL: opmlFeed.htmlURL,
                followedAt: Date(),
                folderName: opmlFeed.folderName,
                refreshIntervalMinutes: BackgroundRefreshSettings.clampedIntervalMinutes(refreshIntervalMinutes)
            )
            context.insert(feed)
            appendLog(
                kind: .info,
                message: L10n.feedLogImportedFromOPML,
                to: feed,
                context: context
            )
            importedCount += 1
            feedsToRefresh.append(feed)
        }

        // Phase 2: Neue Feeds in begrenzten Gruppen abrufen. So bleibt Netzwerk-I/O
        // parallel, ohne bei großen OPML-Imports alle Feeds gleichzeitig anzustoßen.
        if refreshAfterImport && !feedsToRefresh.isEmpty {
            operationProgress = FeedOperationProgress(
                title: L10n.feedProgressOPMLImportTitle,
                completedCount: 0,
                totalCount: feedsToRefresh.count
            )
        }

        if refreshAfterImport {
            for feedBatch in feedBatches(from: feedsToRefresh) {
                await withTaskGroup(of: String?.self) { group in
                    for feed in feedBatch {
                        group.addTask { @MainActor in
                            do {
                                _ = try await self.refreshFeedContents(feed, context: context)
                                return nil
                            } catch let error as LocalizedError {
                                self.appendLog(
                                    kind: .error,
                                    message: error.errorDescription ?? L10n.feedErrorParsingFailed,
                                    to: feed,
                                    context: context
                                )
                                try? context.save()
                                return feed.title
                            } catch {
                                self.appendLog(
                                    kind: .error,
                                    message: L10n.feedErrorParsingFailed,
                                    to: feed,
                                    context: context
                                )
                                try? context.save()
                                return feed.title
                            }
                        }
                    }

                    for await failedTitle in group {
                        if let failedTitle {
                            failedFeedTitles.append(failedTitle)
                        }

                        incrementOperationProgress()
                    }
                }
            }
        }

        try context.save()
        if !failedFeedTitles.isEmpty {
            errorMessage = L10n.feedErrorRefreshAllPartial(
                failedFeedTitles.count,
                feedTitles: failedFeedTitles.joined(separator: ", ")
            )
        }

        return OPMLImportResult(
            total: opmlFeeds.count,
            imported: importedCount,
            skippedDuplicates: skippedDuplicateCount
        )
    }

    static func opmlFeedsForExport(from feeds: [Feed]) -> [OPMLFeed] {
        feeds.map { feed in
            OPMLFeed(
                title: feed.title,
                xmlURL: feed.url,
                htmlURL: feed.siteURL,
                folderName: feed.folderName,
                description: feed.feedDescription,
                tagNames: (feed.tags ?? []).map(\.name).sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                }
            )
        }
    }

    @MainActor
    func renameFeed(_ feed: Feed?, displayTitle: String, context: ModelContext) {
        guard let feed else {
            return
        }

        let cleanedTitle = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else {
            errorMessage = L10n.feedRenameEmptyName
            return
        }

        errorMessage = nil
        feed.originalTitle = feed.originalTitle ?? feed.title
        feed.title = cleanedTitle

        do {
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func restoreOriginalFeedTitle(_ feed: Feed?, context: ModelContext) {
        guard let feed else {
            return
        }

        let originalTitle = feed.originalTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let originalTitle, !originalTitle.isEmpty else {
            return
        }

        errorMessage = nil
        feed.title = originalTitle
        feed.originalTitle = originalTitle

        do {
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func addFeed(urlString: String, context: ModelContext) async {
        let cleanedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedURL.isEmpty else {
            errorMessage = L10n.feedErrorEmptyURL
            return
        }

        // Reentrancy-Guard — konsistent mit refreshFeed/refreshAllFeeds/importOPMLFeeds:
        // ein parallel laufender Refresh würde sonst isLoading überschreiben und die
        // UI fälschlich „nicht lädt" zeigen, während der Hintergrund-Refresh weiterläuft.
        guard !isLoading else {
            errorMessage = L10n.feedErrorAlreadyRunning
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let parsedFeed = try await fetchFeed(cleanedURL)

            // Duplikat-Prüfung — konsistent zum OPML-Pfad (importOPMLFeeds):
            // ein bereits abonnierter Feed mit derselben normalisierten URL
            // wird nicht erneut hinzugefügt. Prüfung nach fetchFeed, weil erst
            // dann die kanonische sourceURL feststeht.
            let knownFeedURLs = Set(
                ((try? context.fetch(FetchDescriptor<Feed>())) ?? [])
                    .map { normalizedFeedURL($0.url) }
            )
            if knownFeedURLs.contains(normalizedFeedURL(parsedFeed.sourceURL)) {
                errorMessage = L10n.feedErrorDuplicate
                isLoading = false
                return
            }

            let enrichedArticles = await enrichArticleImagesIfNeeded(parsedFeed.articles)
            let feed = Feed(
                url: parsedFeed.sourceURL,
                title: parsedFeed.title,
                feedDescription: parsedFeed.description,
                faviconURL: await faviconURL(for: parsedFeed),
                siteURL: parsedFeed.siteURL,
                followedAt: Date(),
                lastRefreshed: Date()
            )

            feed.articles = enrichedArticles.map { parsedArticle in
                Article(
                    title: parsedArticle.title,
                    link: parsedArticle.link,
                    summary: parsedArticle.summary,
                    content: parsedArticle.content,
                    publishedAt: parsedArticle.publishedAt,
                    imageURL: parsedArticle.imageURL,
                    sourceID: parsedArticle.sourceID,
                    feed: feed
                )
            }
            feed.unreadCount = Self.unreadIncrement(for: feed.articles ?? [])

            context.insert(feed)
            appendLog(
                kind: .info,
                message: L10n.feedLogAdded,
                to: feed,
                context: context
            )
            try context.save()
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? L10n.feedErrorAddFailed
        } catch {
            errorMessage = L10n.feedErrorAddFailed
        }

        isLoading = false
    }

    @MainActor
    func refreshFeed(_ feed: Feed?, context: ModelContext) async {
        guard !isLoading else {
            // Statt stillen Drops: Nutzer bekommt Feedback, dass bereits
            // aktualisiert wird, und sein Aufruf nicht verloren geht.
            errorMessage = L10n.feedErrorAlreadyRunning
            return
        }

        guard let feed else {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await refreshFeedContents(feed, context: context)
            await notifyFeedRefresh([result.feedNotification])
            await notifyRuleNotifications(result.ruleNotifications)
        } catch let error as LocalizedError {
            appendLog(
                kind: .error,
                message: error.errorDescription ?? L10n.feedErrorParsingFailed,
                to: feed,
                context: context
            )
            try? context.save()
            errorMessage = error.errorDescription ?? L10n.feedErrorParsingFailed
        } catch {
            appendLog(
                kind: .error,
                message: L10n.feedErrorParsingFailed,
                to: feed,
                context: context
            )
            try? context.save()
            errorMessage = L10n.feedErrorParsingFailed
        }

        isLoading = false
    }

    @MainActor
    func refreshAllFeeds(_ feeds: [Feed], context: ModelContext) async {
        guard !isLoading else {
            errorMessage = L10n.feedErrorAlreadyRunning
            return
        }

        guard !feeds.isEmpty else {
            return
        }

        isLoading = true
        errorMessage = nil
        recentRefreshStatus = nil
        refreshItems = feeds.map { feed in
            FeedRefreshItem(
                feedID: feed.id,
                feedTitle: feed.title,
                feedURL: feed.url,
                status: .pending
            )
        }
        let refreshStatusStart = ContinuousClock().now
        operationProgress = FeedOperationProgress(
            title: L10n.feedProgressRefreshAllTitle,
            completedCount: 0,
            totalCount: feeds.count
        )
        var failedFeedTitles: [String] = []
        var notificationResults: [FeedRefreshNotificationResult] = []
        var ruleNotificationResults: [RuleNotificationResult] = []

        defer {
            isLoading = false
            operationProgress = nil
        }

        // M4: Regeln einmal für den gesamten Refresh holen statt pro Feed neu
        // zu fetchen. Wird an refreshFeedContents weitergereicht.
        let refreshRules = (try? context.fetch(FetchDescriptor<Rule>())) ?? []

        // Feed-Refresh läuft bewusst gedrosselt. Bei vielen Feeds bleibt die App
        // dadurch bedienbarer und Server werden weniger hart getroffen.
        for feedBatch in feedBatches(from: feeds) {
            updateRefreshItemStatuses(
                for: feedBatch.map(\.id),
                status: .refreshing
            )

            await withTaskGroup(of: FeedRefreshOutcome.self) { group in
                for feed in feedBatch {
                    group.addTask { @MainActor in
                        do {
                            let result = try await self.refreshFeedContents(
                                feed,
                                context: context,
                                rules: refreshRules,
                                savesImmediately: false
                            )
                            self.updateRefreshItemStatus(for: feed.id, status: .succeeded)
                            return .success(result)
                        } catch let error as LocalizedError {
                            self.appendLog(
                                kind: .error,
                                message: error.errorDescription ?? L10n.feedErrorParsingFailed,
                                to: feed,
                                context: context
                            )
                            self.updateRefreshItemStatus(for: feed.id, status: .failed)
                            return .failure(feed.title)
                        } catch {
                            self.appendLog(
                                kind: .error,
                                message: L10n.feedErrorParsingFailed,
                                to: feed,
                                context: context
                            )
                            self.updateRefreshItemStatus(for: feed.id, status: .failed)
                            return .failure(feed.title)
                        }
                    }
                }

                for await outcome in group {
                    switch outcome {
                    case .success(let result):
                        notificationResults.append(result.feedNotification)
                        ruleNotificationResults.append(contentsOf: result.ruleNotifications)
                    case .failure(let failedTitle):
                        failedFeedTitles.append(failedTitle)
                    }

                    incrementOperationProgress()
                }
            }

            try? context.save()
        }

        await notifyFeedRefresh(notificationResults)
        await notifyRuleNotifications(ruleNotificationResults)
        await waitForMinimumRefreshStatusDuration(since: refreshStatusStart)

        recentRefreshStatus = FeedRefreshStatusSummary(
            newArticleCount: notificationResults.reduce(0) { $0 + $1.newArticleCount },
            failedFeedCount: failedFeedTitles.count,
            totalFeedCount: feeds.count
        )

        if failedFeedTitles.isEmpty {
            lastRefreshOutcome = .success
        } else if failedFeedTitles.count < feeds.count {
            // Teilfehler: einige Feeds konnten nicht aktualisiert werden, der
            // Rest aber schon. Status „partial" statt pauschal „failed".
            lastRefreshOutcome = .partial(failedCount: failedFeedTitles.count)
            errorMessage = L10n.feedErrorRefreshAllPartial(
                failedFeedTitles.count,
                feedTitles: failedFeedTitles.joined(separator: ", ")
            )
        } else {
            lastRefreshOutcome = .failure
            errorMessage = L10n.feedErrorRefreshAllPartial(
                failedFeedTitles.count,
                feedTitles: failedFeedTitles.joined(separator: ", ")
            )
        }
    }

    @MainActor
    func refreshAllFeeds(_ feeds: [Feed], modelContainer: ModelContainer) async {
        guard !isLoading else {
            errorMessage = L10n.feedErrorAlreadyRunning
            return
        }

        let snapshots = feeds.map { feed in
            FeedRefreshSnapshot(
                id: feed.id,
                title: feed.title,
                url: feed.url
            )
        }
        guard !snapshots.isEmpty else {
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

        let refreshService = FeedBackgroundRefreshService(
            modelContainer: modelContainer,
            fetchFeedConditionally: fetchFeedConditionally,
            discoverFaviconURL: discoverFaviconURL,
            enrichArticleImages: enrichArticleImages,
            articleRetentionDefaults: articleRetentionDefaults
        )
        let summary = await refreshService.refreshAllFeeds(
            snapshots,
            batchSize: Self.maxConcurrentFeedRefreshes
        ) { [weak self] event in
            await self?.handleBackgroundRefreshEvent(event)
        }

        await notifyFeedRefresh(summary.notificationResults)
        await notifyRuleNotifications(summary.ruleNotificationResults)
        await waitForMinimumRefreshStatusDuration(since: refreshStatusStart)

        recentRefreshStatus = FeedRefreshStatusSummary(
            newArticleCount: summary.notificationResults.reduce(0) { $0 + $1.newArticleCount },
            failedFeedCount: summary.failedFeedTitles.count,
            totalFeedCount: snapshots.count
        )

        if summary.failedFeedTitles.isEmpty {
            lastRefreshOutcome = .success
        } else if summary.failedFeedTitles.count < snapshots.count {
            lastRefreshOutcome = .partial(failedCount: summary.failedFeedTitles.count)
            errorMessage = L10n.feedErrorRefreshAllPartial(
                summary.failedFeedTitles.count,
                feedTitles: summary.failedFeedTitles.joined(separator: ", ")
            )
        } else {
            lastRefreshOutcome = .failure
            errorMessage = L10n.feedErrorRefreshAllPartial(
                summary.failedFeedTitles.count,
                feedTitles: summary.failedFeedTitles.joined(separator: ", ")
            )
        }
    }

    @MainActor
    private func handleBackgroundRefreshEvent(_ event: FeedBackgroundRefreshEvent) {
        switch event {
        case .batchStarted(let feedIDs):
            updateRefreshItemStatuses(for: feedIDs, status: .refreshing)
        case .feedSucceeded(let feedID):
            updateRefreshItemStatus(for: feedID, status: .succeeded)
            incrementOperationProgress()
        case .feedFailed(let feedID):
            updateRefreshItemStatus(for: feedID, status: .failed)
            incrementOperationProgress()
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

    // Generisches Chunking in Batches der Größe `maxConcurrentFeedRefreshes`.
    // Enthält bewusst keine Feed-spezifische Logik, sodass es neben `importOPMLFeeds`
    // und `refreshAllFeeds` auch für den OPML-Vorschau-Abruf wiederverwendet
    // werden kann (DRY — vorher war die Methode auf `[Feed]` festgelegt).
    private func feedBatches<T>(from items: [T]) -> [[T]] {
        guard !items.isEmpty else {
            return []
        }
        return stride(from: 0, to: items.count, by: Self.maxConcurrentFeedRefreshes).map { startIndex in
            Array(items[startIndex ..< min(startIndex + Self.maxConcurrentFeedRefreshes, items.count)])
        }
    }

    @MainActor
    func deleteFeed(_ feed: Feed?, context: ModelContext) {
        guard let feed else {
            return
        }

        errorMessage = nil
        do {
            let feedID = feed.id
            let descriptor = FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.feedID == feedID
                }
            )
            let articles = try context.fetch(descriptor)

            for article in articles {
                context.delete(article)
            }

            // .nullify statt .cascade (CloudKit-kompatibel): LogEntries manuell
            // löschen, sonst verwaisten sie nach dem Feed-Löschen.
            for entry in feed.logEntries ?? [] {
                context.delete(entry)
            }

            context.delete(feed)

            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func articleIdentityKeys(_ article: Article) -> [String] {
        var keys: [String] = []

        if let sourceID = cleanedIdentityValue(article.sourceID) {
            keys.append("source:\(sourceID)")
        }

        if let link = cleanedIdentityValue(article.link) {
            keys.append("link:\(link)")
        }

        if let titleDateKey = titleDateIdentityKey(title: article.title, publishedAt: article.publishedAt) {
            keys.append(titleDateKey)
        }

        return keys.isEmpty ? ["title:\(article.title)"] : keys
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

    private func articleIdentityKeys(for parsedArticle: ParsedArticle) -> [String] {
        var keys: [String] = []

        if let sourceID = cleanedIdentityValue(parsedArticle.sourceID) {
            keys.append("source:\(sourceID)")
        }

        if let link = cleanedIdentityValue(parsedArticle.link) {
            keys.append("link:\(link)")
        }

        if let titleDateKey = titleDateIdentityKey(title: parsedArticle.title, publishedAt: parsedArticle.publishedAt) {
            keys.append(titleDateKey)
        }

        return keys.isEmpty ? ["title:\(parsedArticle.title)"] : keys
    }

    private func primaryArticleIdentity(for parsedArticle: ParsedArticle) -> String {
        articleIdentityKeys(for: parsedArticle)[0]
    }

    private func cleanedIdentityValue(_ value: String?) -> String? {
        let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cleaned, !cleaned.isEmpty else {
            return nil
        }

        return cleaned
    }

    private func titleDateIdentityKey(title: String, publishedAt: Date?) -> String? {
        guard let publishedAt else {
            return nil
        }

        return "title-date:\(title)|\(publishedAt.timeIntervalSince1970)"
    }

    @MainActor
    private func refreshFeedContents(
        _ feed: Feed,
        context: ModelContext,
        rules providedRules: [Rule]? = nil,
        savesImmediately: Bool = true
    ) async throws -> FeedRefreshResult {
        let refreshDate = Date()
        let fetchResult = try await fetchFeedConditionally(feed.url, feed.httpValidators)
        let parsedFeed: ParsedFeed
        switch fetchResult {
        case .updated(let updatedFeed, let validators):
            feed.applyHTTPValidators(validators)
            parsedFeed = updatedFeed
        case .notModified(let validators):
            feed.applyHTTPValidators(validators)
            feed.lastRefreshed = refreshDate
            appendLog(
                kind: .info,
                message: L10n.feedLogRefreshed(newArticleCount: 0),
                to: feed,
                context: context
            )
            if savesImmediately {
                try context.save()
            }

            return FeedRefreshResult(
                feedNotification: FeedRefreshNotificationResult(
                    feedTitle: feed.title,
                    newArticleCount: 0,
                    isNotificationEnabled: feed.isNotificationEnabled
                ),
                ruleNotifications: []
            )
        }
        let existingArticlesByIdentity = try existingArticlesByIdentity(for: feed, context: context)
        updateMissingArticleImages(
            in: existingArticlesByIdentity,
            from: parsedFeed.articles
        )
        let existingArticlesNeedingPageImages = parsedFeed.articles.filter { parsedArticle in
            guard
                parsedArticleNeedsPageImage(parsedArticle),
                let existingArticle = existingArticle(in: existingArticlesByIdentity, for: parsedArticle)
            else {
                return false
            }

            return isMissingImage(existingArticle.imageURL)
        }
        let enrichedExistingArticles = await enrichArticleImagesIfNeeded(existingArticlesNeedingPageImages)
        updateMissingArticleImages(
            in: existingArticlesByIdentity,
            from: enrichedExistingArticles
        )
        updateStoredArticleContent(
            in: existingArticlesByIdentity,
            from: parsedFeed.articles
        )

        var seenArticleKeys = Set(existingArticlesByIdentity.keys)
        let newArticles = parsedFeed.articles.filter { parsedArticle in
            let articleKeys = articleIdentityKeys(for: parsedArticle)
            let isKnownArticle = articleKeys.contains { seenArticleKeys.contains($0) }
            seenArticleKeys.formUnion(articleKeys)
            guard !isKnownArticle else {
                return false
            }

            return ArticleRetentionSettings.canImportParsedArticle(
                parsedArticle,
                for: feed,
                defaults: articleRetentionDefaults,
                now: refreshDate
            )
        }
        let enrichedNewArticlesByIdentity = await enrichedArticlesByIdentity(
            for: newArticles.filter(parsedArticleNeedsPageImage)
        )
        // M4: Regeln werden in refreshAllFeeds einmal geholt und weitergereicht
        // (providedRules != nil) statt pro Feed neu zu fetchen. Der Einzel-Feed-
        // Pfad (refreshFeed) übergibt nil und holt selbst — so bleibt das
        // Verhalten für einen einzelnen Feed unverändert.
        let rules: [Rule]
        if newArticles.isEmpty {
            rules = []
        } else if let providedRules {
            rules = providedRules
        } else {
            rules = try context.fetch(FetchDescriptor<Rule>())
        }
        var ruleNotifications: [RuleNotificationResult] = []

        let previousOriginalTitle = feed.originalTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleWasCustom = previousOriginalTitle.map { !$0.isEmpty && feed.title != $0 } ?? false
        feed.originalTitle = parsedFeed.title
        if !titleWasCustom {
            feed.title = parsedFeed.title
        }
        feed.feedDescription = parsedFeed.description
        let previousSiteURL = feed.siteURL
        feed.siteURL = parsedFeed.siteURL
        // M5: Favicon nur neu ermitteln, wenn noch keines vorhanden ist oder
        // sich die siteURL geändert hat — sonst war jeder Refresh ein
        // Favicon-Discovery-Roundtrip (HTML-Laden + Parsen) trotz stabiler
        // Website.
        let needsFaviconDiscovery = (feed.faviconURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || previousSiteURL != feed.siteURL
        if needsFaviconDiscovery, let faviconURL = await faviconURL(for: parsedFeed) {
            feed.faviconURL = faviconURL
        }
        feed.lastRefreshed = refreshDate

        // Neue Artikel erst vollständig erzeugen, dann Regeln im Batch anwenden:
        // `preparedRules` wird dadurch nur einmal pro Feed berechnet statt pro
        // Artikel (Sortierung + normalisierte Conditions).
        var newArticleObjects: [Article] = []
        for parsedArticle in newArticles {
            let articleToInsert = enrichedNewArticlesByIdentity[primaryArticleIdentity(for: parsedArticle)] ?? parsedArticle
            let article = Article(
                title: articleToInsert.title,
                link: articleToInsert.link,
                summary: articleToInsert.summary,
                content: articleToInsert.content,
                publishedAt: articleToInsert.publishedAt,
                imageURL: articleToInsert.imageURL,
                sourceID: articleToInsert.sourceID,
                feed: feed
            )
            context.insert(article)
            newArticleObjects.append(article)
        }
        let ruleResult = RuleEngine.applyRulesWithNotifications(rules, to: newArticleObjects, feed: feed)
        ruleNotifications.append(contentsOf: ruleResult.notifications)
        // Nur nicht-versteckte neue Artikel erhöhen den Ungelesen-Zähler —
        // versteckte (z.B. per Regel ausgeblendete) werden in der Liste nicht
        // angezeigt und würden sonst ein Badge ohne sichtbare Artikel erzeugen.
        // Konsistent zum addFeed-Pfad (Z. 400) über die geteilte static
        // `unreadIncrement(for:)` — verhindert Drift, sobald je ein neuer
        // Artikel mit isRead=true importiert oder gelesen markiert wird.
        feed.unreadCount += Self.unreadIncrement(for: newArticleObjects)

        appendLog(
            kind: .info,
            message: L10n.feedLogRefreshed(newArticleCount: newArticles.count),
            to: feed,
            context: context
        )
        if savesImmediately {
            try context.save()
        }

        return FeedRefreshResult(
            feedNotification: FeedRefreshNotificationResult(
                feedTitle: feed.title,
                newArticleCount: newArticles.count,
                isNotificationEnabled: feed.isNotificationEnabled
            ),
            ruleNotifications: ruleNotifications
        )
    }

    /// Anzahl neuer Artikel, die den Ungelesen-Zähler erhöhen: nur nicht
    /// gelesene UND nicht versteckte. Konsistent zum addFeed-Pfad
    /// (Z. 400) — verhindert Drift, sobald jemals Artikel mit isRead=true
    /// importiert oder per Regel gelesen markiert werden.
    static func unreadIncrement(for articles: [Article]) -> Int {
        articles.filter { !$0.isRead && !$0.isHidden }.count
    }

    private func existingArticlesByIdentity(for feed: Feed, context: ModelContext) throws -> [String: Article] {
        let feedID = Optional(feed.id)
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.feedID == feedID
            }
        )
        descriptor.propertiesToFetch = Article.refreshLookupPropertiesToFetch
        let articles = try context.fetch(descriptor)
        var articlesByIdentity: [String: Article] = [:]
        for article in articles {
            for identityKey in articleIdentityKeys(article) where articlesByIdentity[identityKey] == nil {
                articlesByIdentity[identityKey] = article
            }
        }

        return articlesByIdentity
    }

    private func existingArticle(in existingArticlesByIdentity: [String: Article], for parsedArticle: ParsedArticle) -> Article? {
        for identityKey in articleIdentityKeys(for: parsedArticle) {
            if let article = existingArticlesByIdentity[identityKey] {
                return article
            }
        }

        return nil
    }

    private func updateMissingArticleImages(in existingArticlesByIdentity: [String: Article], from parsedArticles: [ParsedArticle]) {
        for parsedArticle in parsedArticles {
            guard let imageURL = parsedArticle.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !imageURL.isEmpty,
                  let existingArticle = existingArticle(in: existingArticlesByIdentity, for: parsedArticle),
                  existingArticle.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            else {
                continue
            }

            existingArticle.imageURL = imageURL
        }
    }

    private func updateStoredArticleContent(in existingArticlesByIdentity: [String: Article], from parsedArticles: [ParsedArticle]) {
        for parsedArticle in parsedArticles {
            guard let existingArticle = existingArticle(in: existingArticlesByIdentity, for: parsedArticle) else {
                continue
            }

            if let sourceID = StoredArticleRefreshFieldUpdate.missingReplacement(
                for: existingArticle.sourceID,
                from: parsedArticle.sourceID
            ) {
                existingArticle.sourceID = sourceID
            }

            if let link = StoredArticleRefreshFieldUpdate.missingReplacement(
                for: existingArticle.link,
                from: parsedArticle.link
            ) {
                existingArticle.link = link
            }

            if let summary = StoredArticleRefreshFieldUpdate.replacement(
                for: existingArticle.summary,
                from: parsedArticle.summary
            ) {
                existingArticle.summary = summary
            }

            if let content = StoredArticleRefreshFieldUpdate.missingReplacement(
                for: existingArticle.content,
                from: parsedArticle.content
            ) {
                existingArticle.content = content
            }
        }
    }

    private func enrichedArticlesByIdentity(for articles: [ParsedArticle]) async -> [String: ParsedArticle] {
        let enrichedArticles = await enrichArticleImagesIfNeeded(articles)
        return Dictionary(
            enrichedArticles.map { (primaryArticleIdentity(for: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func enrichArticleImagesIfNeeded(_ articles: [ParsedArticle]) async -> [ParsedArticle] {
        guard !articles.isEmpty else {
            return []
        }

        return await enrichArticleImages(articles)
    }

    private func parsedArticleNeedsPageImage(_ article: ParsedArticle) -> Bool {
        isMissingImage(article.imageURL)
    }

    private func isMissingImage(_ imageURL: String?) -> Bool {
        imageURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    @MainActor
    private func appendLog(
        kind: FeedLogEntryKind,
        message: String,
        to feed: Feed,
        context: ModelContext
    ) {
        let entry = FeedLogEntry(kind: kind, message: message, feed: feed)
        context.insert(entry)
        var logEntries = feed.logEntries ?? []
        logEntries.append(entry)
        feed.logEntries = logEntries
        pruneLogEntries(for: feed, context: context)
    }

    @MainActor
    private func pruneLogEntries(for feed: Feed, context: ModelContext) {
        let entriesToDelete = (feed.logEntries ?? [])
            .sorted { $0.createdAt > $1.createdAt }
            .dropFirst(20)

        for entry in entriesToDelete {
            context.delete(entry)
        }
    }

    private func faviconURL(for parsedFeed: ParsedFeed) async -> String? {
        let parsedSiteURL = parsedFeed.siteURL
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap(URL.init(string:))
        guard let siteURL = parsedSiteURL ?? FaviconService.siteURL(from: parsedFeed.sourceURL) else {
            return nil
        }

        return await discoverFaviconURL(siteURL)
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
