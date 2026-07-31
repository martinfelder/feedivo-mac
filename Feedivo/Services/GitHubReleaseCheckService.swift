import Foundation

/// Abstraktion über das tatsächliche Netzwerk-Fetching, damit Aufrufer
/// (UpdateChecker) austauschbar/testbar bleiben, ohne eine eigene
/// URLSession-Mocking-Infrastruktur einführen zu müssen (das Projekt hat
/// aktuell keine — FeedService/FaviconService rufen URLSession.shared direkt
/// auf und testen nur ihre reinen Parsing-Funktionen, nicht den Netzwerk-Call
/// selbst; dasselbe Muster wird hier übernommen).
protocol GitHubReleaseFetching: Sendable {
    func fetchReleases() async throws -> [GitHubRelease]
}

enum GitHubReleaseCheckError: Error, LocalizedError, Equatable {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: "updateCheck.error.invalidResponse")
        case .httpError(let statusCode):
            String.localizedStringWithFormat(String(localized: "updateCheck.error.httpError"), statusCode)
        case .decodingFailed:
            String(localized: "updateCheck.error.decodingFailed")
        }
    }
}

struct GitHubReleaseCheckService: GitHubReleaseFetching {
    private let repositoryPath: String
    private let urlSession: URLSession

    init(repositoryPath: String = "martinfelder/feedivo-mac", urlSession: URLSession = .shared) {
        self.repositoryPath = repositoryPath
        self.urlSession = urlSession
    }

    func fetchReleases() async throws -> [GitHubRelease] {
        guard let url = URL(string: "https://api.github.com/repos/\(repositoryPath)/releases") else {
            throw GitHubReleaseCheckError.invalidResponse
        }

        var request = URLRequest(url: url)
        // Liefert body_html zusätzlich zum rohen body-Feld - GitHub rendert das
        // Markdown server-seitig, wir brauchen dafür keinen eigenen Parser.
        request.setValue("application/vnd.github.html+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubReleaseCheckError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw GitHubReleaseCheckError.httpError(statusCode: httpResponse.statusCode)
        }

        return try Self.decodeReleases(from: data)
    }

    /// Reine Decoding-Logik, getrennt vom Netzwerk-Aufruf - dadurch per
    /// Fixture-JSON testbar, ohne URLSession zu mocken.
    static func decodeReleases(from data: Data) throws -> [GitHubRelease] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([GitHubRelease].self, from: data)
        } catch {
            throw GitHubReleaseCheckError.decodingFailed
        }
    }
}
