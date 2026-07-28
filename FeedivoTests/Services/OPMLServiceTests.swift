import Foundation
import Testing
@testable import Feedivo

struct OPMLServiceTests {

    @Test func parseFeedsReadsNestedOutlinesAndFolders() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>Feedivo Test</title>
          </head>
          <body>
            <outline text="Tech">
              <outline text="heise online" title="heise online News" type="rss" xmlUrl="https://www.heise.de/rss/heise.rdf" htmlUrl="https://www.heise.de/" />
              <outline text="Caschys Blog" type="rss" xmlUrl="https://stadt-bremerhaven.de/feed/" />
            </outline>
            <outline text="Loose Feed" xmlUrl="https://example.com/feed.xml" />
          </body>
        </opml>
        """

        let feeds = try OPMLService.parseFeeds(from: Data(xml.utf8))

        #expect(feeds.count == 3)
        #expect(feeds[0].title == "heise online News")
        #expect(feeds[0].xmlURL == "https://www.heise.de/rss/heise.rdf")
        #expect(feeds[0].htmlURL == "https://www.heise.de/")
        #expect(feeds[0].folderName == "Tech")
        #expect(feeds[1].title == "Caschys Blog")
        #expect(feeds[1].folderName == "Tech")
        #expect(feeds[2].title == "Loose Feed")
        #expect(feeds[2].folderName == nil)
    }

    @Test func parseFeedsRejectsOPMLWithoutFeedOutlines() throws {
        let xml = """
        <opml version="2.0">
          <body>
            <outline text="Folder" />
          </body>
        </opml>
        """

        #expect(throws: OPMLServiceError.noFeedsFound) {
            try OPMLService.parseFeeds(from: Data(xml.utf8))
        }
    }

    @Test func exportFeedsWritesValidOPMLWithEscapedValuesAndFolders() throws {
        let feeds = [
            OPMLFeed(
                title: "News & More",
                xmlURL: "https://example.com/feed.xml",
                htmlURL: "https://example.com/?a=1&b=2",
                folderName: "Tech",
                description: nil,
                tagNames: []
            ),
            OPMLFeed(
                title: "Solo",
                xmlURL: "https://solo.example/feed",
                htmlURL: nil,
                folderName: nil,
                description: nil,
                tagNames: []
            )
        ]

        let xml = OPMLService.exportFeeds(feeds)

        #expect(xml.contains("<opml version=\"2.0\">"))
        #expect(xml.contains("<outline text=\"Tech\">"))
        #expect(xml.contains("text=\"News &amp; More\""))
        #expect(xml.contains("xmlUrl=\"https://example.com/feed.xml\""))
        #expect(xml.contains("htmlUrl=\"https://example.com/?a=1&amp;b=2\""))
        #expect(xml.contains("text=\"Solo\""))
    }

    @Test func exportFeedsCanWriteFlatOPMLWithoutFolders() throws {
        let feeds = [
            OPMLFeed(
                title: "News",
                xmlURL: "https://example.com/feed.xml",
                htmlURL: nil,
                folderName: "Tech",
                description: nil,
                tagNames: []
            )
        ]

        let xml = OPMLService.exportFeeds(
            feeds,
            options: OPMLExportOptions(includesFolders: false)
        )

        #expect(!xml.contains("<outline text=\"Tech\">"))
        #expect(xml.contains("text=\"News\""))
        #expect(xml.contains("xmlUrl=\"https://example.com/feed.xml\""))
    }

    @Test func exportFeedsWritesTagsAndDescriptionsWhenEnabled() throws {
        let feeds = [
            OPMLFeed(
                title: "News & More",
                xmlURL: "https://example.com/feed.xml",
                htmlURL: nil,
                folderName: nil,
                description: "Aktuelle Nachrichten & Analysen",
                tagNames: ["Mac", "Swift"]
            )
        ]

        let xml = OPMLService.exportFeeds(
            feeds,
            options: OPMLExportOptions(
                includesTags: true,
                includesDescriptions: true
            )
        )

        #expect(xml.contains("category=\"Mac,Swift\""))
        #expect(xml.contains("description=\"Aktuelle Nachrichten &amp; Analysen\""))
    }

    @Test func exportFeedsOmitsTagsAndDescriptionsWhenDisabled() throws {
        let feeds = [
            OPMLFeed(
                title: "News",
                xmlURL: "https://example.com/feed.xml",
                htmlURL: nil,
                folderName: nil,
                description: "Beschreibung",
                tagNames: ["Mac"]
            )
        ]

        let xml = OPMLService.exportFeeds(
            feeds,
            options: OPMLExportOptions(
                includesTags: false,
                includesDescriptions: false
            )
        )

        #expect(!xml.contains("category="))
        #expect(!xml.contains("description="))
    }

    @Test func defaultExportFilenameUsesDate() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 6
        components.day = 26
        components.hour = 12
        let date = try #require(components.date)

        #expect(OPMLService.defaultExportFilename(date: date) == "Feedivo-Export-2026-06-26.opml")
    }
}
