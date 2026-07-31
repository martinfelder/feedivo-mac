import Foundation

/// Ein einzelnes GitHub-Release, wie von der GitHub-REST-API geliefert
/// (`GET /repos/{owner}/{repo}/releases`). Mit dem Header
/// `Accept: application/vnd.github.html+json` liefert GitHub zusätzlich
/// `body_html` — server-seitig aus Markdown gerendertes HTML, das wir direkt
/// in `ReaderContentRenderer` weiterreichen (kein eigener Markdown-Parser nötig).
struct GitHubRelease: Equatable, Sendable, Decodable, Identifiable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let bodyHTML: String?
    let publishedAt: Date?

    var id: String { tagName }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case bodyHTML = "body_html"
        case publishedAt = "published_at"
    }
}
