import Foundation

/// Hardened URLSession-Wrapper für Feed-Refreshes: ephemere Session ohne
/// Cookies/URLCache, `httpMaximumConnectionsPerHost = 1`, Timeout 15 s,
/// per-Host User-Agent, und `FeedHTTPPolicy`-gesteuerte 429/4xx/Redirect/
/// „definitiv kein Feed"-Behandlung.
///
/// `FeedHTTPClient.shared.data(for:)` ist Drop-in für den
/// `FeedRequestDataLoader`-Default in `FeedService.fetchFeedConditionally`.
final class FeedHTTPClient: @unchecked Sendable {
    static let shared = FeedHTTPClient()

    private let session: URLSession
    /// `var`, weil `FeedHTTPPolicy.recordResponse` mutating ist — alle
    /// Zugriffe erfolgen unter `lock`, daher `@unchecked Sendable` sicher.
    private var policy: FeedHTTPPolicy
    private let lock = NSLock()

    init(
        sessionConfiguration: URLSessionConfiguration = .feedDefault,
        policy: FeedHTTPPolicy = FeedHTTPPolicy()
    ) {
        self.session = URLSession(configuration: sessionConfiguration)
        self.policy = policy
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // Pre-Request-Policy: Host gesperrt / URL geblacklistet / Redirect cachen?
        let decision: FeedHTTPPolicyDecision? = lock.withLock {
            self.policy.shouldReject(request: request)
        }
        switch decision {
        case .skipHostBlocked, .skipURLBlacklisted:
            // Host-Sperre und URL-Blacklist werden einheitlich als 429 gemeldet,
            // damit der Aufrufer den Feed als „vorübergehend nicht verfügbar" behandelt.
            throw FeedServiceError.httpError(429)
        case .useRedirect(let target):
            var redirected = request
            redirected.url = target
            return try await performAndEvaluate(redirected, originalRequest: request)
        case .none:
            return try await performAndEvaluate(request, originalRequest: request)
        }
    }

    private func performAndEvaluate(
        _ request: URLRequest,
        originalRequest: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedServiceError.parsingFailed
        }
        // `HTTPURLResponse.url` ist in neueren SDKs optional; sie enthält die
        // finale URL (URLSession folgt Redirects automatisch). Fallback auf die
        // angeforderte URL, falls die Response keine mitliefert.
        guard let finalURL = httpResponse.url ?? request.url else {
            throw FeedServiceError.parsingFailed
        }
        let action: FeedHTTPPolicyAction = lock.withLock {
            self.policy.recordResponse(
                request: originalRequest,
                finalURL: finalURL,
                response: httpResponse,
                data: data)
        }
        switch action {
        case .proceed:
            return (data, httpResponse)
        case .reject(let error):
            throw error
        }
    }
}

extension URLSessionConfiguration {
    /// Default-Konfiguration für Feed-Refreshes: keine persistenten Cookies,
    /// kein URLCache, eine Verbindung pro Host, 15/30 s Timeouts und ein
    /// Feedivo-User-Agent.
    static var feedDefault: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 1
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = ["User-Agent": "Feedivo/1.0 (macOS RSS Reader)"]
        return config
    }
}
