import Foundation
import Testing
@testable import Feedivo

struct FeedServiceParsingHardeningsTests {
    // --- Author ---

    @Test func parseRSSFeedUebernimmtDCCreatorAlsAuthor() throws {
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <channel><title>Test</title>
            <item>
              <title>Artikel</title>
              <link>https://example.com/a1</link>
              <dc:creator>Max Mustermann</dc:creator>
            </item>
          </channel>
        </rss>
        """
        let feed = try FeedService.parseFeed(data: Data(xml.utf8), sourceURL: "https://example.com/feed.xml")
        #expect(feed.articles.first?.author == "Max Mustermann")
    }

    @Test func parseRSSFeedUebernimmtAuthorEmailAlsNamensteil() throws {
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0">
          <channel><title>Test</title>
            <item>
              <title>Artikel</title>
              <link>https://example.com/a2</link>
              <author>anna@example.com (Anna Schmidt)</author>
            </item>
          </channel>
        </rss>
        """
        let feed = try FeedService.parseFeed(data: Data(xml.utf8), sourceURL: "https://example.com/feed.xml")
        #expect(feed.articles.first?.author == "Anna Schmidt")
    }

    @Test func parseAtomFeedUebernimmtAuthorNameMitRootFallback() throws {
        let xml = """
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Test</title>
          <author><name>Root Autor</name></author>
          <entry>
            <id>urn:uuid:1</id>
            <title>Eintrag ohne Autor</title>
            <updated>2026-07-01T10:00:00Z</updated>
          </entry>
        </feed>
        """
        let feed = try FeedService.parseFeed(data: Data(xml.utf8), sourceURL: "https://example.com/atom.xml")
        #expect(feed.articles.first?.author == "Root Autor")
    }

    @Test func parseJSONFeedUebernimmtErstenAuthorNamen() throws {
        // Hinweis: FeedKit unterstützt bei JSON-Feed-Items nur das einzelne
        // `author`-Objekt (Singular), nicht das `authors`-Array aus JSON Feed 1.1.
        // Daher verwendet dieses Fixture die Singulärform, die FeedKit parst.
        let json = """
        {
          "version": "https://jsonfeed.org/version/1.1",
          "title": "Test",
          "items": [
            {"id": "j1", "title": "Eintrag", "author": {"name": "Lisa Lee"}}
          ]
        }
        """
        let feed = try FeedService.parseFeed(data: Data(json.utf8), sourceURL: "https://example.com/feed.json")
        #expect(feed.articles.first?.author == "Lisa Lee")
    }
}