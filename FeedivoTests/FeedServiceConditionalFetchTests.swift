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
