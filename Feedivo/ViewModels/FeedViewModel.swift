import Foundation
import Observation
import SwiftData

@Observable
final class FeedViewModel {
    private let fetchFeed: (String) async throws -> ParsedFeed
    private let discoverFaviconURL: (URL) async -> String?
    private let enrichArticleImages: ([ParsedArticle]) async -> [ParsedArticle]

    var isLoading = false
    var errorMessage: String?

    init(
        fetchFeed: @escaping (String) async throws -> ParsedFeed = FeedService.fetchFeed,
        discoverFaviconURL: @escaping (URL) async -> String? = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        },
        enrichArticleImages: @escaping ([ParsedArticle]) async -> [ParsedArticle] = { articles in
            await FeedService.enrichArticleImagesIfNeeded(in: articles)
        }
    ) {
        self.fetchFeed = fetchFeed
        self.discoverFaviconURL = discoverFaviconURL
        self.enrichArticleImages = enrichArticleImages
    }

    @MainActor
    func importOPMLFeeds(
        _ opmlFeeds: [OPMLFeed],
        existingFeeds: [Feed],
        context: ModelContext
    ) async throws -> OPMLImportResult {
        errorMessage = nil
        isLoading = true
        defer {
            isLoading = false
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
            guard knownFeedURLs.insert(normalizedURL).inserted else {
                skippedDuplicateCount += 1
                continue
            }

            let feed = Feed(
                url: cleanedURL,
                title: opmlFeed.title.trimmingCharacters(in: .whitespacesAndNewlines),
                siteURL: opmlFeed.htmlURL,
                followedAt: Date(),
                folderName: opmlFeed.folderName
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

        // Phase 2: Alle neuen Feeds parallel abrufen (Netzwerk-I/O läuft gleichzeitig)
        await withTaskGroup(of: String?.self) { group in
            for feed in feedsToRefresh {
                group.addTask { @MainActor in
                    do {
                        try await self.refreshFeedContents(feed, context: context)
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
            try await refreshFeedContents(feed, context: context)
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
        var failedFeedTitles: [String] = []

        // Alle Feeds parallel aktualisieren. Jede Task läuft auf dem Main Actor,
        // gibt ihn aber während await-Aufrufen (Netzwerk) frei — so laufen alle
        // Netzwerkabrufe gleichzeitig, ohne SwiftData-Zugriffe zu verparallelisieren.
        await withTaskGroup(of: String?.self) { group in
            for feed in feeds {
                group.addTask { @MainActor in
                    do {
                        try await self.refreshFeedContents(feed, context: context)
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
            }
        }

        if !failedFeedTitles.isEmpty {
            errorMessage = L10n.feedErrorRefreshAllPartial(
                failedFeedTitles.count,
                feedTitles: failedFeedTitles.joined(separator: ", ")
            )
        }

        isLoading = false
    }

    @MainActor
    func deleteFeed(_ feed: Feed?, context: ModelContext) {
        guard let feed else {
            return
        }

        errorMessage = nil
        context.delete(feed)

        do {
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func articleIdentity(_ article: Article) -> String {
        if let link = article.link?.trimmingCharacters(in: .whitespacesAndNewlines),
           !link.isEmpty {
            return "link:\(link)"
        }

        return "title-date:\(article.title)|\(article.publishedAt?.timeIntervalSince1970 ?? 0)"
    }

    private func normalizedFeedURL(_ urlString: String) -> String {
        urlString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func articleIdentity(for parsedArticle: ParsedArticle) -> String {
        if let link = parsedArticle.link?.trimmingCharacters(in: .whitespacesAndNewlines),
           !link.isEmpty {
            return "link:\(link)"
        }

        return "title-date:\(parsedArticle.title)|\(parsedArticle.publishedAt?.timeIntervalSince1970 ?? 0)"
    }

    @MainActor
    private func refreshFeedContents(_ feed: Feed, context: ModelContext) async throws {
        let parsedFeed = try await fetchFeed(feed.url)
        let existingArticlesByIdentity = existingArticlesByIdentity(in: feed)
        updateMissingArticleImages(
            in: existingArticlesByIdentity,
            from: parsedFeed.articles
        )
        let existingArticlesNeedingPageImages = parsedFeed.articles.filter { parsedArticle in
            guard
                parsedArticleNeedsPageImage(parsedArticle),
                let existingArticle = existingArticlesByIdentity[articleIdentity(for: parsedArticle)]
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

        var seenArticleKeys = Set(existingArticlesByIdentity.keys)
        let newArticles = parsedFeed.articles.filter { parsedArticle in
            seenArticleKeys.insert(articleIdentity(for: parsedArticle)).inserted
        }
        let enrichedNewArticlesByIdentity = await enrichedArticlesByIdentity(
            for: newArticles.filter(parsedArticleNeedsPageImage)
        )

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
        feed.lastRefreshed = Date()

        for parsedArticle in newArticles {
            let articleToInsert = enrichedNewArticlesByIdentity[articleIdentity(for: parsedArticle)] ?? parsedArticle
            feed.articles.append(
                Article(
                    title: articleToInsert.title,
                    link: articleToInsert.link,
                    summary: articleToInsert.summary,
                    content: articleToInsert.content,
                    publishedAt: articleToInsert.publishedAt,
                    imageURL: articleToInsert.imageURL,
                    feed: feed
                )
            )
        }
        feed.unreadCount += newArticles.count

        appendLog(
            kind: "info",
            message: L10n.feedLogRefreshed(newArticleCount: newArticles.count),
            to: feed,
            context: context
        )
        try context.save()
    }

    private func existingArticlesByIdentity(in feed: Feed) -> [String: Article] {
        var articlesByIdentity: [String: Article] = [:]
        for article in feed.articles {
            articlesByIdentity[articleIdentity(article)] = article
        }

        return articlesByIdentity
    }

    private func updateMissingArticleImages(in existingArticlesByIdentity: [String: Article], from parsedArticles: [ParsedArticle]) {
        for parsedArticle in parsedArticles {
            guard let imageURL = parsedArticle.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !imageURL.isEmpty,
                  let existingArticle = existingArticlesByIdentity[articleIdentity(for: parsedArticle)],
                  existingArticle.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            else {
                continue
            }

            existingArticle.imageURL = imageURL
        }
    }

    private func enrichedArticlesByIdentity(for articles: [ParsedArticle]) async -> [String: ParsedArticle] {
        let enrichedArticles = await enrichArticleImagesIfNeeded(articles)
        return Dictionary(uniqueKeysWithValues: enrichedArticles.map { (articleIdentity(for: $0), $0) })
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
