import Foundation

/// Ein einzelnes Release-Asset (z. B. die gepackte .app als ZIP, oder die
/// begleitende .sha256-Prüfsummen-Datei), wie von der GitHub-REST-API im
/// `assets`-Array eines Releases geliefert.
struct GitHubReleaseAsset: Equatable, Sendable, Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

extension GitHubReleaseAsset {
    /// Findet das ZIP-Release-Asset (case-insensitiver Namens-Suffix-Vergleich).
    static func zipAsset(in assets: [GitHubReleaseAsset]) -> GitHubReleaseAsset? {
        assets.first { $0.name.lowercased().hasSuffix(".zip") }
    }

    /// Findet die begleitende SHA256-Prüfsummen-Datei desselben Releases.
    static func checksumAsset(in assets: [GitHubReleaseAsset]) -> GitHubReleaseAsset? {
        assets.first { $0.name.lowercased().hasSuffix(".sha256") }
    }
}

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
    let assets: [GitHubReleaseAsset]

    var id: String { tagName }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case bodyHTML = "body_html"
        case publishedAt = "published_at"
        case assets
    }

    // Handgeschriebener statt synthetisierter Initializer: `assets` bekommt hier
    // einen echten Default-Parameter (`= []`), damit bestehende Testaufrufstellen wie
    // `GitHubRelease(tagName:name:htmlURL:bodyHTML:publishedAt:)` (siehe
    // UpdateCheckerTests.swift) ohne Änderung weiter kompilieren.
    init(
        tagName: String,
        name: String?,
        htmlURL: URL,
        bodyHTML: String?,
        publishedAt: Date?,
        assets: [GitHubReleaseAsset] = []
    ) {
        self.tagName = tagName
        self.name = name
        self.htmlURL = htmlURL
        self.bodyHTML = bodyHTML
        self.publishedAt = publishedAt
        self.assets = assets
    }

    // Eigene Decodable-Implementierung statt Synthese: `assets` fehlt in manchen
    // (z. B. selbst geschriebenen Test-)Fixtures - decodeIfPresent + Fallback auf
    // [] statt eines harten Decoding-Fehlers.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        bodyHTML = try container.decodeIfPresent(String.self, forKey: .bodyHTML)
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        assets = try container.decodeIfPresent([GitHubReleaseAsset].self, forKey: .assets) ?? []
    }
}
