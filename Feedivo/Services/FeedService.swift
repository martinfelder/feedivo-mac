import Foundation
import FeedKit
import XMLKit

struct ParsedFeed {
    let sourceURL: String
    let title: String
    let description: String?
    let articles: [ParsedArticle]
}

struct ParsedArticle {
    let title: String
    let link: String?
    let summary: String?
    let content: String?
    let publishedAt: Date?
    let imageURL: String?
}

enum FeedServiceError: LocalizedError {
    case invalidURL
    case parsingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Die Feed-URL ist ungültig."
        case .parsingFailed:
            return "Der Feed konnte nicht gelesen werden."
        }
    }
}

enum FeedService {
    static func fetchFeed(urlString: String) async throws -> ParsedFeed {
        guard let url = URL(string: urlString) else {
            throw FeedServiceError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode) {
            throw FeedServiceError.parsingFailed
        }

        return try parseFeed(data: data, sourceURL: urlString)
    }

    static func parseFeed(data: Data, sourceURL: String) throws -> ParsedFeed {
        let feed = try FeedKit.Feed(data: data)

        switch feed {
        case .rss(let rssFeed):
            return parseRSSFeed(rssFeed, sourceURL: sourceURL)
        case .atom(let atomFeed):
            return parseAtomFeed(atomFeed, sourceURL: sourceURL)
        case .json(let jsonFeed):
            return parseJSONFeed(jsonFeed, sourceURL: sourceURL)
        }
    }

    private static func parseRSSFeed(_ rssFeed: RSSFeed, sourceURL: String) -> ParsedFeed {
        let channel = rssFeed.channel
        let articles = channel?.items?.compactMap { item -> ParsedArticle? in
            guard let title = item.title ?? item.description else {
                return nil
            }

            return ParsedArticle(
                title: title,
                link: item.link,
                summary: item.description,
                content: item.content?.encoded,
                publishedAt: item.pubDate,
                imageURL: item.enclosure?.attributes?.url
            )
        } ?? []

        return ParsedFeed(
            sourceURL: sourceURL,
            title: channel?.title ?? sourceURL,
            description: channel?.description,
            articles: articles
        )
    }

    private static func parseAtomFeed(_ atomFeed: AtomFeed, sourceURL: String) -> ParsedFeed {
        let articles = atomFeed.entries?.compactMap { entry -> ParsedArticle? in
            guard let title = entry.title ?? entry.summary?.text else {
                return nil
            }

            return ParsedArticle(
                title: title,
                link: entry.links?.first(where: { $0.attributes?.rel == nil || $0.attributes?.rel == "alternate" })?.attributes?.href,
                summary: entry.summary?.text,
                content: entry.content?.text,
                publishedAt: entry.published ?? entry.updated,
                imageURL: nil
            )
        } ?? []

        return ParsedFeed(
            sourceURL: sourceURL,
            title: atomFeed.title?.text ?? sourceURL,
            description: atomFeed.subtitle?.text,
            articles: articles
        )
    }

    private static func parseJSONFeed(_ jsonFeed: JSONFeed, sourceURL: String) -> ParsedFeed {
        let articles = jsonFeed.items?.compactMap { item -> ParsedArticle? in
            guard let title = item.title ?? item.summary ?? item.contentText else {
                return nil
            }

            return ParsedArticle(
                title: title,
                link: item.url ?? item.externalURL,
                summary: item.summary,
                content: item.contentHtml ?? item.contentText,
                publishedAt: item.datePublished ?? item.dateModified,
                imageURL: item.image ?? item.bannerImage
            )
        } ?? []

        return ParsedFeed(
            sourceURL: sourceURL,
            title: jsonFeed.title ?? sourceURL,
            description: jsonFeed.description,
            articles: articles
        )
    }
}
