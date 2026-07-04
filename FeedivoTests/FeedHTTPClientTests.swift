import Foundation
import Testing
@testable import Feedivo

// URLProtocol-Stub: liefert konfigurierte Antworten pro URL.
final class FeedHTTPClientTestsURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [URL: (Int, [String: String], Data)] = [:]
    nonisolated(unsafe) static var redirectTargets: [URL: URL] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        // Redirect-Simulation: liefere 302 mit Location
        if let target = Self.redirectTargets[url] {
            let resp = HTTPURLResponse(
                url: url, statusCode: 302, httpVersion: nil,
                headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let entry = Self.responses[url] ?? (404, [:], Data())
        let resp = HTTPURLResponse(
            url: url, statusCode: entry.0, httpVersion: nil, headerFields: entry.1)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: entry.2)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct FeedHTTPClientTests {
    /// Mock-State pro Test zurücksetzen, damit serialisierte Tests sich nicht
    /// in die Quere kommen (parallele Ausführung würde shared static clobbern).
    private func resetMock() {
        FeedHTTPClientTestsURLProtocol.responses = [:]
        FeedHTTPClientTestsURLProtocol.redirectTargets = [:]
    }

    @Test func clientSperrtHostNach429() async throws {
        resetMock()
        FeedHTTPClientTestsURLProtocol.responses = [
            URL(string: "https://blocked.example/feed.xml")!: (429, ["Retry-After": "60"], Data())
        ]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FeedHTTPClientTestsURLProtocol.self]
        let client = FeedHTTPClient(
            sessionConfiguration: config,
            policy: FeedHTTPPolicy(now: { Date(timeIntervalSince1970: 1_000) }))

        do {
            _ = try await client.data(for: URLRequest(url: URL(string: "https://blocked.example/feed.xml")!))
            Issue.record("Erwartet httpError(429)")
        } catch FeedServiceError.httpError(let code) {
            #expect(code == 429)
        }

        // Zweiter Request an selben Host → skip (Host gesperrt), wirft wieder 429
        do {
            _ = try await client.data(for: URLRequest(url: URL(string: "https://blocked.example/other.xml")!))
            Issue.record("Erwartet Sperre")
        } catch FeedServiceError.httpError(let code) {
            #expect(code == 429)
        }
    }

    @Test func clientWirftParsingFailedFuerHtml() async throws {
        resetMock()
        let url = URL(string: "https://html.example/feed.xml")!
        FeedHTTPClientTestsURLProtocol.responses = [
            url: (200, [:], Data("<html><body>kein Feed</body></html>".utf8))
        ]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FeedHTTPClientTestsURLProtocol.self]
        let client = FeedHTTPClient(sessionConfiguration: config)

        do {
            _ = try await client.data(for: URLRequest(url: url))
            Issue.record("Erwartet parsingFailed")
        } catch FeedServiceError.parsingFailed {
            // ok
        }
    }
}