import Foundation
import CryptoKit
import FeedKit
import XMLKit

struct ParsedFeed: Sendable {
    let sourceURL: String
    let title: String
    let description: String?
    let siteURL: String?
    let articles: [ParsedArticle]

    init(
        sourceURL: String,
        title: String,
        description: String?,
        siteURL: String? = nil,
        articles: [ParsedArticle]
    ) {
        self.sourceURL = sourceURL
        self.title = title
        self.description = description
        self.siteURL = siteURL
        self.articles = articles
    }
}

struct ParsedArticle: Sendable {
    let title: String
    let sourceID: String?
    let link: String?
    let summary: String?
    let content: String?
    let publishedAt: Date?
    let imageURL: String?
    let author: String?

    init(
        title: String,
        sourceID: String? = nil,
        link: String?,
        summary: String?,
        content: String?,
        publishedAt: Date?,
        imageURL: String?,
        author: String? = nil
    ) {
        self.title = title
        self.sourceID = sourceID
        self.link = link
        self.summary = summary
        self.content = content
        self.publishedAt = publishedAt
        self.imageURL = imageURL
        self.author = author
    }

    func copy(imageURL: String?) -> ParsedArticle {
        ParsedArticle(
            title: title,
            sourceID: sourceID,
            link: link,
            summary: summary,
            content: content,
            publishedAt: publishedAt,
            imageURL: imageURL,
            author: author
        )
    }
}

struct FeedHTTPValidators: Equatable, Sendable {
    var eTag: String?
    var lastModified: String?
    var contentHash: String?
    var lastStatusCode: Int?
    var cacheControlMaxAge: Int?
    var conditionalGetSetAt: Date?

    init(
        eTag: String? = nil,
        lastModified: String? = nil,
        contentHash: String? = nil,
        lastStatusCode: Int? = nil,
        cacheControlMaxAge: Int? = nil,
        conditionalGetSetAt: Date? = nil
    ) {
        self.eTag = eTag
        self.lastModified = lastModified
        self.contentHash = contentHash
        self.lastStatusCode = lastStatusCode
        self.cacheControlMaxAge = cacheControlMaxAge
        self.conditionalGetSetAt = conditionalGetSetAt
    }

    /// Deckelt max-age auf 5 h, weil viele Sites Cache-Control falsch konfigurieren.
    static let cacheControlMaxMaxAge = 5 * 3600
}

enum ConditionalFeedFetchResult: Sendable {
    case updated(ParsedFeed, FeedHTTPValidators)
    case notModified(FeedHTTPValidators)
}

enum FeedServiceError: LocalizedError, Equatable {
    case invalidURL
    case parsingFailed
    /// HTTP-Antwortstatus außerhalb 200…299 — eigenständiger Fall statt
    /// misleading als `.parsingFailed` ausgewiesen (M6).
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return L10n.feedErrorInvalidURL
        case .parsingFailed:
            return L10n.feedErrorParsingFailed
        case .httpError(let statusCode):
            return L10n.feedErrorHTTPStatus(statusCode)
        }
    }
}

enum FeedService {
    typealias FeedDataLoader = (URL) async throws -> (Data, URLResponse)
    typealias FeedRequestDataLoader = (URLRequest) async throws -> (Data, URLResponse)

    static func fetchFeed(urlString: String) async throws -> ParsedFeed {
        try await fetchFeed(urlString: urlString) { url in
            try await URLSession.shared.data(from: url)
        }
    }

    static func fetchFeed(
        urlString: String,
        dataLoader: @escaping FeedDataLoader
    ) async throws -> ParsedFeed {
        guard let url = URL(string: urlString) else {
            throw FeedServiceError.invalidURL
        }

        let (data, response) = try await dataLoader(url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode) {
            throw FeedServiceError.httpError(httpResponse.statusCode)
        }

        return try parseFeed(data: data, sourceURL: urlString)
    }

