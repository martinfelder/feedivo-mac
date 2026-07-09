import Foundation

/// Ergebnis des Parsens einer `feedivo://`-Deep-Link-URL (Feature 23.2).
enum FeedivoURLSchemeAction: Equatable {
    case addFeed(urlString: String)
    case openArticle(articleID: UUID)
}

/// Reine Parsing-Logik für das `feedivo://`-URL-Schema. Kein SwiftUI-/App-
/// Bezug, dadurch isoliert unit-testbar. Unbekannte Hosts oder fehlende/
/// kaputte Query-Parameter liefern `nil` — der Aufrufer ignoriert die URL
/// dann still (kein Alert, kein Crash).
enum FeedivoURLSchemeParser {
    static func action(for url: URL) -> FeedivoURLSchemeAction? {
        guard url.scheme == "feedivo",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        switch url.host {
        case "add":
            guard let feedURLString = components.queryItems?.first(where: { $0.name == "url" })?.value,
                  !feedURLString.isEmpty
            else {
                return nil
            }

            return .addFeed(urlString: feedURLString)

        case "article":
            guard let idString = components.queryItems?.first(where: { $0.name == "id" })?.value,
                  let articleID = UUID(uuidString: idString)
            else {
                return nil
            }

            return .openArticle(articleID: articleID)

        default:
            return nil
        }
    }
}
