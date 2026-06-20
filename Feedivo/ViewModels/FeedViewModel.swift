import Foundation
import Observation
import SwiftData

@Observable
final class FeedViewModel {
    private let fetchFeed: (String) async throws -> ParsedFeed
    private let discoverFaviconURL: (URL) async -> String?

    var isLoading = false
    var errorMessage: String?

    init(
        fetchFeed: @escaping (String) async throws -> ParsedFeed = FeedService.fetchFeed,
        discoverFaviconURL: @escaping (URL) async -> String? = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        }
    ) {
        self.fetchFeed = fetchFeed
        self.discoverFaviconURL = discoverFaviconURL
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
            let feed = Feed(
                url: parsedFeed.sourceURL,
                title: parsedFeed.title,
                feedDescription: parsedFeed.description,
                faviconURL: await faviconURL(for: parsedFeed),
                siteURL: parsedFeed.siteURL,
                followedAt: Date(),
                lastRefreshed: Date()
            )

            feed.articles = parsedFeed.articles.map { parsedArticle in
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

        for feed in feeds {
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
                failedFeedTitles.append(feed.title)
            } catch {
                appendLog(
                    kind: "error",
                    message: L10n.feedErrorParsingFailed,
                    to: feed,
                    context: context
                )
                try? context.save()
                failedFeedTitles.append(feed.title)
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
        var seenArticleKeys = Set(feed.articles.map(articleIdentity))
        let newArticles = parsedFeed.articles.filter { parsedArticle in
            seenArticleKeys.insert(articleIdentity(for: parsedArticle)).inserted
        }

        feed.title = parsedFeed.title
        feed.feedDescription = parsedFeed.description
        feed.siteURL = parsedFeed.siteURL
        if let faviconURL = await faviconURL(for: parsedFeed) {
            feed.faviconURL = faviconURL
        }
        feed.lastRefreshed = Date()

        for parsedArticle in newArticles {
            feed.articles.append(
                Article(
                    title: parsedArticle.title,
                    link: parsedArticle.link,
                    summary: parsedArticle.summary,
                    content: parsedArticle.content,
                    publishedAt: parsedArticle.publishedAt,
                    imageURL: parsedArticle.imageURL,
                    feed: feed
                )
            )
        }

        appendLog(
            kind: "info",
            message: L10n.feedLogRefreshed(newArticleCount: newArticles.count),
            to: feed,
            context: context
        )
        try context.save()
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
