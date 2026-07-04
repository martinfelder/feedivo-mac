import Foundation

/// HTTP-Strategie für Feed-Refreshes. In-memory, pro App-Lebensdauer.
/// Steuert 429-Host-Sperre, 4xx-URL-Blacklist, Redirect-Cache und
/// „definitiv kein Feed"-Erkennung. Rein logisch — keine Netzwerk-Aufrufe.
struct FeedHTTPPolicy {
    private var blockedHosts: [String: Date] = [:]      // host → Sperrung-bis
    private var blacklistedURLs: [URL: Date] = [:]      // url → Blacklist-bis
    private var redirectCache: [URL: URL] = [:]         // original → final

    /// Hosts, deren Conditional-GET-Info nicht gedropped werden darf.
    static let noConditionalGetDropHosts: Set<String> = ["openrss.org", "rachelbythebay.com"]

    private let now: () -> Date
    let blacklistDuration: TimeInterval        // Default 1 h
    let default429RetrySeconds: TimeInterval   // Default 600

    init(
        now: @escaping () -> Date = Date.init,
        blacklistDuration: TimeInterval = 3600,
        default429RetrySeconds: TimeInterval = 600
    ) {
        self.now = now
        self.blacklistDuration = blacklistDuration
        self.default429RetrySeconds = default429RetrySeconds
    }

    // Pre-Request: liefert eine Entscheidung, falls der Request gar nicht erst raus soll.
    // Reihenfolge: Blacklist/Host-Sperre VOR Redirect-Cache. Würden wir den
    // Redirect-Cache zuerst fragen, hätte eine Original-URL, die nach einem
    // Redirect zwischendurch 4xx/404 lief und daher geblacklistet wurde, keine
    // Wirkung mehr — der gecachte Redirect würde sie endlos erneut anfetchen.
    func shouldReject(request: URLRequest) -> FeedHTTPPolicyDecision? {
        guard let url = request.url else { return nil }

        if let until = blacklistedURLs[url], until > now() {
            return .skipURLBlacklisted(until: until)
        }
        if let host = url.host, let until = blockedHosts[host], until > now() {
            return .skipHostBlocked(retryAfter: until)
        }
        if let target = redirectCache[url] {
            return .useRedirect(target)
        }
        return nil
    }

    func redirectTarget(for originalURL: URL) -> URL? {
        redirectCache[originalURL]
    }

    // Post-Response: werten die Antwort aus und mutieren den Policy-Zustand.
    mutating func recordResponse(
        request: URLRequest,
        finalURL: URL,
        response: HTTPURLResponse,
        data: Data
    ) -> FeedHTTPPolicyAction {
        let originalURL = request.url ?? finalURL

        // Redirect cachen, falls die finale URL von der angeforderten abweicht.
        if finalURL != originalURL, originalURL.host == finalURL.host || sameRegistrableDomain(originalURL, finalURL) {
            redirectCache[originalURL] = finalURL
        }

        switch response.statusCode {
        case 429:
            let retryAfter = parseRetryAfter(response.value(forHTTPHeaderField: "Retry-After"))
                ?? now().addingTimeInterval(default429RetrySeconds)
            if let host = finalURL.host {
                blockedHosts[host] = retryAfter
            }
            return .reject(.httpError(429))
        case 400...499:
            if let host = finalURL.host {
                blockedHosts[host] = now().addingTimeInterval(blacklistDuration)
            }
            blacklistedURLs[originalURL] = now().addingTimeInterval(blacklistDuration)
            return .reject(.httpError(response.statusCode))
        default:
            break
        }

        if isDefinitelyNotFeed(data) {
            return .reject(.parsingFailed)
        }
        return .proceed
    }

    // Host-Sperre / Blacklist aufräumen (gelegentlich aufrufen).
    mutating func prune() {
        let current = now()
        blockedHosts = blockedHosts.filter { $0.value > current }
        blacklistedURLs = blacklistedURLs.filter { $0.value > current }
    }

    private func parseRetryAfter(_ header: String?) -> Date? {
        guard let header else { return nil }
        if let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)) {
            return now().addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: header).map { $0 }
    }

    private func isDefinitelyNotFeed(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(512), encoding: .utf8) else { return false }
        let trimmed = prefix.lstripWhitespace()
        if trimmed.hasPrefix("<?xml") { return false }
        if trimmed.hasPrefix("<rss") || trimmed.hasPrefix("<feed") || trimmed.hasPrefix("<rdf") { return false }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return false } // JSON Feed
        if trimmed.hasPrefix("<!DOCTYPE html") || trimmed.hasPrefix("<html") { return true }
        return false
    }

    private func sameRegistrableDomain(_ a: URL, _ b: URL) -> Bool {
        guard let hostA = a.host, let hostB = b.host else { return false }
        let regA = registrableDomain(hostA)
        let regB = registrableDomain(hostB)
        return regA == regB
    }

    private func registrableDomain(_ host: String) -> String {
        let parts = host.split(separator: ".").suffix(2)
        return parts.joined(separator: ".")
    }
}

enum FeedHTTPPolicyDecision: Equatable {
    case skipHostBlocked(retryAfter: Date)
    case skipURLBlacklisted(until: Date)
    case useRedirect(URL)
}

enum FeedHTTPPolicyAction: Equatable {
    case proceed
    case reject(FeedServiceError)
}

private extension String {
    func lstripWhitespace() -> String {
        var view = self[...]
        while let first = view.first, first.isWhitespace { view = view.dropFirst() }
        return String(view)
    }
}