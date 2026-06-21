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

    // Gecachte Regex-Objekte — einmalig kompiliert statt bei jedem Aufruf neu
    private static let linkTagExpression = try! NSRegularExpression(
        pattern: #"<link\b[^>]*>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    private static let tagAttributeExpression = try! NSRegularExpression(
        pattern: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#,
        options: [.caseInsensitive]
    )

    private static func faviconCandidates(inHTML html: String, pageURL: URL) -> [FaviconCandidate] {
        let htmlRange = NSRange(html.startIndex ..< html.endIndex, in: html)
        let linkTagMatches = linkTagExpression.matches(in: html, range: htmlRange)

        return linkTagMatches.compactMap { match -> FaviconCandidate? in
            guard let tagRange = Range(match.range, in: html) else { return nil }
            let tag = String(html[tagRange])
            let attrs = attributes(in: tag)
            guard let rel = attrs["rel"]?.lowercased(),
                  rel.contains("icon"),
                  let href = attrs["href"],
                  let url = absoluteURL(from: href, relativeTo: pageURL) else {
                return nil
            }

            return FaviconCandidate(
                url: url,
                rel: rel,
                sizeScore: sizeScore(from: attrs["sizes"])
            )
        }
    }

    // Einzel-Durchlauf mit Capture Groups — kein doppeltes Kompilieren mehr
    private static func attributes(in tag: String) -> [String: String] {
        let range = NSRange(tag.startIndex ..< tag.endIndex, in: tag)
        let attrMatches = tagAttributeExpression.matches(in: tag, range: range)

        return attrMatches.reduce(into: [String: String]()) { result, match in
            guard let nameRange = Range(match.range(at: 1), in: tag) else { return }

            let value = (2 ... 4).compactMap { index -> String? in
                guard match.range(at: index).location != NSNotFound,
                      let valueRange = Range(match.range(at: index), in: tag) else { return nil }
                return String(tag[valueRange])
            }.first ?? ""

            result[String(tag[nameRange]).lowercased()] = value
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
