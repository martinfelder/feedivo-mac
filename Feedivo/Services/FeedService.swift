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
                imageURL: firstImageURL(in: item.media)
                    ?? item.iTunes?.image?.attributes?.href
                    ?? firstImageURL(from: item.enclosure)
                    ?? firstImageURL(inHTML: item.content?.encoded)
                    ?? firstImageURL(inHTML: item.description)
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
                imageURL: firstImageURL(in: entry.media)
                    ?? firstImageURL(inHTML: entry.content?.text)
                    ?? firstImageURL(inHTML: entry.summary?.text)
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

    private nonisolated static func firstImageURL(in media: Media?) -> String? {
        guard let media else {
            return nil
        }

        if let url = media.thumbnails?.compactMap({ cleanImageURL($0.attributes?.url) }).first {
            return url
        }

        if let url = media.contents?.compactMap(firstImageURL(in:)).first {
            return url
        }

        if let url = media.group?.thumbnails?.compactMap({ cleanImageURL($0.attributes?.url) }).first {
            return url
        }

        return media.group?.contents?.compactMap(firstImageURL(in:)).first
    }

    private nonisolated static func firstImageURL(in content: MediaContent) -> String? {
        if let url = content.thumbnails?.compactMap({ cleanImageURL($0.attributes?.url) }).first {
            return url
        }

        guard let url = cleanImageURL(content.attributes?.url) else {
            return nil
        }

        let medium = content.attributes?.medium?.lowercased()
        let type = content.attributes?.type?.lowercased()
        if medium == "image" || type?.hasPrefix("image/") == true || looksLikeImageURL(url) {
            return url
        }

        return nil
    }

    private nonisolated static func firstImageURL(from enclosure: RSSFeedEnclosure?) -> String? {
        guard let url = cleanImageURL(enclosure?.attributes?.url) else {
            return nil
        }

        let type = enclosure?.attributes?.type?.lowercased()
        if type?.hasPrefix("image/") == true || looksLikeImageURL(url) {
            return url
        }

        return nil
    }

    private nonisolated static func firstImageURL(inHTML html: String?) -> String? {
        guard let html, !html.isEmpty else {
            return nil
        }

        let pattern = #"<img[^>]+src\s*=\s*["']([^"']+)["']"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        guard let match = expression.firstMatch(in: html, range: range),
              let srcRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return cleanImageURL(String(html[srcRange]))
    }

    private nonisolated static func cleanImageURL(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private nonisolated static func looksLikeImageURL(_ url: String) -> Bool {
        guard let components = URLComponents(string: url) else {
            return false
        }

        let path = components.path.lowercased()
        return [".jpg", ".jpeg", ".png", ".gif", ".webp", ".avif"].contains { path.hasSuffix($0) }
    }
}