    static func fetchFeedConditionally(
        urlString: String,
        validators: FeedHTTPValidators
    ) async throws -> ConditionalFeedFetchResult {
        try await fetchFeedConditionally(urlString: urlString, validators: validators) { request in
            try await URLSession.shared.data(for: request)
        }
    }

    static func fetchFeedConditionally(
        urlString: String,
        validators: FeedHTTPValidators,
        dataLoader: @escaping FeedRequestDataLoader
    ) async throws -> ConditionalFeedFetchResult {
        guard let url = URL(string: urlString) else {
            throw FeedServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let eTag = validators.eTag?.trimmingCharacters(in: .whitespacesAndNewlines),
           !eTag.isEmpty {
            request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = validators.lastModified?.trimmingCharacters(in: .whitespacesAndNewlines),
           !lastModified.isEmpty {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await dataLoader(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            let parsedFeed = try parseFeed(data: data, sourceURL: urlString)
            // Fallback-Pfad (kein HTTPURLResponse): Werte aus den Eingabe-Validatoren
            // weiterreichen, damit cacheControlMaxAge/conditionalGetSetAt nicht verloren gehen.
            let updatedValidators = FeedHTTPValidators(
                eTag: validators.eTag,
                lastModified: validators.lastModified,
                contentHash: contentHash(for: data),
                lastStatusCode: validators.lastStatusCode,
                cacheControlMaxAge: validators.cacheControlMaxAge,
                conditionalGetSetAt: validators.conditionalGetSetAt
            )
            return .updated(parsedFeed, updatedValidators)
        }

        let responseValidators = validators.updated(from: httpResponse, data: data)
        if httpResponse.statusCode == 304 {
            return .notModified(responseValidators)
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw FeedServiceError.httpError(httpResponse.statusCode)
        }
        if let previousContentHash = validators.contentHash,
           let responseContentHash = responseValidators.contentHash,
           previousContentHash == responseContentHash {
            return .notModified(responseValidators)
        }

        let parsedFeed = try parseFeed(data: data, sourceURL: urlString)
        return .updated(parsedFeed, responseValidators)
    }

    /// Maximale zulässige Abweichung von pubDate in die Zukunft; darüber wird
    /// publishedAt auf nil gesetzt (verhindert Sortier-Sprünge bei fehlerhaften Feeds).
    static let maximumFutureInterval: TimeInterval = 24 * 3600

    static func parseFeed(data: Data, sourceURL: String) throws -> ParsedFeed {
        try parseFeed(data: data, sourceURL: sourceURL, now: Date.init)
    }

    static func parseFeed(data: Data, sourceURL: String, now: @escaping () -> Date) throws -> ParsedFeed {
        let feed = try FeedKit.Feed(data: data)
        let referenceDate = now()

        func clamp(_ date: Date?) -> Date? {
            guard let date else { return nil }
            return date > referenceDate.addingTimeInterval(maximumFutureInterval) ? nil : date
        }

        switch feed {
        case .rss(let rssFeed):
            return parseRSSFeed(rssFeed, sourceURL: sourceURL, clamp: clamp, referenceNow: referenceDate)
        case .atom(let atomFeed):
            return parseAtomFeed(atomFeed, sourceURL: sourceURL, clamp: clamp, referenceNow: referenceDate)
        case .json(let jsonFeed):
            return parseJSONFeed(jsonFeed, sourceURL: sourceURL, clamp: clamp, referenceNow: referenceDate)
        }
    }

    private static func parseRSSFeed(
        _ rssFeed: RSSFeed,
        sourceURL: String,
        clamp: (Date?) -> Date? = { $0 },
        referenceNow: Date = Date()
    ) -> ParsedFeed {
        let channel = rssFeed.channel
        let baseURL = URL(string: sourceURL)
        let articles = channel?.items?.compactMap { item -> ParsedArticle? in
            guard let title = item.title ?? item.description else {
                return nil
            }

            let resolvedLink = item.link.trimmedNonEmpty
            let resolvedSourceID = item.guid?.text.trimmedNonEmpty
                ?? (resolvedLink == nil ? syntheticSourceID(title: title, publishedAt: clamp(item.pubDate), now: referenceNow) : nil)

            return ParsedArticle(
                title: title,
                sourceID: resolvedSourceID,
                link: item.link,
                summary: item.description,
                content: item.content?.encoded,
                publishedAt: clamp(item.pubDate),
                imageURL: firstImageURL(in: item.media, relativeTo: baseURL)
                    ?? cleanImageURL(item.iTunes?.image?.attributes?.href, relativeTo: baseURL)
                    ?? firstImageURL(from: item.enclosure, relativeTo: baseURL)
                    ?? firstImageURL(inHTML: item.content?.encoded, relativeTo: baseURL)
                    ?? firstImageURL(inHTML: item.description, relativeTo: baseURL),
                author: authorDisplayName(from: item.dublinCore?.creator)
                    ?? authorDisplayName(from: item.author)
            )
        } ?? []

        return ParsedFeed(
            sourceURL: sourceURL,
            title: channel?.title ?? sourceURL,
            description: channel?.description,
            siteURL: cleanURL(channel?.link, relativeTo: baseURL),
            articles: articles
        )
    }

    private static func parseAtomFeed(
        _ atomFeed: AtomFeed,
        sourceURL: String,
        clamp: (Date?) -> Date? = { $0 },
        referenceNow: Date = Date()
    ) -> ParsedFeed {
        let baseURL = URL(string: sourceURL)
        let articles = atomFeed.entries?.compactMap { entry -> ParsedArticle? in
            guard let title = entry.title ?? entry.summary?.text else {
                return nil
            }

            let resolvedLink = entry.links?.first(where: { $0.attributes?.rel == nil || $0.attributes?.rel == "alternate" })?.attributes?.href.trimmedNonEmpty
            let resolvedSourceID = entry.id.trimmedNonEmpty
                ?? (resolvedLink == nil ? syntheticSourceID(title: title, publishedAt: clamp(entry.published ?? entry.updated), now: referenceNow) : nil)

            return ParsedArticle(
                title: title,
                sourceID: resolvedSourceID,
                link: entry.links?.first(where: { $0.attributes?.rel == nil || $0.attributes?.rel == "alternate" })?.attributes?.href,
                summary: entry.summary?.text,
                content: entry.content?.text,
                publishedAt: clamp(entry.published ?? entry.updated),
                imageURL: firstImageURL(in: entry.media, relativeTo: baseURL)
                    ?? firstImageURL(inHTML: entry.content?.text, relativeTo: baseURL)
                    ?? firstImageURL(inHTML: entry.summary?.text, relativeTo: baseURL),
                author: authorDisplayName(from: entry.authors?.first?.name)
                    ?? authorDisplayName(from: atomFeed.authors?.first?.name)
            )
        } ?? []

        return ParsedFeed(
            sourceURL: sourceURL,
            title: atomFeed.title?.text ?? sourceURL,
            description: atomFeed.subtitle?.text,
            siteURL: cleanURL(
                atomFeed.links?.first(where: { $0.attributes?.rel == nil || $0.attributes?.rel == "alternate" })?.attributes?.href,
                relativeTo: baseURL
            ),
            articles: articles
        )
    }

    private static func parseJSONFeed(
        _ jsonFeed: JSONFeed,
        sourceURL: String,
        clamp: (Date?) -> Date? = { $0 },
        referenceNow: Date = Date()
    ) -> ParsedFeed {
        let baseURL = URL(string: sourceURL)
        let articles = jsonFeed.items?.compactMap { item -> ParsedArticle? in
            guard let title = item.title ?? item.summary ?? item.contentText else {
                return nil
            }

            let resolvedLink = (item.url ?? item.externalURL).trimmedNonEmpty
            let resolvedSourceID = item.id.trimmedNonEmpty
                ?? (resolvedLink == nil ? syntheticSourceID(title: title, publishedAt: clamp(item.datePublished ?? item.dateModified), now: referenceNow) : nil)

            return ParsedArticle(
                title: title,
                sourceID: resolvedSourceID,
                link: item.url ?? item.externalURL,
                summary: item.summary,
                content: item.contentHtml ?? item.contentText,
                publishedAt: clamp(item.datePublished ?? item.dateModified),
                imageURL: cleanImageURL(item.image, relativeTo: baseURL)
                    ?? cleanImageURL(item.bannerImage, relativeTo: baseURL),
                author: authorDisplayName(from: item.author?.name)
            )
        } ?? []

        return ParsedFeed(
            sourceURL: sourceURL,
            title: jsonFeed.title ?? sourceURL,
            description: jsonFeed.description,
            siteURL: cleanURL(jsonFeed.homePageURL, relativeTo: baseURL),
            articles: articles
        )
    }

    /// Erzeugt eine deterministische synthetische sourceID für Artikel ohne guid
    /// und ohne link, damit ArticleStore den Artikel beim Refresh aktualisiert
    /// statt dupliziert. Präfix "synth:" trennt von echten guids.
    private nonisolated static func syntheticSourceID(title: String, publishedAt: Date?, now: Date) -> String {
        let dateString: String
        if let publishedAt {
            dateString = ISO8601DateFormatter().string(from: publishedAt)
        } else {
            dateString = ISO8601DateFormatter().string(from: now)
        }
        let payload = Data("\(title)|\(dateString)".utf8)
        let digest = SHA256.hash(data: payload)
        return "synth:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func firstImageURL(in media: Media?, relativeTo baseURL: URL?) -> String? {
        guard let media else {
            return nil
        }

        if let url = media.thumbnails?.compactMap({ cleanImageURL($0.attributes?.url, relativeTo: baseURL) }).first {
            return url
        }

        if let url = media.contents?.compactMap({ firstImageURL(in: $0, relativeTo: baseURL) }).first {
            return url
        }

        if let url = media.group?.thumbnails?.compactMap({ cleanImageURL($0.attributes?.url, relativeTo: baseURL) }).first {
            return url
        }

        return media.group?.contents?.compactMap { firstImageURL(in: $0, relativeTo: baseURL) }.first
    }

    private nonisolated static func firstImageURL(in content: MediaContent, relativeTo baseURL: URL?) -> String? {
        if let url = content.thumbnails?.compactMap({ cleanImageURL($0.attributes?.url, relativeTo: baseURL) }).first {
            return url
        }

        guard let url = cleanImageURL(content.attributes?.url, relativeTo: baseURL) else {
            return nil
        }

        let medium = content.attributes?.medium?.lowercased()
        let type = content.attributes?.type?.lowercased()
        if medium == "image" || type?.hasPrefix("image/") == true || looksLikeImageURL(url) {
            return url
        }

        return nil
    }

    private nonisolated static func firstImageURL(from enclosure: RSSFeedEnclosure?, relativeTo baseURL: URL?) -> String? {
        guard let url = cleanImageURL(enclosure?.attributes?.url, relativeTo: baseURL) else {
            return nil
        }

        let type = enclosure?.attributes?.type?.lowercased()
        if type?.hasPrefix("image/") == true || looksLikeImageURL(url) {
            return url
        }

        return nil
    }

    private nonisolated(unsafe) static let imgSrcExpression = try! NSRegularExpression(
        pattern: #"<img[^>]+src\s*=\s*["']([^"']+)["']"#,
        options: [.caseInsensitive]
    )

    private nonisolated static func firstImageURL(inHTML html: String?, relativeTo baseURL: URL?) -> String? {
        guard let html, !html.isEmpty else {
            return nil
        }

        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        guard let match = imgSrcExpression.firstMatch(in: html, range: range),
              let srcRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return cleanImageURL(String(html[srcRange]), relativeTo: baseURL)
    }

    static func enrichArticleImagesIfNeeded(
        in articles: [ParsedArticle]
    ) async -> [ParsedArticle] {
        await enrichArticleImagesIfNeeded(in: articles) { url in
            try await URLSession.shared.data(from: url)
        }
    }

    static func enrichArticleImagesIfNeeded(
        in articles: [ParsedArticle],
        dataLoader: @escaping FeedDataLoader
    ) async -> [ParsedArticle] {
        var enrichedArticles = articles
        let candidates = articles.enumerated().compactMap { index, article -> (index: Int, url: URL)? in
            guard article.imageURL == nil,
                  let link = article.link,
                  let url = URL(string: link),
                  url.scheme != nil
            else {
                return nil
            }

            return (index, url)
        }

        guard !candidates.isEmpty else {
            return articles
        }

        await withTaskGroup(of: (Int, String?).self) { group in
            var iterator = candidates.makeIterator()
            var activeTasks = 0

            for _ in 0 ..< min(4, candidates.count) {
                guard let candidate = iterator.next() else {
                    break
                }

                activeTasks += 1
                group.addTask {
                    let imageURL = await articlePageImageURL(candidate.url, dataLoader: dataLoader)
                    return (candidate.index, imageURL)
                }
            }

            while activeTasks > 0, let result = await group.next() {
                activeTasks -= 1

                if let imageURL = result.1 {
                    enrichedArticles[result.0] = enrichedArticles[result.0].copy(imageURL: imageURL)
                }

                if let candidate = iterator.next() {
                    activeTasks += 1
                    group.addTask {
                        let imageURL = await articlePageImageURL(candidate.url, dataLoader: dataLoader)
                        return (candidate.index, imageURL)
                    }
                }
            }
        }

        return enrichedArticles
    }

    private static func articlePageImageURL(
        _ articleURL: URL,
        dataLoader: FeedDataLoader
    ) async -> String? {
        guard let (data, response) = try? await dataLoader(articleURL),
              (response as? HTTPURLResponse).map({ (200 ... 299).contains($0.statusCode) }) ?? true,
              let html = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return firstMetaImageURL(inHTML: html, relativeTo: articleURL)
    }

    private nonisolated(unsafe) static let metaTagExpression = try! NSRegularExpression(
        pattern: #"<meta\b[^>]*>"#,
        options: [.caseInsensitive]
    )

    // Vorcompilierte Attribut-Regexes für die drei genutzten Meta-Tag-Attribute
    private nonisolated(unsafe) static let metaAttributeExpressions: [String: NSRegularExpression] = {
        Dictionary(uniqueKeysWithValues: ["property", "name", "content"].compactMap { name in
            guard let expr = try? NSRegularExpression(
                pattern: #"\#(name)\s*=\s*["']([^"']+)["']"#,
                options: [.caseInsensitive]
            ) else { return nil }
            return (name, expr)
        })
    }()

    private nonisolated static func firstMetaImageURL(inHTML html: String, relativeTo baseURL: URL?) -> String? {
        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        let matches = metaTagExpression.matches(in: html, range: range)

        for match in matches {
            guard let metaRange = Range(match.range, in: html) else {
                continue
            }

            let metaTag = String(html[metaRange])
            let name = attributeValue(named: "property", in: metaTag)
                ?? attributeValue(named: "name", in: metaTag)

            guard let name,
                  ["og:image", "twitter:image"].contains(name.lowercased()),
                  let content = attributeValue(named: "content", in: metaTag),
                  let imageURL = cleanImageURL(content, relativeTo: baseURL)
            else {
                continue
            }

            return imageURL
        }

        return nil
    }

    private nonisolated static func attributeValue(named attributeName: String, in htmlTag: String) -> String? {
        guard let expression = metaAttributeExpressions[attributeName] else {
            return nil
        }

        let range = NSRange(htmlTag.startIndex ..< htmlTag.endIndex, in: htmlTag)
        guard let match = expression.firstMatch(in: htmlTag, range: range),
              let valueRange = Range(match.range(at: 1), in: htmlTag) else {
            return nil
        }

        return String(htmlTag[valueRange])
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func cleanImageURL(_ value: String?, relativeTo baseURL: URL?) -> String? {
        guard let value else {
            return nil
        }

        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return nil
        }

        return cleanURL(cleaned, relativeTo: baseURL)
    }

    private nonisolated static func looksLikeImageURL(_ url: String) -> Bool {
        guard let components = URLComponents(string: url) else {
            return false
        }

        let path = components.path.lowercased()
        return [".jpg", ".jpeg", ".png", ".gif", ".webp", ".avif"].contains { path.hasSuffix($0) }
    }

    private nonisolated static func cleanURL(_ value: String?, relativeTo baseURL: URL?) -> String? {
        guard let value else {
            return nil
        }

        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return nil
        }

        guard let url = URL(string: cleaned, relativeTo: baseURL)?.absoluteURL else {
            return cleaned
        }

        return url.absoluteString
    }

    /// Liefert den Anzeige-Namen aus einem RSS-<author>- oder <dc:creator>-String.
    /// E-Mail-Form "anna@example.com (Anna Schmidt)" → "Anna Schmidt";
    /// reine E-Mail "anna@example.com" → nil (kein brauchbarer Name).
    private nonisolated static func authorDisplayName(from raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // "anna@example.com (Anna Schmidt)"
        if let parenOpen = trimmed.firstIndex(of: "("),
           let parenClose = trimmed.firstIndex(of: ")"),
           parenOpen < parenClose {
            let name = String(trimmed[trimmed.index(after: parenOpen)..<parenClose])
            return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
        }
        // reine E-Mail ohne Klammern → kein Name
        if trimmed.contains("@"), !trimmed.contains(" ") {
            return nil
        }
        return trimmed
    }

    fileprivate nonisolated static func contentHash(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension Optional where Wrapped == String {
    /// Liefert den getrimmten Wert oder nil, falls danach leer.
    /// Lokales Äquivalent zu `trimmedNonEmpty` in ArticleStore/RetentionService,
    /// da deren Extension file-private ist.
    var trimmedNonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

private extension FeedHTTPValidators {
    func updated(from response: HTTPURLResponse, data: Data) -> FeedHTTPValidators {
        let responseMaxAge = Self.parseCacheControlMaxAge(response.value(forHTTPHeaderField: "Cache-Control"))
        let mergedMaxAge = responseMaxAge ?? cacheControlMaxAge
        let setAt = (response.statusCode == 200) ? Date() : conditionalGetSetAt

        return FeedHTTPValidators(
            eTag: response.value(forHTTPHeaderField: "ETag") ?? eTag,
            lastModified: response.value(forHTTPHeaderField: "Last-Modified") ?? lastModified,
            contentHash: response.statusCode == 304 ? contentHash : FeedService.contentHash(for: data),
            lastStatusCode: response.statusCode,
            cacheControlMaxAge: mergedMaxAge,
            conditionalGetSetAt: setAt
        )
    }

    static func parseCacheControlMaxAge(_ header: String?) -> Int? {
        guard let header, !header.isEmpty else { return nil }
        let lowered = header.lowercased()
        guard let range = lowered.range(of: "max-age=") else { return nil }
        let rest = lowered[range.upperBound...]
        let digits = String(rest.prefix { $0.isNumber })
        guard let seconds = Int(digits) else { return nil }
        return min(seconds, cacheControlMaxMaxAge)
    }
}
