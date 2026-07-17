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
import WebKit
@testable import Feedivo

struct FeedivoTests {

    @Test func feedServiceErrorTexteSindLokalisiert() {
        #expect(FeedServiceError.invalidURL.errorDescription == "Die Feed-URL ist ungültig.")
        #expect(FeedServiceError.parsingFailed.errorDescription == "Der Feed konnte nicht gelesen werden.")
        #expect(FeedServiceError.httpError(404).errorDescription == "Der Feed konnte nicht geladen werden (HTTP 404).")
        #expect(FeedDiscoveryError.httpError(503).errorDescription == "Der Feed konnte nicht geladen werden (HTTP 503).")
    }

    @Test func fetchFeedWirftHTTPErrorBeiNicht2xxStatus() async throws {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/feed.xml")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!

        await #expect(throws: FeedServiceError.httpError(404)) {
            _ = try await FeedService.fetchFeed(urlString: "https://example.com/feed.xml") { _ in
                (Data(), response)
            }
        }
    }

    @Test func fetchFeedRuftDataLoaderNichtAufDemMainThreadAuf() async throws {
        actor ThreadObservation {
            private(set) var wasMainThread: Bool?

            func record(_ isMainThread: Bool) {
                wasMainThread = isMainThread
            }
        }

        let observation = ThreadObservation()
        let response = URLResponse(
            url: URL(string: "https://example.com/feed.xml")!,
            mimeType: nil,
            expectedContentLength: -1,
            textEncodingName: nil
        )

        _ = try? await FeedService.fetchFeed(urlString: "https://example.com/feed.xml") { _ in
            await observation.record(Thread.isMainThread)
            return (Data(), response)
        }

        let wasMainThread = await observation.wasMainThread
        #expect(wasMainThread == false)
    }

    @Test func appLanguageLiefertLocaleUndFallback() {
        #expect(AppLanguage(rawValue: "de")?.localeIdentifier == "de")
        #expect(AppLanguage(rawValue: "en")?.localeIdentifier == "en")
        #expect(AppLanguage(rawValue: "fr")?.localeIdentifier == "fr")
        #expect(AppLanguage(rawValue: "it")?.localeIdentifier == "it")
        #expect(AppLanguage(rawValue: "system")?.localeIdentifier == nil)
        #expect(AppLanguage.resolved(from: "unbekannt") == .system)
    }

    @Test func appAppearanceLiefertColorSchemeUndFallback() {
        #expect(AppAppearance.resolved(from: "system").colorScheme == nil)
        #expect(AppAppearance.resolved(from: "light").colorScheme == .light)
        #expect(AppAppearance.resolved(from: "dark").colorScheme == .dark)
        #expect(AppAppearance.resolved(from: "unbekannt") == .system)
        #expect(AppAppearance.allCases.count == 3)
        #expect(AppAppearance.defaultMode == .system)
    }

    @Test func firstRunThemeLiefertUnterschiedlicheTokensFuerHellUndDunkel() {
        let light = FirstRunTheme(colorScheme: .light)
        let dark = FirstRunTheme(colorScheme: .dark)

        #expect(light.card != dark.card)
        #expect(light.dropZoneBackground != dark.dropZoneBackground)
        #expect(light.accentStroke != dark.accentStroke)
        #expect(light.card == Color.white)
        #expect(dark.card != Color.white)
    }

    @Test func frostedCardLiefertUnterschiedlicheTokensFuerHellUndDunkel() {
        #expect(Color.frostedCard(for: .light) == Color.white)
        #expect(Color.frostedCard(for: .dark) != Color.white)
        #expect(Color.frostedCard(for: .light) != Color.frostedCard(for: .dark))
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

    @Test func networkConnectionStatusLiefertAnzeigeDaten() {
        #expect(NetworkConnectionStatus.online.localizationKey == "networkStatus.online")
        #expect(NetworkConnectionStatus.online.systemImageName == "wifi")
        #expect(NetworkConnectionStatus.offline.localizationKey == "networkStatus.offline")
        #expect(NetworkConnectionStatus.offline.systemImageName == "wifi.slash")
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

    @Test func readerContentBlockIDBleibtKompaktFuerLangeArtikeltexte() {
        let longParagraph = String(repeating: "Langer Artikeltext ", count: 200)
        let block = ReaderContentBlock.paragraph(longParagraph)

        #expect(block.id.count < 80)
    }

    @Test func readerContentBlockEntriesBleibenBeiDoppeltenAbsaetzenEindeutig() {
        let blocks: [ReaderContentBlock] = [
            .paragraph("Gleicher Absatz"),
            .paragraph("Gleicher Absatz"),
            .heading("Gleicher Absatz")
        ]

        let entries = ReaderContentBlockEntry.entries(from: blocks)

        #expect(entries.map(\.index) == [0, 1, 2])
        #expect(entries.map(\.block) == blocks)
        #expect(Set(entries.map(\.id)).count == 3)
        #expect(entries[0].id.hasSuffix(":0"))
        #expect(entries[1].id.hasSuffix(":1"))
        #expect(entries[2].id.hasSuffix(":0"))
    }

    @Test func readerContentRendererErkenntBilderUndFallbackSummary() {
        #expect(ReaderContentRenderer.isImageHTMLBlock(#"<IMG src="https://example.com/bild.jpg">"#))
        #expect(!ReaderContentRenderer.isImageHTMLBlock("<p>Nur Text</p>"))

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

    @Test func readerContentRendererNutztArticleImageURLAlsLeadBildUndEntferntDuplikat() {
        let blocks = ReaderContentRenderer.blocks(
            summary: nil,
            content: #"<p>Intro</p><img src="https://example.com/lead.jpg"><p>Text</p>"#,
            fallbackImageURL: " https://example.com/lead.jpg "
        )

        #expect(blocks == [
            .image(urlString: "https://example.com/lead.jpg"),
            .paragraph("Intro"),
            .paragraph("Text")
        ])
    }

    @Test func readerContentRendererIgnoriertVGWortZaehlimages() {
        let blocks = ReaderContentRenderer.blocks(
            summary: nil,
            content: #"<p>Artikeltext</p><img src="https://vg05.met.vgwort.de/na/b94510332eaf4f8ea19ced6ac17cd7c0" />"#,
            fallbackImageURL: nil
        )

        #expect(blocks == [.paragraph("Artikeltext")])
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

    @Test func readerContentRendererDekodiertHTMLEntitiesOhneWebKitPfad() {
        let blocks = ReaderContentRenderer.blocks(
            summary: nil,
            content: """
            <p>AT&amp;T &lt; Telekom&nbsp;— &#8230;</p>
            <p>Link: <a href="https://example.com">öffnen</a><br>Neue Zeile</p>
            """,
            fallbackImageURL: nil
        )

        #expect(blocks == [
            .paragraph("AT&T < Telekom — …"),
            .paragraph("Link: öffnen Neue Zeile")
        ])
    }

    @Test func readerContentRendererWandeltHTMLInReinenVorschautextUm() {
        let plainText = ReaderContentRenderer.htmlToPlainText(
            #"<div style="float: center;"><img width="500" height="281" src="https://example.com/bild.jpg" alt=""/></div>Der eigentliche Vorschautext."#
        )

        #expect(plainText == "Der eigentliche Vorschautext.")
    }

    @Test func readerContentRendererDekodiertEntitiesAuchInTextOhneTags() {
        let blocks = ReaderContentRenderer.blocks(
            summary: nil,
            content: "AT&amp;T&nbsp;News &#8230;",
            fallbackImageURL: nil
        )

        #expect(blocks == [
            .paragraph("AT&T News …")
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

    @Test func articleInspectorTypographyIstKompakt() {
        #expect(ArticleInspectorTypography.titleFontSize == 15)
        #expect(ArticleInspectorTypography.sectionTitleFontSize == 13)
        #expect(ArticleInspectorTypography.primaryValueFontSize == 12)
        #expect(ArticleInspectorTypography.controlFontSize == 11.5)
        #expect(ArticleInspectorTypography.labelFontSize == 11)
        #expect(ArticleInspectorTypography.secondaryFontSize == 11)
        #expect(ArticleInspectorTypography.chipFontSize == 11)
        #expect(ArticleInspectorTypography.iconFontSize == 12)
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
        #expect(ReaderTypography.defaultTitleFontSize == 31)
        #expect(ReaderTypography.clampedBodyFontSize(10) == 14)
        #expect(ReaderTypography.clampedBodyFontSize(18) == 18)
        #expect(ReaderTypography.clampedBodyFontSize(40) == 24)

        #expect(ReaderTypography.clampedLineSpacing(0) == 1)
        #expect(ReaderTypography.clampedLineSpacing(6) == 6)
        #expect(ReaderTypography.clampedLineSpacing(20) == 12)
    }

    @Test func readerTypographyDefiniertBoldDefaults() {
        #expect(!ReaderTypography.defaultTitleFontIsBold)
        #expect(!ReaderTypography.defaultBodyFontIsBold)
    }

    @Test func readerTypographyZeigtArtikelbilderStandardmaessig() {
        #expect(ReaderTypography.defaultShowsArticleImages)
    }

    @Test func readerTypographyDefiniertEditorialReaderRhythmus() {
        #expect(ReaderTypography.articleTopPadding == 44)
        #expect(ReaderTypography.articleBottomPadding == 28)
        #expect(ReaderTypography.headerSpacing == 14)
        #expect(ReaderTypography.contentBlockSpacing == 22)
        #expect(ReaderTypography.imageTextDividerSpacing == 14)
        #expect(ReaderTypography.readerDividerOpacity == 0.18)
        #expect(ReaderTypography.leadImageMaxHeight == 460)
        #expect(ReaderTypography.footerTopPadding == 12)
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

    @Test func readerFontPresetWaehltRegistriertenPostScriptNamen() {
        ReaderFontRegistry.registerBundledFonts()

        let customPresets = ReaderFontPreset.allCases.filter { preset in
            preset != .system && preset != .serif
        }

        for preset in customPresets {
            #expect(preset.availableFontName() != nil, "Kein registrierter Font für \(preset.title)")
        }
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

    @Test func feedServiceIgnoriertVGWortZaehlimagesUndNimmtNaechstesArtikelbild() throws {
        let rss = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <title>Feedivo Test Feed</title>
                <item>
                    <title>Artikel mit Zaehlimages</title>
                    <link>https://example.com/html-artikel</link>
                    <description><![CDATA[
                        <p>Kurzer Einstieg</p>
                        <img src="https://vg05.met.vgwort.de/na/b94510332eaf4f8ea19ced6ac17cd7c0">
                        <img src="https://example.com/echtes-bild.jpg" alt="Bild">
                    ]]></description>
                </item>
            </channel>
        </rss>
        """

        let result = try FeedService.parseFeed(data: Data(rss.utf8), sourceURL: "https://example.com/feed.xml")

        #expect(result.articles.first?.imageURL == "https://example.com/echtes-bild.jpg")
    }

    @Test func feedServiceErkenntArtikelbildKandidatenUndZaehlimages() {
        #expect(!FeedService.isArticleImageURLCandidate("https://vg05.met.vgwort.de/na/b94510332eaf4f8ea19ced6ac17cd7c0"))
        #expect(!FeedService.isArticleImageURLCandidate("https://example.com/pixel.gif"))
        #expect(FeedService.isArticleImageURLCandidate("https://example.com/echtes-bild.jpg"))
    }

    @MainActor
    @Test func articleResourceURLPolicyWebContentBlockerRegelnKompilieren() async throws {
        let identifier = "\(ArticleResourceURLPolicy.webContentBlockerIdentifier).Tests.\(UUID().uuidString)"
        let ruleList = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<WKContentRuleList, Error>) in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: ArticleResourceURLPolicy.webContentBlockerRulesJSON
            ) { ruleList, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let ruleList {
                    continuation.resume(returning: ruleList)
                } else {
                    continuation.resume(throwing: URLError(.cannotParseResponse))
                }
            }
        }

        #expect(ruleList.identifier == identifier)
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

    @Test func feedServiceLiestRSSGuidAlsStabileArtikelQuelle() throws {
        let rss = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <title>Feedivo Test Feed</title>
                <item>
                    <title>Artikel mit GUID</title>
                    <guid isPermaLink="false">artikel-123</guid>
                    <link>https://example.com/artikel?utm_source=feed</link>
                    <description>Kurzer Einstieg</description>
                </item>
            </channel>
        </rss>
        """

        let result = try FeedService.parseFeed(data: Data(rss.utf8), sourceURL: "https://example.com/feed.xml")

        #expect(result.articles.first?.sourceID == "artikel-123")
        #expect(result.articles.first?.link == "https://example.com/artikel?utm_source=feed")
    }

    @Test func feedServiceReichertArtikelbildAusVerlinkterArtikelseiteExplizitAn() async throws {
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

        let parsedFeed = try await FeedService.fetchFeed(urlString: "https://example.com/feed.xml") { url in
            guard url.absoluteString == "https://example.com/feed.xml" else {
                Issue.record("Feed-Abruf sollte keine Artikelseite laden: \(url.absoluteString)")
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(), response)
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(rss.utf8), response)
        }

        #expect(parsedFeed.articles.first?.imageURL == nil)

        let enrichedArticles = await FeedService.enrichArticleImagesIfNeeded(in: parsedFeed.articles) { url in
            let data: Data
            switch url.absoluteString {
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

        #expect(enrichedArticles.first?.imageURL == "https://example.com/wp-content/uploads/artikelbild.jpg")
    }

    @Test func statisticsExportServiceEscapedKommasUndAnfuehrungszeichenInCSV() {
        let readingStatistics = ReadingStatisticsSnapshot(
            articlesReadToday: 1,
            articlesReadThisWeek: 2,
            articlesReadTotal: 3,
            topFeeds: [
                ReadingStatisticsFeedCount(feedID: "feed-1", feedTitle: "Feed, mit \"Komma\"", faviconURL: nil, count: 5)
            ],
            dailyReadCounts: [],
            averageReadingMinutesPerDay: 4.2,
            topTags: [],
            totalReadingMinutesAllTime: 120,
            articlesReadInSelectedRange: 3,
            articlesReadInPreviousPeriod: nil
        )

        let csv = StatisticsExportService.buildCSV(readingStatistics: readingStatistics, feedStatistics: [])

        #expect(csv.contains(#""Feed, mit ""Komma""",5"#))
    }

    @Test func statisticsExportServiceEnthaeltAlleAbschnitte() {
        let csv = StatisticsExportService.buildCSV(
            readingStatistics: .empty,
            feedStatistics: [("Example", FeedReadingStatisticsSnapshot(averageArticlesPerWeek: 3.5, readPercentage: 80, averageReadingMinutes: 6))]
        )

        #expect(csv.contains("Kennzahl,Wert"))
        #expect(csv.contains("Meistgelesene Feeds,Anzahl"))
        #expect(csv.contains("Meistgenutzte Tags,Anzahl"))
        #expect(csv.contains("Feed,Artikel pro Woche (Ø),Lese-Prozentsatz,Ø Lesedauer (Minuten)"))
        #expect(csv.contains("Example,3.5,80.0,6.0"))
    }

    private func daysAgo(_ days: Int, from reference: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: reference))!
    }

    private func readingStatistics(readDaysAgo: [Int]) -> ReadingStatisticsSnapshot {
        var snapshot = ReadingStatisticsSnapshot.empty
        snapshot.dailyReadCounts = readDaysAgo.map { ReadingStatisticsDailyCount(date: daysAgo($0), count: 1) }
        return snapshot
    }

    @Test func currentStreakZaehltAufeinanderfolgendeTageBisHeute() {
        let stats = readingStatistics(readDaysAgo: [0, 1, 2])
        #expect(stats.currentStreak == 3)
    }

    @Test func currentStreakBleibtBisMitternachtAktivOhneHeutigenArtikel() {
        let stats = readingStatistics(readDaysAgo: [1, 2])
        #expect(stats.currentStreak == 2)
    }

    @Test func currentStreakIstNullBeiUnterbrochenerSerie() {
        let stats = readingStatistics(readDaysAgo: [3])
        #expect(stats.currentStreak == 0)
    }

    @Test func longestStreakFindetLaengsteSerieUnabhaengigVonAktuellerSerie() {
        let stats = readingStatistics(readDaysAgo: [0, 1] + [20, 21, 22, 23, 24])
        #expect(stats.longestStreak == 5)
        #expect(stats.currentStreak == 2)
    }

    @Test func streaksSindNullOhneGeleseneArtikel() {
        #expect(ReadingStatisticsSnapshot.empty.currentStreak == 0)
        #expect(ReadingStatisticsSnapshot.empty.longestStreak == 0)
    }

    @Test func trendPercentageBerechnetAnstiegUndRueckgang() {
        var increase = ReadingStatisticsSnapshot.empty
        increase.articlesReadInSelectedRange = 12
        increase.articlesReadInPreviousPeriod = 10
        #expect(increase.trendPercentage == 20)

        var decrease = ReadingStatisticsSnapshot.empty
        decrease.articlesReadInSelectedRange = 5
        decrease.articlesReadInPreviousPeriod = 10
        #expect(decrease.trendPercentage == -50)
    }

    @Test func trendPercentageIstNilOhneVorperiode() {
        var stats = ReadingStatisticsSnapshot.empty
        stats.articlesReadInSelectedRange = 7
        stats.articlesReadInPreviousPeriod = nil
        #expect(stats.trendPercentage == nil)
    }

    @Test func trendPercentageIstNilBeiVorperiodeNull() {
        var stats = ReadingStatisticsSnapshot.empty
        stats.articlesReadInSelectedRange = 3
        stats.articlesReadInPreviousPeriod = 0
        #expect(stats.trendPercentage == nil)
    }

    @Test func keyboardShortcutSpecLiefertKorrekteAnzeigeSymbole() {
        let commandN = KeyboardShortcutSpec(key: "n", modifiers: [.command])
        #expect(commandN.displaySymbols == "⌘N")

        // macOS-Reihenfolge ⌃⌥⇧⌘ (Control, Option, Shift, Command) — Shift kommt vor Command.
        let commandShiftR = KeyboardShortcutSpec(key: "r", modifiers: [.command, .shift])
        #expect(commandShiftR.displaySymbols == "⇧⌘R")

        let commandUpArrow = KeyboardShortcutSpec(key: SpecialKey.upArrow.rawValue, modifiers: [.command])
        #expect(commandUpArrow.displaySymbols == "⌘↑")
    }

    @Test func keyboardShortcutSpecZeigtLeertasteAlsSonderzeichen() {
        let plainSpace = KeyboardShortcutSpec(key: " ", modifiers: [])
        #expect(plainSpace.displaySymbols == "␣")

        let shiftSpace = KeyboardShortcutSpec(key: " ", modifiers: [.shift])
        #expect(shiftSpace.displaySymbols == "⇧␣")
    }

    @Test func keyboardShortcutOverridesRundtripDurchJSON() {
        var overrides = KeyboardShortcutOverrides()
        overrides.values["feedAdd"] = .some(KeyboardShortcutSpec(key: "m", modifiers: [.command, .option]))
        overrides.values["articleSearch"] = .some(nil)

        let restored = KeyboardShortcutOverrides.resolved(from: overrides.rawValue)

        #expect(restored.values["feedAdd"] == .some(KeyboardShortcutSpec(key: "m", modifiers: [.command, .option])))
        #expect(restored.values["articleSearch"] == .some(nil))
        #expect(restored.values["feedRefresh"] == nil)
    }

    @Test func keyboardShortcutsSettingsFaelltAufDefaultZurueckWennNichtAngepasst() {
        let overrides = KeyboardShortcutOverrides()
        let spec = KeyboardShortcutsSettings.spec(for: .feedAdd, in: overrides)
        #expect(spec == CustomizableShortcut.feedAdd.defaultSpec)
    }

    @Test func keyboardShortcutsSettingsLiefertNilBeiExplizitGeloeschtemShortcut() {
        var overrides = KeyboardShortcutOverrides()
        overrides.values[CustomizableShortcut.articleSearch.id] = .some(nil)

        let spec = KeyboardShortcutsSettings.spec(for: .articleSearch, in: overrides)
        #expect(spec == nil)
    }

    @Test func keyboardShortcutsSettingsErkenntKonflikt() {
        var overrides = KeyboardShortcutOverrides()
        // feedRefresh (Default ⌘R) wird auf denselben Shortcut wie feedAdd (⌘N) umgelegt.
        overrides.values[CustomizableShortcut.feedRefresh.id] = .some(CustomizableShortcut.feedAdd.defaultSpec!)

        let conflict = KeyboardShortcutsSettings.conflictingShortcut(
            for: CustomizableShortcut.feedAdd.defaultSpec!,
            excluding: .feedAdd,
            in: overrides
        )

        #expect(conflict == .feedRefresh)
    }

    @Test func keyboardShortcutsSettingsKeinKonfliktBeiUnterschiedlichenShortcuts() {
        let overrides = KeyboardShortcutOverrides()
        let conflict = KeyboardShortcutsSettings.conflictingShortcut(
            for: KeyboardShortcutSpec(key: "z", modifiers: [.command, .option, .shift]),
            excluding: .feedAdd,
            in: overrides
        )
        #expect(conflict == nil)
    }

    @Test func customizableShortcutEnthaeltAchtNeueFaelleOhneDefault() {
        let newCases: [CustomizableShortcut] = [
            .feedImportOPML, .feedExportOPML, .feedOrganizerOpen,
            .articleToggleArchived, .articleCopyLink, .articleOpenOriginal,
            .articleShareOriginal, .articleExport
        ]

        for shortcut in newCases {
            #expect(shortcut.defaultSpec == nil, "\(shortcut.rawValue) sollte keinen Default-Shortcut haben")
        }

        #expect(CustomizableShortcut.feedImportOPML.category == .feed)
        #expect(CustomizableShortcut.feedExportOPML.category == .feed)
        #expect(CustomizableShortcut.feedOrganizerOpen.category == .feed)
        #expect(CustomizableShortcut.articleToggleArchived.category == .article)
        #expect(CustomizableShortcut.articleCopyLink.category == .article)
        #expect(CustomizableShortcut.articleOpenOriginal.category == .article)
        #expect(CustomizableShortcut.articleShareOriginal.category == .article)
        #expect(CustomizableShortcut.articleExport.category == .article)

        #expect(CustomizableShortcut.allCases.count == 20)
    }

    @MainActor
    @Test func textEditingFocusMonitorReagiertAufBeginnUndEndeNotification() async throws {
        let center = NotificationCenter()
        let monitor = TextEditingFocusMonitor()
        monitor.startObserving(center: center)

        #expect(monitor.isEditingText == false)

        center.post(name: NSControl.textDidBeginEditingNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(monitor.isEditingText == true)

        center.post(name: NSControl.textDidEndEditingNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(monitor.isEditingText == false)
    }

    @Test func needsTextFieldGuardIstWahrNurOhneModifier() {
        let ohneModifier = KeyboardShortcutSpec(key: "j", modifiers: [])
        let mitModifier = KeyboardShortcutSpec(key: "j", modifiers: [.command])
        let leertasteOhneModifier = KeyboardShortcutSpec(key: " ", modifiers: [])

        #expect(KeyboardShortcutsSettings.needsTextFieldGuard(for: ohneModifier) == true)
        #expect(KeyboardShortcutsSettings.needsTextFieldGuard(for: mitModifier) == false)
        #expect(KeyboardShortcutsSettings.needsTextFieldGuard(for: leertasteOhneModifier) == true)
    }

    @Test func readerArrowKeyNavigationRechtsWechseltNurAusNativeZuWeb() {
        #expect(ReaderArrowKeyNavigation.rightArrowShouldSwitchToWeb(currentMode: .native) == true)
        #expect(ReaderArrowKeyNavigation.rightArrowShouldSwitchToWeb(currentMode: .web) == false)
    }

    @Test func readerArrowKeyNavigationLinksWechseltNurAusWebZuNative() {
        #expect(ReaderArrowKeyNavigation.leftArrowShouldSwitchToNative(currentMode: .web) == true)
        #expect(ReaderArrowKeyNavigation.leftArrowShouldSwitchToNative(currentMode: .native) == false)
    }

    @Test func sidebarFeedOrderOrdnetUnfolderteFeedsVorOrdnernEin() {
        let unfoldered = FeedSidebarSnapshot(
            id: "u1", title: "Unfoldered", url: "https://u1", faviconURL: nil,
            folderName: nil, sortIndex: 0, unreadCount: 0, hasRecentError: false
        )
        let foldered = FeedSidebarSnapshot(
            id: "f1", title: "Foldered", url: "https://f1", faviconURL: nil,
            folderName: "Ordner A", sortIndex: 0, unreadCount: 0, hasRecentError: false
        )
        let folders = [FeedFolderRecord(name: "Ordner A", sortIndex: 0)]

        let ordered = SidebarFeedOrder.orderedFeeds(from: [foldered, unfoldered], folders: folders)

        #expect(ordered.map(\.id) == ["u1", "f1"])
    }

    @Test func sidebarFeedOrderRespektiertOrdnerReihenfolge() {
        let feedInB = FeedSidebarSnapshot(
            id: "b1", title: "In B", url: "https://b1", faviconURL: nil,
            folderName: "Ordner B", sortIndex: 0, unreadCount: 0, hasRecentError: false
        )
        let feedInA = FeedSidebarSnapshot(
            id: "a1", title: "In A", url: "https://a1", faviconURL: nil,
            folderName: "Ordner A", sortIndex: 0, unreadCount: 0, hasRecentError: false
        )
        let folders = [
            FeedFolderRecord(name: "Ordner B", sortIndex: 0),
            FeedFolderRecord(name: "Ordner A", sortIndex: 1)
        ]

        let ordered = SidebarFeedOrder.orderedFeeds(from: [feedInA, feedInB], folders: folders)

        #expect(ordered.map(\.id) == ["b1", "a1"])
    }

    @Test func sidebarFeedOrderNextFeedWithUnreadUeberspringtFeedsOhneUngelesene() {
        let feeds = [
            FeedSidebarSnapshot(id: "1", title: "A", url: "https://1", faviconURL: nil, folderName: nil, sortIndex: 0, unreadCount: 0, hasRecentError: false),
            FeedSidebarSnapshot(id: "2", title: "B", url: "https://2", faviconURL: nil, folderName: nil, sortIndex: 1, unreadCount: 0, hasRecentError: false),
            FeedSidebarSnapshot(id: "3", title: "C", url: "https://3", faviconURL: nil, folderName: nil, sortIndex: 2, unreadCount: 5, hasRecentError: false)
        ]

        let next = SidebarFeedOrder.nextFeedWithUnread(after: "1", in: feeds)

        #expect(next?.id == "3")
    }

    @Test func sidebarFeedOrderNextFeedWithUnreadLiefertNilAmEnde() {
        let feeds = [
            FeedSidebarSnapshot(id: "1", title: "A", url: "https://1", faviconURL: nil, folderName: nil, sortIndex: 0, unreadCount: 3, hasRecentError: false)
        ]

        let next = SidebarFeedOrder.nextFeedWithUnread(after: "1", in: feeds)

        #expect(next == nil)
    }

    @Test func sidebarFeedOrderPreviousFeedWithUnreadUeberspringtFeedsOhneUngelesene() {
        let feeds = [
            FeedSidebarSnapshot(id: "1", title: "A", url: "https://1", faviconURL: nil, folderName: nil, sortIndex: 0, unreadCount: 5, hasRecentError: false),
            FeedSidebarSnapshot(id: "2", title: "B", url: "https://2", faviconURL: nil, folderName: nil, sortIndex: 1, unreadCount: 0, hasRecentError: false),
            FeedSidebarSnapshot(id: "3", title: "C", url: "https://3", faviconURL: nil, folderName: nil, sortIndex: 2, unreadCount: 0, hasRecentError: false)
        ]

        let previous = SidebarFeedOrder.previousFeedWithUnread(before: "3", in: feeds)

        #expect(previous?.id == "1")
    }

    @Test func sidebarFeedOrderPreviousFeedWithUnreadLiefertNilAmAnfang() {
        let feeds = [
            FeedSidebarSnapshot(id: "1", title: "A", url: "https://1", faviconURL: nil, folderName: nil, sortIndex: 0, unreadCount: 3, hasRecentError: false)
        ]

        let previous = SidebarFeedOrder.previousFeedWithUnread(before: "1", in: feeds)

        #expect(previous == nil)
    }

}
