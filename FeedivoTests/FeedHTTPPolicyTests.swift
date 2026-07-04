import Foundation
import Testing
@testable import Feedivo

struct FeedHTTPPolicyTests {
    @Test func record429MitRetryAfterSperrtHost() throws {
        var policy = FeedHTTPPolicy(now: { Date(timeIntervalSince1970: 1_000) })
        let url = URL(string: "https://example.com/feed.xml")!
        let response = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "60"])!
        let action = policy.recordResponse(request: URLRequest(url: url), finalURL: url, response: response, data: Data())

        if case .reject(.httpError(let code)) = action {
            #expect(code == 429)
        } else {
            Issue.record("Erwartet reject .httpError(429)")
        }

        let decision = policy.shouldReject(request: URLRequest(url: url))
        if case .skipHostBlocked(let retryAfter)? = decision {
            #expect(retryAfter == Date(timeIntervalSince1970: 1_060))
        } else {
            Issue.record("Host sollte gesperrt sein")
        }
    }

    @Test func record404BlacklistedURL() throws {
        var policy = FeedHTTPPolicy(now: { Date(timeIntervalSince1970: 1_000) })
        let url = URL(string: "https://example.com/feed.xml")!
        let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
        _ = policy.recordResponse(request: URLRequest(url: url), finalURL: url, response: response, data: Data())

        let decision = policy.shouldReject(request: URLRequest(url: url))
        #expect(decision != nil) // URL für 1h blacklisted
    }

    @Test func redirectWirdGecachtUndBeiFolgeRequestGenutzt() throws {
        var policy = FeedHTTPPolicy(now: { Date() })
        let original = URL(string: "https://blog.example.com/feed")!
        let target = URL(string: "https://blog.example.com/rss.xml")!
        let response = HTTPURLResponse(url: target, statusCode: 200, httpVersion: nil, headerFields: nil)!
        // Simuliere: Request ging an original, Response kam von target (Redirect)
        _ = policy.recordResponse(request: URLRequest(url: original), finalURL: target, response: response, data: Data())

        #expect(policy.redirectTarget(for: original) == target)
    }

    @Test func redirectierteURLDieSpaeter404tWirdGeblacklistetNichtNeuGeleitet() throws {
        // Original leitet auf target weiter; target liefert später 404 → Original-URL
        // wird geblacklistet. Ein Folge-Request muss skipURLBlacklisted zurückgeben,
        // nicht useRedirect — sonst würde der tote Redirect endlos refetcht und die
        // Blacklist wäre für weitergeleitete Feeds wirkungslos.
        var policy = FeedHTTPPolicy(now: { Date(timeIntervalSince1970: 1_000) })
        let original = URL(string: "https://blog.example.com/feed")!
        let target = URL(string: "https://blog.example.com/rss.xml")!
        let redirectResponse = HTTPURLResponse(url: target, statusCode: 200, httpVersion: nil, headerFields: nil)!
        _ = policy.recordResponse(request: URLRequest(url: original), finalURL: target, response: redirectResponse, data: Data())
        let notFound = HTTPURLResponse(url: target, statusCode: 404, httpVersion: nil, headerFields: nil)!
        _ = policy.recordResponse(request: URLRequest(url: original), finalURL: target, response: notFound, data: Data())

        let decision = policy.shouldReject(request: URLRequest(url: original))
        if case .skipURLBlacklisted? = decision {
            // ok — Blacklist schlägt vor dem Redirect-Cache zu
        } else {
            Issue.record("Erwartet .skipURLBlacklisted, bekam \(String(describing: decision))")
        }
    }

    @Test func definitelyNotFeedWirftParsingFailed() throws {
        var policy = FeedHTTPPolicy(now: { Date() })
        let url = URL(string: "https://example.com/feed.xml")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let html = Data("<html><body><h1>Not a feed</h1></body></html>".utf8)
        let action = policy.recordResponse(request: URLRequest(url: url), finalURL: url, response: response, data: html)

        if case .reject(.parsingFailed) = action {
            // ok
        } else {
            Issue.record("Erwartet reject .parsingFailed für HTML-Antwort")
        }
    }
}