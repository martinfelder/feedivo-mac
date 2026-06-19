//
//  FeedivoTests.swift
//  FeedivoTests
//
//  Created by Martin Felder on 19.06.2026.
//

import Foundation
import Testing
@testable import Feedivo

struct FeedivoTests {

    @Test func feedServiceParstRSSTitelUndArtikelMetadaten() async throws {
        let rss = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <title>Feedivo Test Feed</title>
                <description>Ein Feed fuer Tests</description>
                <item>
                    <title>Erster Artikel</title>
                    <link>https://example.com/erster-artikel</link>
                    <description>Kurze Zusammenfassung</description>
                    <pubDate>Fri, 19 Jun 2026 10:00:00 GMT</pubDate>
                </item>
            </channel>
        </rss>
        """

        let result = try FeedService.parseFeed(data: Data(rss.utf8), sourceURL: "https://example.com/feed.xml")

        #expect(result.title == "Feedivo Test Feed")
        #expect(result.description == "Ein Feed fuer Tests")
        #expect(result.articles.count == 1)
        #expect(result.articles.first?.title == "Erster Artikel")
        #expect(result.articles.first?.link == "https://example.com/erster-artikel")
        #expect(result.articles.first?.summary == "Kurze Zusammenfassung")
    }

}
