import Foundation
import SwiftData

struct FeedRefreshSnapshot: Sendable {
    var id: UUID
    var title: String
    var url: String
}

enum FeedBackgroundRefreshEvent: Sendable {
    case batchStarted([UUID])
    case feedSucceeded(UUID)
    case feedFailed(UUID)
}

struct FeedBackgroundRefreshSummary: Sendable {
    var notificationResults: [FeedRefreshNotificationResult]
    var ruleNotificationResults: [RuleNotificationResult]
    var failedFeedTitles: [String]
}

private struct FeedBackgroundRefreshResult: Sendable {
    var feedNotification: FeedRefreshNotificationResult
    var ruleNotifications: [RuleNotificationResult]
}

private enum FeedBackgroundRefreshOutcome: Sendable {
    case success(UUID, FeedBackgroundRefreshResult)
    case failure(UUID, String)
}

struct FeedBackgroundRefreshService {
    private let modelContainer: ModelContainer
    private let fetchFeedConditionally: @Sendable (String, FeedHTTPValidators) async throws -> ConditionalFeedFetchResult
    private let discoverFaviconURL: @Sendable (URL) async -> String?
    private let enrichArticleImages: @Sendable ([ParsedArticle]) async -> [ParsedArticle]
    private let articleRetentionDefaults: UserDefaults

