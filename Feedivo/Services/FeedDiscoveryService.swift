import Foundation

struct FeedDiscoveryResult: Identifiable, Equatable, Sendable {
    var id: String { feedURL }
    var title: String
    var feedURL: String
    var siteURL: String?
    var faviconURL: String?
    var previewArticles: [FeedDiscoveryPreviewArticle] = []
}

struct FeedDiscoveryPreviewArticle: Identifiable, Equatable, Sendable {
    var id: String { link ?? "\(title)-\(publishedAt?.timeIntervalSince1970 ?? 0)" }
    var title: String
    var link: String?
    var summary: String?
    var publishedAt: Date?
}

enum FeedDiscoveryError: LocalizedError, Equatable {
    case invalidURL
    case noFeedsFound
    /// HTTP-Antwortstatus außerhalb 200…299 beim Laden der Website-HTML (M6).
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return L10n.feedErrorInvalidURL
        case .noFeedsFound:
            return L10n.feedDiscoveryErrorNoFeedsFound
        case .httpError(let statusCode):
            return L10n.feedErrorHTTPStatus(statusCode)
        }
    }
}

struct FeedDiscoveryService {
    typealias FeedFetcher = (String) async throws -> ParsedFeed
    typealias WebsiteHTMLLoader = (URL) async throws -> String

    private struct FeedLinkCandidate {
        var title: String?
        var urlString: String
    }

    private let fetchFeed: FeedFetcher
    private let loadWebsiteHTML: WebsiteHTMLLoader

    init(
        fetchFeed: @escaping FeedFetcher = FeedService.fetchFeed,
        loadWebsiteHTML: @escaping WebsiteHTMLLoader = FeedDiscoveryService.loadWebsiteHTML
    ) {
        self.fetchFeed = fetchFeed
        self.loadWebsiteHTML = loadWebsiteHTML
    }

    func discoverFeeds(from input: String) async throws -> [FeedDiscoveryResult] {
        let websiteURL = try normalizedWebURL(from: input)
        let normalizedInput = websiteURL.absoluteString

        if let directFeed = try? await fetchFeed(normalizedInput) {
            return [
                FeedDiscoveryResult(
                    title: directFeed.title,
                    feedURL: directFeed.sourceURL,
                    siteURL: directFeed.siteURL,
                    faviconURL: Self.faviconURL(for: directFeed),
                    previewArticles: Self.previewArticles(from: directFeed.articles)
                )
            ]
        }

        let html = try await loadWebsiteHTML(websiteURL)
        let candidates = Self.feedLinkCandidates(in: html, baseURL: websiteURL)
        guard !candidates.isEmpty else {
            throw FeedDiscoveryError.noFeedsFound
        }

        var results: [FeedDiscoveryResult] = []
        var seenURLs = Set<String>()

        for candidate in candidates where seenURLs.insert(candidate.urlString).inserted {
            do {
                let parsedFeed = try await fetchFeed(candidate.urlString)
                results.append(
                    FeedDiscoveryResult(
                        title: parsedFeed.title.isEmpty ? candidate.title ?? candidate.urlString : parsedFeed.title,
                        feedURL: parsedFeed.sourceURL,
                        siteURL: parsedFeed.siteURL ?? websiteURL.absoluteString,
                        faviconURL: Self.faviconURL(for: parsedFeed, fallbackSiteURL: websiteURL),
                        previewArticles: Self.previewArticles(from: parsedFeed.articles)
                    )
                )
            } catch {
                continue
            }
        }

        guard !results.isEmpty else {
            throw FeedDiscoveryError.noFeedsFound
        }

        return results
    }

    private static func loadWebsiteHTML(from url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode) {
            throw FeedDiscoveryError.httpError(httpResponse.statusCode)
        }

        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private static func feedLinkCandidates(in html: String, baseURL: URL) -> [FeedLinkCandidate] {
        linkTags(in: html).compactMap { tag in
            let attributes = attributes(in: tag)
            guard
                let href = attributes["href"],
                isFeedLink(rel: attributes["rel"], type: attributes["type"]),
                let absoluteURL = URL(string: href, relativeTo: baseURL)?.absoluteURL
            else {
                return nil
            }

            return FeedLinkCandidate(
                title: attributes["title"],
                urlString: absoluteURL.absoluteString
            )
        }
    }

    private static func isFeedLink(rel: String?, type: String?) -> Bool {
        guard rel?.lowercased().split(separator: " ").contains("alternate") == true else {
            return false
        }

        let normalizedType = type?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalizedType == "application/rss+xml"
            || normalizedType == "application/atom+xml"
            || normalizedType == "application/feed+json"
            || normalizedType == "application/json"
    }

    private static func linkTags(in html: String) -> [String] {
        let pattern = #"<link\b[^>]*>"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return expression.matches(in: html, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: html) else {
                return nil
            }

            return String(html[matchRange])
        }
    }

    private static func attributes(in tag: String) -> [String: String] {
        let pattern = #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(['"])(.*?)\2"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [:]
        }

        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        var attributes: [String: String] = [:]
        for match in expression.matches(in: tag, range: range) {
            guard
                let nameRange = Range(match.range(at: 1), in: tag),
                let valueRange = Range(match.range(at: 3), in: tag)
            else {
                continue
            }

            attributes[String(tag[nameRange]).lowercased()] = String(tag[valueRange])
        }

        return attributes
    }

    private func normalizedWebURL(from input: String) throws -> URL {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            throw FeedDiscoveryError.invalidURL
        }

        let value = trimmedInput.contains("://") ? trimmedInput : "https://\(trimmedInput)"
        guard
            let url = URL(string: value),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil
        else {
            throw FeedDiscoveryError.invalidURL
        }

        return url
    }

    private static func previewArticles(from articles: [ParsedArticle]) -> [FeedDiscoveryPreviewArticle] {
        articles
            .sorted { lhs, rhs in
                switch (lhs.publishedAt, rhs.publishedAt) {
                case let (lhsDate?, rhsDate?):
                    return lhsDate > rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
            .prefix(5)
            .map { article in
                FeedDiscoveryPreviewArticle(
                    title: article.title,
                    link: article.link,
                    summary: article.summary,
                    publishedAt: article.publishedAt
                )
            }
    }

    private static func faviconURL(for feed: ParsedFeed, fallbackSiteURL: URL? = nil) -> String? {
        if let siteURL = FaviconService.siteURL(from: feed.siteURL) {
            return FaviconService.fallbackFaviconURL(for: siteURL)?.absoluteString
        }

        if let fallbackSiteURL {
            return FaviconService.fallbackFaviconURL(for: fallbackSiteURL)?.absoluteString
        }

        return nil
    }
}
