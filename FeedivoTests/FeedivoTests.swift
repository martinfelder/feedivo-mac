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

    @Test func feedServiceErrorTexteSindLokalisiert() {
        #expect(FeedServiceError.invalidURL.errorDescription == "Die Feed-URL ist ungültig.")
        #expect(FeedServiceError.parsingFailed.errorDescription == "Der Feed konnte nicht gelesen werden.")
    }

    @Test func appLanguageLiefertLocaleUndFallback() {
        #expect(AppLanguage(rawValue: "de")?.localeIdentifier == "de")
        #expect(AppLanguage(rawValue: "en")?.localeIdentifier == "en")
        #expect(AppLanguage(rawValue: "fr")?.localeIdentifier == "fr")
        #expect(AppLanguage(rawValue: "it")?.localeIdentifier == "it")
        #expect(AppLanguage(rawValue: "system")?.localeIdentifier == nil)
        #expect(AppLanguage.resolved(from: "unbekannt") == .system)
    }

    @Test func readerContentRendererErzeugtAbsaetzeAusHTML() {
        let blocks = ReaderContentRenderer.blocks(
            summary: nil,
            content: "<p>Erster <strong>Absatz</strong>.</p><p>Zweiter Absatz.</p>",
            fallbackImageURL: nil
        )

        #expect(blocks == [
            .paragraph("Erster Absatz."),
            .paragraph("Zweiter Absatz.")
        ])
    }

    @Test func readerContentRendererErkenntBilderUndFallbackSummary() {
        let imageBlocks = ReaderContentRenderer.blocks(
            summary: nil,
            content: #"<p>Text vor dem Bild.</p><img src="https://example.com/bild.jpg" alt="Bild"><p>Text danach.</p>"#,
            fallbackImageURL: nil
        )

        #expect(imageBlocks == [
            .image(urlString: "https://example.com/bild.jpg"),
            .paragraph("Text vor dem Bild."),
            .paragraph("Text danach.")
        ])

        let summaryBlocks = ReaderContentRenderer.blocks(
            summary: "Nur eine kurze Zusammenfassung.",
            content: "",
            fallbackImageURL: "https://example.com/fallback.jpg"
        )

        #expect(summaryBlocks == [
            .image(urlString: "https://example.com/fallback.jpg"),
            .paragraph("Nur eine kurze Zusammenfassung.")
        ])
    }

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

    @Test func feedServiceLiestArtikelbildAusMediaThumbnail() throws {
        let rss = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
            <channel>
                <title>Feedivo Test Feed</title>
                <item>
                    <title>Artikel mit Media-Bild</title>
                    <link>https://example.com/media-artikel</link>
                    <media:thumbnail url="https://example.com/bild-media.jpg" width="1200" height="800" />
                </item>
            </channel>
        </rss>
        """

        let result = try FeedService.parseFeed(data: Data(rss.utf8), sourceURL: "https://example.com/feed.xml")

        #expect(result.articles.first?.imageURL == "https://example.com/bild-media.jpg")
    }

    @Test func feedServiceLiestArtikelbildAusHTMLDescription() throws {
        let rss = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <title>Feedivo Test Feed</title>
                <item>
                    <title>Artikel mit HTML-Bild</title>
                    <link>https://example.com/html-artikel</link>
                    <description><![CDATA[
                        <p>Kurzer Einstieg</p>
                        <img src="https://example.com/bild-html.jpg" alt="Bild">
                    ]]></description>
                </item>
            </channel>
        </rss>
        """

        let result = try FeedService.parseFeed(data: Data(rss.utf8), sourceURL: "https://example.com/feed.xml")

        #expect(result.articles.first?.imageURL == "https://example.com/bild-html.jpg")
    }

}
