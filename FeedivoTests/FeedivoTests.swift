//
//  FeedivoTests.swift
//  FeedivoTests
//
//  Created by Martin Felder on 19.06.2026.
//

import AppKit
import Foundation
import SwiftUI
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

    @Test func interfaceTextSizeLiefertDynamicTypeSizeUndFallback() {
        #expect(InterfaceTextSize.resolved(from: "small") == .small)
        #expect(InterfaceTextSize.resolved(from: "standard") == .standard)
        #expect(InterfaceTextSize.resolved(from: "large") == .large)
        #expect(InterfaceTextSize.resolved(from: "extraLarge") == .extraLarge)
        #expect(InterfaceTextSize.resolved(from: "unbekannt") == .standard)
        #expect(InterfaceTextSize.small.dynamicTypeSize == .medium)
        #expect(InterfaceTextSize.standard.dynamicTypeSize == .large)
        #expect(InterfaceTextSize.large.dynamicTypeSize == .xLarge)
        #expect(InterfaceTextSize.extraLarge.dynamicTypeSize == .xxLarge)
    }

    @Test func interfaceTextSizeSkaliertKonkreteOberflaechenwerte() {
        let baseSize = 14.0

        #expect(InterfaceTextSize.small.scaled(baseSize) < InterfaceTextSize.standard.scaled(baseSize))
        #expect(InterfaceTextSize.standard.scaled(baseSize) == baseSize)
        #expect(InterfaceTextSize.large.scaled(baseSize) > InterfaceTextSize.standard.scaled(baseSize))
        #expect(InterfaceTextSize.extraLarge.scaled(baseSize) > InterfaceTextSize.large.scaled(baseSize))
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

    @Test func readerContentRendererErkenntStrukturierteTextbloecke() {
        let blocks = ReaderContentRenderer.blocks(
            summary: nil,
            content: """
            <h2>Zwischentitel</h2>
            <p>Ein normaler Absatz.</p>
            <blockquote>Ein zitiertes Argument.</blockquote>
            <ul>
                <li>Erster Punkt</li>
                <li>Zweiter Punkt mit <strong>Betonung</strong></li>
            </ul>
            """,
            fallbackImageURL: nil
        )

        #expect(blocks == [
            .heading("Zwischentitel"),
            .paragraph("Ein normaler Absatz."),
            .quote("Ein zitiertes Argument."),
            .listItem("Erster Punkt"),
            .listItem("Zweiter Punkt mit Betonung")
        ])
    }

    @Test func readerContentRendererWirftLeereStrukturbloeckeWegUndFaelltAufAbsatzZurueck() {
        let emptyBlocks = ReaderContentRenderer.blocks(
            summary: nil,
            content: "<h2> </h2><blockquote></blockquote><ul><li> </li></ul>",
            fallbackImageURL: nil
        )

        #expect(emptyBlocks.isEmpty)

        let brokenBlocks = ReaderContentRenderer.blocks(
            summary: nil,
            content: "<section><strong>Kaputter, aber lesbarer Inhalt",
            fallbackImageURL: nil
        )

        #expect(brokenBlocks == [
            .paragraph("Kaputter, aber lesbarer Inhalt")
        ])
    }

    @Test func readerMetadataBerechnetUngefaehreLesezeit() {
        let kurzerText = "Ein kurzer Artikel mit nur wenigen Worten."
        let langerText = Array(repeating: "Wort", count: 420).joined(separator: " ")

        #expect(ReaderMetadataFormatter.readingTimeText(for: kurzerText) == "ca. 1 Min. Lesezeit")
        #expect(ReaderMetadataFormatter.readingTimeText(for: langerText) == "ca. 3 Min. Lesezeit")
    }

    @Test func readerMetadataNutztContentVorSummary() {
        let kurzerSummaryText = "Kurze Summary."
        let langerContentText = Array(repeating: "Wort", count: 260).joined(separator: " ")

        #expect(ReaderMetadataFormatter.readingTimeText(content: langerContentText, summary: kurzerSummaryText) == "ca. 2 Min. Lesezeit")
    }

    @Test func readerFontPresetEnthaeltGewuenschteSchriften() {
        #expect(ReaderFontPreset.allCases.map(\.title) == [
            "System",
            "Geist",
            "Inter",
            "Manrope",
            "DM Sans",
            "Literata",
            "Newsreader",
            "IBM Plex Sans",
            "Atkinson Hyperlegible",
            "Source Serif 4",
            "Libre Franklin",
            "Lora",
            "Merriweather",
            "Noto Sans",
            "Noto Serif",
            "Roboto Slab",
            "Crimson Pro",
            "Fraunces",
            "Serif"
        ])

        #expect(ReaderFontPreset.resolved(from: "system") == .system)
        #expect(ReaderFontPreset.resolved(from: "notoSans") == .notoSans)
        #expect(ReaderFontPreset.resolved(from: "crimsonPro") == .crimsonPro)
        #expect(ReaderFontPreset.resolved(from: "unbekannt") == .system)
    }

    @Test func readerTypographyBegrenztTextgroesseUndZeilenabstand() {
        #expect(ReaderTypography.clampedBodyFontSize(10) == 14)
        #expect(ReaderTypography.clampedBodyFontSize(18) == 18)
        #expect(ReaderTypography.clampedBodyFontSize(40) == 24)

        #expect(ReaderTypography.clampedLineSpacing(0) == 1)
        #expect(ReaderTypography.clampedLineSpacing(6) == 6)
        #expect(ReaderTypography.clampedLineSpacing(20) == 12)
    }

    @Test func readerTypographyBegrenztTitelZeilenabstandSeparat() {
        #expect(ReaderTypography.defaultTitleLineSpacing == 2)
        #expect(ReaderTypography.clampedTitleLineSpacing(-4) == 0)
        #expect(ReaderTypography.clampedTitleLineSpacing(4) == 4)
        #expect(ReaderTypography.clampedTitleLineSpacing(20) == 10)
    }

    @Test func readerTypographyBegrenztArtikelbreite() {
        #expect(ReaderTypography.defaultContentWidth == 720)
        #expect(ReaderTypography.clampedContentWidth(400) == 520)
        #expect(ReaderTypography.clampedContentWidth(760) == 760)
        #expect(ReaderTypography.clampedContentWidth(1200) == 980)
    }

    @Test func readerFontPresetKenntPostScriptKandidaten() {
        #expect(ReaderFontPreset.inter.fontNames.contains("Inter-Regular"))
        #expect(ReaderFontPreset.dmSans.fontNames.contains("DMSans-Regular"))
        #expect(ReaderFontPreset.ibmPlexSans.fontNames.contains("IBMPlexSans-Regular"))
        #expect(ReaderFontPreset.notoSans.fontNames.contains("NotoSans-Regular"))
        #expect(ReaderFontPreset.serif.fontNames.isEmpty)
    }

    @Test func readerFontPresetHatBundleDateienFuerCustomFonts() {
        let customPresets = ReaderFontPreset.allCases.filter { preset in
            preset != .system && preset != .serif
        }

        #expect(customPresets.allSatisfy { $0.bundledFontFileName != nil })
        #expect(customPresets.count == ReaderFontRegistry.fontResourceNames.count)
    }

    @Test func readerFontsLiegenImAppBundle() throws {
        for resourceName in ReaderFontRegistry.fontResourceNames {
            let url = ReaderFontRegistry.fontURL(for: resourceName)
            #expect(url != nil, "Font fehlt im Bundle: \(resourceName)")
        }
    }

    @Test func readerFontRegistryRegistriertBundledFonts() {
        ReaderFontRegistry.registerBundledFonts()

        let availableFonts = Set(NSFontManager.shared.availableFonts)

        #expect(availableFonts.contains("Inter-Regular"))
        #expect(availableFonts.contains("Fraunces-Regular"))
        #expect(availableFonts.contains("SourceSerif4Roman-Regular"))
    }

    @Test func readerTypographyLeitetMetadatenGroesseVomFliesstextAb() {
        #expect(ReaderTypography.metadataFontSize(forBodyFontSize: 14) == 12)
        #expect(ReaderTypography.metadataFontSize(forBodyFontSize: 17) == 13)
        #expect(ReaderTypography.metadataFontSize(forBodyFontSize: 24) == 18)
    }

    @Test func feedServiceParstRSSTitelUndArtikelMetadaten() async throws {
        let rss = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <title>Feedivo Test Feed</title>
                <link>https://example.com/</link>
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
        #expect(result.siteURL == "https://example.com/")
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

    @Test func feedServiceMachtRelativeArtikelbilderAbsolut() throws {
        let rss = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <title>Feedivo Test Feed</title>
                <item>
                    <title>Artikel mit relativem HTML-Bild</title>
                    <link>https://example.com/artikel</link>
                    <description><![CDATA[
                        <p>Kurzer Einstieg</p>
                        <img src="/assets/bild-relativ.jpg" alt="Bild">
                    ]]></description>
                </item>
            </channel>
        </rss>
        """

        let result = try FeedService.parseFeed(data: Data(rss.utf8), sourceURL: "https://example.com/feed.xml")

        #expect(result.articles.first?.imageURL == "https://example.com/assets/bild-relativ.jpg")
    }

    @Test func feedServiceMachtRelativeMediaBilderAbsolut() throws {
        let rss = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
            <channel>
                <title>Feedivo Test Feed</title>
                <item>
                    <title>Artikel mit relativem Media-Bild</title>
                    <link>https://example.com/artikel</link>
                    <media:thumbnail url="bilder/media-bild.jpg" width="1200" height="800" />
                </item>
            </channel>
        </rss>
        """

        let result = try FeedService.parseFeed(data: Data(rss.utf8), sourceURL: "https://example.com/news/feed.xml")

        #expect(result.articles.first?.imageURL == "https://example.com/news/bilder/media-bild.jpg")
    }

    @Test func feedServiceLiestArtikelbildAusVerlinkterArtikelseiteWennFeedKeinBildLiefert() async throws {
        let rss = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <title>Feedivo Test Feed</title>
                <item>
                    <title>Artikel ohne Feed-Bild</title>
                    <link>https://example.com/artikel-ohne-feed-bild/</link>
                    <description>Nur Text ohne Bild</description>
                </item>
            </channel>
        </rss>
        """
        let articleHTML = """
        <!doctype html>
        <html>
            <head>
                <meta property="og:image" content="https://example.com/wp-content/uploads/artikelbild.jpg">
            </head>
            <body></body>
        </html>
        """

        let result = try await FeedService.fetchFeed(urlString: "https://example.com/feed.xml") { url in
            let data: Data
            switch url.absoluteString {
            case "https://example.com/feed.xml":
                data = Data(rss.utf8)
            case "https://example.com/artikel-ohne-feed-bild/":
                data = Data(articleHTML.utf8)
            default:
                Issue.record("Unerwartete URL: \(url.absoluteString)")
                data = Data()
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (data, response)
        }

        #expect(result.articles.first?.imageURL == "https://example.com/wp-content/uploads/artikelbild.jpg")
    }

}
