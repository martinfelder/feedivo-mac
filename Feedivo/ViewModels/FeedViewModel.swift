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

@Observable
final class FeedViewModel {
    static let maxConcurrentFeedRefreshes = 6

    private let fetchFeed: (String) async throws -> ParsedFeed
    private let discoverFaviconURL: (URL) async -> String?
    private let enrichArticleImages: ([ParsedArticle]) async -> [ParsedArticle]
    private let notifyFeedRefresh: ([FeedRefreshNotificationResult]) async -> Void
    private let notifyRuleNotifications: ([RuleNotificationResult]) async -> Void
    private let articleRetentionDefaults: UserDefaults

    var isLoading = false
    var errorMessage: String?
    var operationProgress: FeedOperationProgress?

    init(
        fetchFeed: @escaping (String) async throws -> ParsedFeed = FeedService.fetchFeed,
        discoverFaviconURL: @escaping (URL) async -> String? = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        },
        enrichArticleImages: @escaping ([ParsedArticle]) async -> [ParsedArticle] = { articles in
            await FeedService.enrichArticleImagesIfNeeded(in: articles)
        },
        notifyFeedRefresh: @escaping ([FeedRefreshNotificationResult]) async -> Void = { results in
            await FeedNotificationService.presentRefreshSummary(for: results)
        },
        notifyRuleNotifications: @escaping ([RuleNotificationResult]) async -> Void = { results in
            await FeedNotificationService.presentRuleSummary(for: results)
        },
        articleRetentionDefaults: UserDefaults = .standard
    ) {
        self.fetchFeed = fetchFeed
        self.discoverFaviconURL = discoverFaviconURL
        self.enrichArticleImages = enrichArticleImages
        self.notifyFeedRefresh = notifyFeedRefresh
        self.notifyRuleNotifications = notifyRuleNotifications
        self.articleRetentionDefaults = articleRetentionDefaults
    }

    @MainActor
    func opmlImportPreviewRows(
        for opmlFeeds: [OPMLFeed],
        existingFeeds: [Feed],
        onProgress: ((OPMLImportPreviewProgress) -> Void)? = nil
    ) async -> [OPMLImportPreviewRow] {
        var knownFeedURLs = Set(existingFeeds.map { normalizedFeedURL($0.url) })
        var rows: [OPMLImportPreviewRow] = []

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
                rows.append(
                    OPMLImportPreviewRow(
                        feed: opmlFeed,
                        status: .duplicate,
                        isSelected: false
                    )
                )
                continue
            }

            do {
                _ = try await fetchFeed(cleanedURL)
                rows.append(
                    OPMLImportPreviewRow(
                        feed: opmlFeed,
                        status: .available,
                        isSelected: true
                    )
                )
            } catch {
                rows.append(
                    OPMLImportPreviewRow(
                        feed: opmlFeed,
                        status: .unreachable,
                        isSelected: false
                    )
                )
            }
        }

        return rows
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
                kind: "info",
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
                                    kind: "error",
                                    message: error.errorDescription ?? L10n.feedErrorParsingFailed,
                                    to: feed,
                                    context: context
                                )
                                try? context.save()
                                return feed.title
                            } catch {
                                self.appendLog(
                                    kind: "error",
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

    func opmlFeedsForExport(from feeds: [Feed]) -> [OPMLFeed] {
        feeds.map { feed in
            OPMLFeed(
                title: feed.title,
                xmlURL: feed.url,
                htmlURL: feed.siteURL,
                folderName: feed.folderName
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

        isLoading = true
        errorMessage = nil

        do {
            let parsedFeed = try await fetchFeed(cleanedURL)
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
            feed.unreadCount = feed.articles.filter { !$0.isRead }.count

            context.insert(feed)
            appendLog(
                kind: "info",
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
                kind: "error",
                message: error.errorDescription ?? L10n.feedErrorParsingFailed,
                to: feed,
                context: context
            )
            try? context.save()
            errorMessage = error.errorDescription ?? L10n.feedErrorParsingFailed
        } catch {
            appendLog(
                kind: "error",
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
        guard !feeds.isEmpty else {
            return
        }

        isLoading = true
        errorMessage = nil
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

        // Feed-Refresh läuft bewusst gedrosselt. Bei vielen Feeds bleibt die App
        // dadurch bedienbarer und Server werden weniger hart getroffen.
        for feedBatch in feedBatches(from: feeds) {
            await withTaskGroup(of: FeedRefreshOutcome.self) { group in
                for feed in feedBatch {
                    group.addTask { @MainActor in
                        do {
                            let result = try await self.refreshFeedContents(feed, context: context)
                            return .success(result)
                        } catch let error as LocalizedError {
                            self.appendLog(
                                kind: "error",
                                message: error.errorDescription ?? L10n.feedErrorParsingFailed,
                                to: feed,
                                context: context
                            )
                            try? context.save()
                            return .failure(feed.title)
                        } catch {
                            self.appendLog(
                                kind: "error",
                                message: L10n.feedErrorParsingFailed,
                                to: feed,
                                context: context
                            )
                            try? context.save()
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
        }

        await notifyFeedRefresh(notificationResults)
        await notifyRuleNotifications(ruleNotificationResults)

        if !failedFeedTitles.isEmpty {
            errorMessage = L10n.feedErrorRefreshAllPartial(
                failedFeedTitles.count,
                feedTitles: failedFeedTitles.joined(separator: ", ")
            )
        }
    }

    private func feedBatches(from feeds: [Feed]) -> [[Feed]] {
        stride(from: 0, to: feeds.count, by: Self.maxConcurrentFeedRefreshes).map { startIndex in
            Array(feeds[startIndex ..< min(startIndex + Self.maxConcurrentFeedRefreshes, feeds.count)])
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
    private func refreshFeedContents(_ feed: Feed, context: ModelContext) async throws -> FeedRefreshResult {
        let refreshDate = Date()
        let parsedFeed = try await fetchFeed(feed.url)
        let existingArticlesByIdentity = existingArticlesByIdentity(in: feed)
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
        let rules = newArticles.isEmpty
            ? []
            : try context.fetch(FetchDescriptor<Rule>())
        var ruleNotifications: [RuleNotificationResult] = []

        let previousOriginalTitle = feed.originalTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleWasCustom = previousOriginalTitle.map { !$0.isEmpty && feed.title != $0 } ?? false
        feed.originalTitle = parsedFeed.title
        if !titleWasCustom {
            feed.title = parsedFeed.title
        }
        feed.feedDescription = parsedFeed.description
        feed.siteURL = parsedFeed.siteURL
        if let faviconURL = await faviconURL(for: parsedFeed) {
            feed.faviconURL = faviconURL
        }
        feed.lastRefreshed = refreshDate

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
            let ruleResult = RuleEngine.applyRulesWithNotifications(rules, to: article, feed: feed)
            ruleNotifications.append(contentsOf: ruleResult.notifications)
            feed.articles.append(article)
        }
        feed.unreadCount += newArticles.count

        appendLog(
            kind: "info",
            message: L10n.feedLogRefreshed(newArticleCount: newArticles.count),
            to: feed,
            context: context
        )
        try context.save()

        return FeedRefreshResult(
            feedNotification: FeedRefreshNotificationResult(
                feedTitle: feed.title,
                newArticleCount: newArticles.count,
                isNotificationEnabled: feed.isNotificationEnabled
            ),
            ruleNotifications: ruleNotifications
        )
    }

    private func existingArticlesByIdentity(in feed: Feed) -> [String: Article] {
        var articlesByIdentity: [String: Article] = [:]
        for article in feed.articles {
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

            if isMissingText(existingArticle.sourceID),
               let sourceID = nonEmptyText(parsedArticle.sourceID) {
                existingArticle.sourceID = sourceID
            }

            if isMissingText(existingArticle.link),
               let link = nonEmptyText(parsedArticle.link) {
                existingArticle.link = link
            }

            if let summary = nonEmptyText(parsedArticle.summary) {
                existingArticle.summary = summary
            }

            if isMissingText(existingArticle.content),
               let content = nonEmptyText(parsedArticle.content) {
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

    private func isMissingText(_ text: String?) -> Bool {
        text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    private func nonEmptyText(_ text: String?) -> String? {
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedText, !trimmedText.isEmpty else {
            return nil
        }

        return text
    }

    @MainActor
    private func appendLog(
        kind: String,
        message: String,
        to feed: Feed,
        context: ModelContext
    ) {
        let entry = FeedLogEntry(kind: kind, message: message, feed: feed)
        context.insert(entry)
        feed.logEntries.append(entry)
        pruneLogEntries(for: feed, context: context)
    }

    @MainActor
    private func pruneLogEntries(for feed: Feed, context: ModelContext) {
        let entriesToDelete = feed.logEntries
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
