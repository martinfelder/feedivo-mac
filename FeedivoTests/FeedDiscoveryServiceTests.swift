import Foundation
import Testing
@testable import Feedivo

struct FeedDiscoveryServiceTests {
    @Test func discoverFeedsErkenntDirekteFeedURL() async throws {
        let service = FeedDiscoveryService(
            fetchFeed: { urlString in
                #expect(urlString == "https://example.com/feed.xml")
                return ParsedFeed(
                    sourceURL: urlString,
                    title: "Direkter Feed",
                    description: nil,
                    siteURL: "https://example.com",
                    articles: []
                )
            },
            loadWebsiteHTML: { _ in
                Issue.record("Website sollte nicht geladen werden, wenn die Eingabe direkt ein Feed ist.")
                return ""
            }
        )

        let result = try await service.discoverFeeds(from: "https://example.com/feed.xml")

        #expect(result == [
            FeedDiscoveryResult(
                title: "Direkter Feed",
                feedURL: "https://example.com/feed.xml",
                siteURL: "https://example.com"
            )
        ])
    }

    @Test func discoverFeedsFindetFeedLinkInWebsiteHTML() async throws {
        let service = FeedDiscoveryService(
            fetchFeed: { urlString in
                if urlString == "https://example.com" {
                    throw FeedServiceError.parsingFailed
                }

                #expect(urlString == "https://example.com/feed.xml")
                return ParsedFeed(
                    sourceURL: urlString,
                    title: "Website Feed",
                    description: nil,
                    siteURL: "https://example.com",
                    articles: []
                )
            },
            loadWebsiteHTML: { url in
                #expect(url.absoluteString == "https://example.com")
                return """
                <html>
                  <head>
                    <link rel="alternate" type="application/rss+xml" title="RSS" href="/feed.xml">
                  </head>
                </html>
                """
            }
        )

        let result = try await service.discoverFeeds(from: "https://example.com")

        #expect(result == [
            FeedDiscoveryResult(
                title: "Website Feed",
                feedURL: "https://example.com/feed.xml",
                siteURL: "https://example.com"
            )
        ])
    }

    @Test func discoverFeedsLiefertMehrereGefundeneFeedsOhneDuplikate() async throws {
        let service = FeedDiscoveryService(
            fetchFeed: { urlString in
                if urlString == "https://example.com" {
                    throw FeedServiceError.parsingFailed
                }

                return ParsedFeed(
                    sourceURL: urlString,
                    title: urlString.contains("podcast") ? "Podcast" : "News",
                    description: nil,
                    siteURL: "https://example.com",
                    articles: []
                )
            },
            loadWebsiteHTML: { _ in
                """
                <link rel="alternate" type="application/rss+xml" title="News" href="/feed.xml">
                <link href="/podcast.xml" title="Podcast" type="application/atom+xml" rel="alternate">
                <link rel="alternate" type="application/rss+xml" title="News doppelt" href="/feed.xml">
                """
            }
        )

        let result = try await service.discoverFeeds(from: "https://example.com")

        #expect(result.map(\.feedURL) == [
            "https://example.com/feed.xml",
            "https://example.com/podcast.xml"
        ])
        #expect(result.map(\.title) == ["News", "Podcast"])
    }

    @Test func discoverFeedsMeldetWebsiteOhneFeedLinksAlsNichtGefunden() async throws {
        let service = FeedDiscoveryService(
            fetchFeed: { _ in
                throw FeedServiceError.parsingFailed
            },
            loadWebsiteHTML: { _ in
                "<html><head><title>Keine Feeds</title></head></html>"
            }
        )

        await #expect(throws: FeedDiscoveryError.noFeedsFound) {
            try await service.discoverFeeds(from: "https://example.com")
        }
    }
}
