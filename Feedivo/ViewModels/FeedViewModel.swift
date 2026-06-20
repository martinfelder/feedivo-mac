import Foundation
import Observation
import SwiftData

@Observable
final class FeedViewModel {
    private let fetchFeed: (String) async throws -> ParsedFeed

    var isLoading = false
    var errorMessage: String?

    init(fetchFeed: @escaping (String) async throws -> ParsedFeed = FeedService.fetchFeed) {
        self.fetchFeed = fetchFeed
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
            let parsedFeed = try await fetchFeed(feed.url)
            var seenArticleKeys = Set(feed.articles.map(articleIdentity))
            let newArticles = parsedFeed.articles.filter { parsedArticle in
                seenArticleKeys.insert(articleIdentity(for: parsedArticle)).inserted
            }

            feed.title = parsedFeed.title
            feed.feedDescription = parsedFeed.description
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

            try context.save()
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? L10n.feedErrorParsingFailed
        } catch {
            errorMessage = L10n.feedErrorParsingFailed
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
}
