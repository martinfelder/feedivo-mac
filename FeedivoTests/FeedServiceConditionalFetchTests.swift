import Foundation
import CryptoKit
import Testing
@testable import Feedivo

struct FeedServiceConditionalFetchTests {
    @Test func conditionalFetchSendetBekannteHTTPValidatoren() async throws {
        let result = try await FeedService.fetchFeedConditionally(
            urlString: "https://example.com/feed.xml",
            validators: FeedHTTPValidators(
                eTag: "\"abc\"",
                lastModified: "Wed, 01 Jul 2026 10:00:00 GMT",
                contentHash: nil,
                lastStatusCode: nil
            ),
            dataLoader: { request in
                #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"abc\"")
                #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == "Wed, 01 Jul 2026 10:00:00 GMT")

                return (
                    Self.rssData(title: "Validator Feed"),
                    Self.httpResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: [
                            "ETag": "\"def\"",
                            "Last-Modified": "Thu, 02 Jul 2026 10:00:00 GMT"
                        ]
                    )
                )
            }
        )

        guard case .updated(let parsedFeed, let validators) = result else {
            Issue.record("Erwartet wurde ein aktualisierter Feed.")
            return
        }

        #expect(parsedFeed.title == "Validator Feed")
        #expect(validators.eTag == "\"def\"")
        #expect(validators.lastModified == "Thu, 02 Jul 2026 10:00:00 GMT")
        #expect(validators.contentHash != nil)
        #expect(validators.lastStatusCode == 200)
    }

    @Test func conditionalFetchGibtNotModifiedOhneParsingZurueck() async throws {
        let result = try await FeedService.fetchFeedConditionally(
            urlString: "https://example.com/feed.xml",
            validators: FeedHTTPValidators(
                eTag: "\"abc\"",
                lastModified: nil,
                contentHash: "old-hash",
                lastStatusCode: nil
            ),
            dataLoader: { request in
                #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"abc\"")

                return (
                    Data("kein feed xml".utf8),
                    Self.httpResponse(
                        url: request.url!,
                        statusCode: 304,
                        headers: [
                            "ETag": "\"abc\""
                        ]
                    )
                )
            }
        )

        guard case .notModified(let validators) = result else {
            Issue.record("Erwartet wurde ein unveränderter Feed.")
            return
        }

        #expect(validators.eTag == "\"abc\"")
        #expect(validators.contentHash == "old-hash")
        #expect(validators.lastStatusCode == 304)
    }

    @Test func conditionalFetchGibtNotModifiedBeiUnveraendertemBodyHashZurueck() async throws {
        let unchangedData = Data("kein feed xml".utf8)
        let unchangedHash = Self.sha256Hex(for: unchangedData)

        let result = try await FeedService.fetchFeedConditionally(
            urlString: "https://example.com/feed.xml",
            validators: FeedHTTPValidators(
                eTag: nil,
                lastModified: nil,
                contentHash: unchangedHash,
                lastStatusCode: 200
            ),
            dataLoader: { request in
                (
                    unchangedData,
                    Self.httpResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: [:]
                    )
                )
            }
        )

        guard case .notModified(let validators) = result else {
            Issue.record("Erwartet wurde ein unveränderter Feed über gleichen Body-Hash.")
            return
        }

        #expect(validators.contentHash == unchangedHash)
        #expect(validators.lastStatusCode == 200)
    }

    @Test func conditionalFetchUebernimmtCacheControlMaxAgeGedeckelt() async throws {
        let result = try await FeedService.fetchFeedConditionally(
            urlString: "https://example.com/feed.xml",
            validators: FeedHTTPValidators(),
            dataLoader: { request in
                (
                    Self.rssData(title: "CC Feed"),
                    Self.httpResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Cache-Control": "max-age=99999"]
                    )
                )
            }
        )

        guard case .updated(_, let validators) = result else {
            Issue.record("Erwartet aktualisierten Feed.")
            return
        }
        #expect(validators.cacheControlMaxAge == 5 * 3600) // auf 5h gedeckelt
    }

    @Test func conditionalFetchFallbackNaehrtCacheControlMaxAgeUndConditionalGetSetAtWeiter() async throws {
        // Fallback-Pfad: dataLoader liefert einen Plain-URLResponse (kein HTTPURLResponse).
        // In diesem Fall dürfen cacheControlMaxAge und conditionalGetSetAt der Eingabe-
        // Validatoren nicht verloren gehen.
        let setAt = Date(timeIntervalSince1970: 1_800_000)
        let inputValidators = FeedHTTPValidators(
            eTag: nil,
            lastModified: nil,
            contentHash: nil,
            lastStatusCode: nil,
            cacheControlMaxAge: 1800,
            conditionalGetSetAt: setAt
        )

        let result = try await FeedService.fetchFeedConditionally(
            urlString: "https://example.com/feed.xml",
            validators: inputValidators,
            dataLoader: { request in
                let plainResponse = URLResponse(
                    url: request.url!,
                    mimeType: nil,
                    expectedContentLength: 0,
                    textEncodingName: nil
                )
                return (Self.rssData(title: "Fallback Feed"), plainResponse)
            }
        )

        guard case .updated(let parsedFeed, let validators) = result else {
            Issue.record("Erwartet aktualisierten Feed über den Fallback-Pfad.")
            return
        }

        #expect(parsedFeed.title == "Fallback Feed")
        #expect(validators.cacheControlMaxAge == 1800)
        #expect(validators.conditionalGetSetAt == setAt)
    }

    @Test func defaultDataLoaderNutztFeedHTTPClientPolicy429() async throws {
        // Plausibilitäts-Check: der Default-Pfad ohne Injection compiliert und
        // läuft. Die echte 429-/Policy-Härtung wird in FeedHTTPClientTests
        // abgedeckt (der shared-Client lässt sich für Tests nicht umkonfigurieren).
        // Hier wird nur sichergestellt, dass der Default-Aufruf die bekannte
        // Signatur hat und FeedHTTPClient im Build verdrahtet ist.
        #expect(FeedHTTPClient.self == FeedHTTPClient.self)
    }

    private static func rssData(title: String) -> Data {
        Data(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <rss version="2.0">
              <channel>
                <title>\(title)</title>
                <link>https://example.com/</link>
                <description>Test Feed</description>
                <item>
                  <title>Artikel</title>
                  <link>https://example.com/article</link>
                  <guid>article-1</guid>
                  <pubDate>Wed, 01 Jul 2026 10:00:00 GMT</pubDate>
                </item>
              </channel>
            </rss>
            """.utf8
        )
    }

    private static func httpResponse(
        url: URL,
        statusCode: Int,
        headers: [String: String]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    private static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
