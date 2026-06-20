import Foundation
import Testing
@testable import Feedivo

struct FaviconServiceTests {

    @Test func parseFaviconURLBevorzugtAppleTouchIconMitGroessterGroesse() throws {
        let html = """
        <html>
            <head>
                <link rel="icon" sizes="32x32" href="/favicon-32.png">
                <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">
                <link rel="shortcut icon" href="/favicon.ico">
            </head>
        </html>
        """
        let pageURL = try #require(URL(string: "https://example.com/news/"))

        let faviconURL = FaviconService.faviconURL(inHTML: html, pageURL: pageURL)

        #expect(faviconURL?.absoluteString == "https://example.com/apple-touch-icon.png")
    }

    @Test func parseFaviconURLMachtRelativeUndProtokollRelativeURLsAbsolut() throws {
        let relativeHTML = #"<link href="icons/favicon.svg" rel="mask-icon">"#
        let protocolRelativeHTML = #"<link rel="icon" href="//cdn.example.com/favicon.png">"#
        let pageURL = try #require(URL(string: "https://example.com/blog/index.html"))

        let relativeURL = FaviconService.faviconURL(inHTML: relativeHTML, pageURL: pageURL)
        let protocolRelativeURL = FaviconService.faviconURL(inHTML: protocolRelativeHTML, pageURL: pageURL)

        #expect(relativeURL?.absoluteString == "https://example.com/blog/icons/favicon.svg")
        #expect(protocolRelativeURL?.absoluteString == "https://cdn.example.com/favicon.png")
    }

    @Test func fallbackFaviconURLNutztWebsiteRoot() throws {
        let feedURL = try #require(URL(string: "https://example.com/news/feed.xml?format=rss"))

        let fallbackURL = FaviconService.fallbackFaviconURL(for: feedURL)

        #expect(fallbackURL?.absoluteString == "https://example.com/favicon.ico")
    }

    @Test func discoverFaviconURLNutztHTMLUndFaelltAufFaviconIcoZurueck() async throws {
        let siteURL = try #require(URL(string: "https://example.com/"))
        let html = #"<link rel="icon" sizes="64x64" href="/favicon-64.png">"#

        let discoveredURL = await FaviconService.discoverFaviconURL(
            siteURL: siteURL,
            fetchHTML: { url in
                #expect(url == siteURL)
                return html
            }
        )

        let fallbackURL = await FaviconService.discoverFaviconURL(
            siteURL: siteURL,
            fetchHTML: { _ in throw TestFaviconFetchError() }
        )

        #expect(discoveredURL == "https://example.com/favicon-64.png")
        #expect(fallbackURL == "https://example.com/favicon.ico")
    }
}

private struct TestFaviconFetchError: Error {}