    init(
        modelContainer: ModelContainer,
        fetchFeedConditionally: @escaping @Sendable (String, FeedHTTPValidators) async throws -> ConditionalFeedFetchResult = FeedService.fetchFeedConditionally,
        discoverFaviconURL: @escaping @Sendable (URL) async -> String? = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        },
        enrichArticleImages: @escaping @Sendable ([ParsedArticle]) async -> [ParsedArticle] = { articles in
            await FeedService.enrichArticleImagesIfNeeded(in: articles)
        },
        articleRetentionDefaults: UserDefaults = .standard
    ) {
        self.modelContainer = modelContainer
        self.fetchFeedConditionally = fetchFeedConditionally
        self.discoverFaviconURL = discoverFaviconURL
        self.enrichArticleImages = enrichArticleImages
        self.articleRetentionDefaults = articleRetentionDefaults
    }

    func refreshAllFeeds(
        _ snapshots: [FeedRefreshSnapshot],
        batchSize: Int,
        onEvent: @escaping @Sendable (FeedBackgroundRefreshEvent) async -> Void
    ) async -> FeedBackgroundRefreshSummary {
        var notificationResults: [FeedRefreshNotificationResult] = []
        var ruleNotificationResults: [RuleNotificationResult] = []
        var failedFeedTitles: [String] = []

        for batch in batches(from: snapshots, batchSize: batchSize) {
            await onEvent(.batchStarted(batch.map(\.id)))

            await withTaskGroup(of: FeedBackgroundRefreshOutcome.self) { group in
                for snapshot in batch {
                    group.addTask {
                        await refreshFeed(snapshot)
                    }
                }

                for await outcome in group {
                    switch outcome {
                    case .success(let feedID, let result):
                        notificationResults.append(result.feedNotification)
                        ruleNotificationResults.append(contentsOf: result.ruleNotifications)
                        await onEvent(.feedSucceeded(feedID))
                    case .failure(let feedID, let failedTitle):
                        failedFeedTitles.append(failedTitle)
                        await onEvent(.feedFailed(feedID))
                    }
                }
            }
        }

        return FeedBackgroundRefreshSummary(
            notificationResults: notificationResults,
            ruleNotificationResults: ruleNotificationResults,
            failedFeedTitles: failedFeedTitles
        )
    }

    private func refreshFeed(_ snapshot: FeedRefreshSnapshot) async -> FeedBackgroundRefreshOutcome {
        let context = ModelContext(modelContainer)
        do {
            let feed = try fetchFeed(withID: snapshot.id, context: context)
            let result = try await refreshFeedContents(feed, context: context)
            return .success(snapshot.id, result)
        } catch let error as LocalizedError {
            appendFailureLog(
                message: error.errorDescription ?? L10n.feedErrorParsingFailed,
                feedID: snapshot.id,
                context: context
            )
            return .failure(snapshot.id, snapshot.title)
        } catch {
            appendFailureLog(
                message: L10n.feedErrorParsingFailed,
                feedID: snapshot.id,
                context: context
            )
            return .failure(snapshot.id, snapshot.title)
        }
    }

    private func refreshFeedContents(_ feed: Feed, context: ModelContext) async throws -> FeedBackgroundRefreshResult {
        let refreshDate = Date()
        let fetchResult = try await fetchFeedConditionally(feed.url, feed.httpValidators)
        let parsedFeed: ParsedFeed
        switch fetchResult {
        case .updated(let updatedFeed, let validators):
            feed.applyHTTPValidators(validators)
            parsedFeed = updatedFeed
        case .notModified(let validators):
            let validatorsChanged = feed.applyHTTPValidatorsIfChanged(validators)
            if validatorsChanged {
                feed.lastRefreshed = refreshDate
                try context.save()
            }

            return FeedBackgroundRefreshResult(
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
        let rules = newArticles.isEmpty ? [] : try context.fetch(FetchDescriptor<Rule>())

        let previousOriginalTitle = feed.originalTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleWasCustom = previousOriginalTitle.map { !$0.isEmpty && feed.title != $0 } ?? false
        feed.originalTitle = parsedFeed.title
        if !titleWasCustom {
            feed.title = parsedFeed.title
        }
        feed.feedDescription = parsedFeed.description
        let previousSiteURL = feed.siteURL
        feed.siteURL = parsedFeed.siteURL
        let needsFaviconDiscovery = (feed.faviconURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || previousSiteURL != feed.siteURL
        if needsFaviconDiscovery, let faviconURL = await faviconURL(for: parsedFeed) {
            feed.faviconURL = faviconURL
        }
        feed.lastRefreshed = refreshDate

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
        feed.unreadCount += Self.unreadIncrement(for: newArticleObjects)

        appendLog(
            kind: .info,
            message: L10n.feedLogRefreshed(newArticleCount: newArticles.count),
            to: feed,
            context: context
        )
        try context.save()

        return FeedBackgroundRefreshResult(
            feedNotification: FeedRefreshNotificationResult(
                feedTitle: feed.title,
                newArticleCount: newArticles.count,
                isNotificationEnabled: feed.isNotificationEnabled
            ),
            ruleNotifications: ruleResult.notifications
        )
    }

    private func fetchFeed(withID feedID: UUID, context: ModelContext) throws -> Feed {
        var descriptor = FetchDescriptor<Feed>(
            predicate: #Predicate<Feed> { feed in
                feed.id == feedID
            }
        )
        descriptor.fetchLimit = 1
        if let feed = try context.fetch(descriptor).first {
            return feed
        }

        throw FeedBackgroundRefreshError.feedMissing
    }

    private func appendFailureLog(message: String, feedID: UUID, context: ModelContext) {
        guard let feed = try? fetchFeed(withID: feedID, context: context) else {
            return
        }

        appendLog(kind: .error, message: message, to: feed, context: context)
        try? context.save()
    }

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

    private func pruneLogEntries(for feed: Feed, context: ModelContext) {
        let entriesToDelete = (feed.logEntries ?? [])
            .sorted { $0.createdAt > $1.createdAt }
            .dropFirst(20)

        for entry in entriesToDelete {
            context.delete(entry)
        }
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

    private func faviconURL(for parsedFeed: ParsedFeed) async -> String? {
        let parsedSiteURL = parsedFeed.siteURL
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap(URL.init(string:))
        guard let siteURL = parsedSiteURL ?? FaviconService.siteURL(from: parsedFeed.sourceURL) else {
            return nil
        }

        return await discoverFaviconURL(siteURL)
    }

    private func batches<T>(from items: [T], batchSize: Int) -> [[T]] {
        guard !items.isEmpty else {
            return []
        }

        let safeBatchSize = max(1, batchSize)
        return stride(from: 0, to: items.count, by: safeBatchSize).map { startIndex in
            Array(items[startIndex ..< min(startIndex + safeBatchSize, items.count)])
        }
    }

    private static func unreadIncrement(for articles: [Article]) -> Int {
        articles.filter { !$0.isRead && !$0.isHidden }.count
    }
}

private enum FeedBackgroundRefreshError: LocalizedError {
    case feedMissing

    var errorDescription: String? {
        L10n.feedErrorParsingFailed
    }
}
