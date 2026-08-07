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
                siteURL: "https://example.com",
                faviconURL: "https://example.com/favicon.ico"
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
                siteURL: "https://example.com",
                faviconURL: "https://example.com/favicon.ico"
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

    @Test func websiteHTMLRequestSetztConsentCookieFuerYouTubeHosts() {
        let request = FeedDiscoveryService.websiteHTMLRequest(for: URL(string: "https://www.youtube.com/@Apple")!)

        #expect(request.value(forHTTPHeaderField: "Cookie") == "CONSENT=YES+cb.20210328-17-p0.en+FX+000")
    }

    @Test func websiteHTMLRequestErkenntYouTubeHostOhneWWWPraefix() {
        let request = FeedDiscoveryService.websiteHTMLRequest(for: URL(string: "https://youtube.com/@Apple")!)

        #expect(request.value(forHTTPHeaderField: "Cookie") == "CONSENT=YES+cb.20210328-17-p0.en+FX+000")
    }

    @Test func websiteHTMLRequestSetztKeinConsentCookieFuerAndereHosts() {
        let request = FeedDiscoveryService.websiteHTMLRequest(for: URL(string: "https://example.com")!)

        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test func discoverFeedsLiefertMaximalFuenfVorschauArtikelNeuesteZuerst() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let service = FeedDiscoveryService(
            fetchFeed: { urlString in
                ParsedFeed(
                    sourceURL: urlString,
                    title: "Vorschau Feed",
                    description: nil,
                    siteURL: "https://example.com",
                    articles: (1 ... 7).map { day in
                        ParsedArticle(
                            title: "Artikel \(day)",
                            link: "https://example.com/\(day)",
                            summary: day == 7 ? "Neuester Artikel" : nil,
                            content: nil,
                            publishedAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: day)),
                            imageURL: nil
                        )
                    }
                )
            },
            loadWebsiteHTML: { _ in
                Issue.record("Website sollte nicht geladen werden, wenn die Eingabe direkt ein Feed ist.")
                return ""
            }
        )

        let result = try await service.discoverFeeds(from: "https://example.com/feed.xml")

        #expect(result.first?.previewArticles.map(\.title) == [
            "Artikel 7",
            "Artikel 6",
            "Artikel 5",
            "Artikel 4",
            "Artikel 3"
        ])
        #expect(result.first?.previewArticles.first?.summary == "Neuester Artikel")
    }
}
