import Foundation

enum FaviconService {
    typealias HTMLFetcher = (URL) async throws -> String

    static func discoverFaviconURL(
        siteURL: URL,
        fetchHTML: HTMLFetcher = fetchHTML
    ) async -> String? {
        if let html = try? await fetchHTML(siteURL),
           let faviconURL = faviconURL(inHTML: html, pageURL: siteURL) {
            return faviconURL.absoluteString
        }

        return fallbackFaviconURL(for: siteURL)?.absoluteString
    }

    static func faviconURL(inHTML html: String, pageURL: URL) -> URL? {
        faviconCandidates(inHTML: html, pageURL: pageURL)
            .sorted()
            .first?
            .url
    }

    static func fallbackFaviconURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.scheme != nil,
              components.host != nil else {
            return nil
        }

        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func siteURL(from value: String?) -> URL? {
        guard let value else {
            return nil
        }

        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleaned),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.scheme != nil,
              components.host != nil else {
            return nil
        }

        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func fetchHTML(from url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private static func faviconCandidates(inHTML html: String, pageURL: URL) -> [FaviconCandidate] {
        let linkTags = matches(
            pattern: #"<link\b[^>]*>"#,
            in: html,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )

        return linkTags.compactMap { tag in
            let attributes = attributes(in: tag)
            guard let rel = attributes["rel"]?.lowercased(),
                  rel.contains("icon"),
                  let href = attributes["href"],
                  let url = absoluteURL(from: href, relativeTo: pageURL) else {
                return nil
            }

            return FaviconCandidate(
                url: url,
                rel: rel,
                sizeScore: sizeScore(from: attributes["sizes"])
            )
        }
    }

    private static func attributes(in tag: String) -> [String: String] {
        let attributeMatches = matches(
            pattern: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#,
            in: tag,
            options: [.caseInsensitive]
        )

        return attributeMatches.reduce(into: [String: String]()) { result, attribute in
            guard let match = try? NSRegularExpression(
                pattern: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#,
                options: [.caseInsensitive]
            ).firstMatch(
                in: attribute,
                range: NSRange(attribute.startIndex ..< attribute.endIndex, in: attribute)
            ),
                let nameRange = Range(match.range(at: 1), in: attribute) else {
                return
            }

            let value = (2 ... 4).compactMap { index -> String? in
                guard match.range(at: index).location != NSNotFound,
                      let range = Range(match.range(at: index), in: attribute) else {
                    return nil
                }

                return String(attribute[range])
            }.first ?? ""

            result[String(attribute[nameRange]).lowercased()] = value
        }
    }

    private static func absoluteURL(from value: String, relativeTo pageURL: URL) -> URL? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return nil
        }

        if cleaned.hasPrefix("//"),
           let scheme = pageURL.scheme {
            return URL(string: "\(scheme):\(cleaned)")
        }

        return URL(string: cleaned, relativeTo: pageURL)?.absoluteURL
    }

    private static func sizeScore(from sizes: String?) -> Int {
        guard let sizes else {
            return 0
        }

        return sizes
            .split(separator: " ")
            .compactMap { size -> Int? in
                let parts = size.lowercased().split(separator: "x")
                guard parts.count == 2,
                      let width = Int(parts[0]),
                      let height = Int(parts[1]) else {
                    return nil
                }

                return width * height
            }
            .max() ?? 0
    }

    private static func matches(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else {
                return nil
            }

            return String(text[matchRange])
        }
    }
}

private struct FaviconCandidate: Comparable {
    let url: URL
    let rel: String
    let sizeScore: Int

    static func < (lhs: FaviconCandidate, rhs: FaviconCandidate) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }

        if lhs.sizeScore != rhs.sizeScore {
            return lhs.sizeScore > rhs.sizeScore
        }

        return lhs.url.absoluteString < rhs.url.absoluteString
    }

    private var priority: Int {
        if rel.contains("apple-touch-icon") {
            return 400
        }

        if rel.contains("mask-icon") {
            return 300
        }

        if rel.contains("shortcut") {
            return 100
        }

        return 200
    }
}
