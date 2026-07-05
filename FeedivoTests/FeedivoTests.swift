//
//  FeedivoTests.swift
//  FeedivoTests
//
//  Created by Martin Felder on 19.06.2026.
//

import AppKit
import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Feedivo

struct FeedivoTests {

    @Test func artikelArchivUndHiddenStatusHabenSichereDefaults() {
        let normalerArtikel = Article(title: "Normal")
        let ausgeblendeterArchivArtikel = Article(
            title: "Archiviert",
            isArchived: true,
            isHidden: true
        )

        #expect(!normalerArtikel.isArchived)
        #expect(!normalerArtikel.isHidden)
        #expect(ausgeblendeterArchivArtikel.isArchived)
        #expect(ausgeblendeterArchivArtikel.isHidden)
    }

    @Test func feedBenachrichtigungenSindStandardmaessigDeaktiviert() {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Beispiel")

        #expect(!feed.isNotificationEnabled)
    }

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

    @Test func articleInspectorFormatterBereitetArtikelstatusAuf() {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Example Feed")
        let article = Article(
            title: "Artikel",
            link: "https://example.com/artikel",
            summary: " Kurze Zusammenfassung mit genug Text fuer den oberen Artikelkontext. ",
            content: nil,
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isRead: false,
            isStarred: true,
            feed: feed
        )
        article.offlineState = .failed
        article.offlineErrorMessage = "Timeout"

        let details = ArticleInspectorFormatter.details(
            for: article,
            feedName: "Example Feed",
            contentAvailability: .summaryOnly,
            readingTime: "ca. 1 Min. Lesezeit"
        )

        #expect(details.title == "Artikel")
        #expect(details.summaryExcerpt == "Kurze Zusammenfassung mit genug Text fuer den oberen Artikelkontext.")
        #expect(details.feedName == "Example Feed")
        #expect(details.feedInitial == "E")
        #expect(details.readingTime == "ca. 1 Min. Lesezeit")
        #expect(details.readStateKey == "reader.inspector.unread")
        #expect(details.starStateKey == "reader.inspector.starred")
        #expect(details.offlineStateKey == "reader.offline.failed")
        #expect(details.offlineActionKey == "reader.offline.save")
        #expect(details.offlineDetail == "Timeout")
        #expect(details.hasOriginalURL == true)
    }

    @Test func articleInspectorFormatterNutztVorbereiteteReaderMetadaten() {
        let article = Article(
            title: "Artikel",
            link: "https://example.com/artikel",
            summary: "Kurzfassung",
            content: nil,
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isRead: true,
            isStarred: false
        )

        let details = ArticleInspectorFormatter.details(
            for: article,
            feedName: "Snapshot Feed",
            contentAvailability: .fullText,
            readingTime: "ca. 7 Min. Lesezeit"
        )

        #expect(details.feedName == "Snapshot Feed")
        #expect(details.contentAvailabilityKey == "reader.inspector.content.fullText")
        #expect(details.readingTime == "ca. 7 Min. Lesezeit")
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

    @Test func readerPreparedArticleBerechnetTeureReaderDatenEinmalig() {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Test Feed")
        let article = Article(
            title: "Artikel",
            link: "https://example.com/artikel",
            summary: "<p>Zusammenfassung</p>",
            content: "<p>Absatz</p>",
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
            imageURL: "https://example.com/image.jpg",
            feed: feed
        )

        let preparedArticle = ReaderPreparedArticle(article: article)

        #expect(preparedArticle.contentBlocks == [.image(urlString: "https://example.com/image.jpg"), .paragraph("Absatz")])
        #expect(preparedArticle.metadataText.contains("Test Feed"))
        #expect(preparedArticle.metadataText.contains("ca. 1 Min. Lesezeit"))
        #expect(preparedArticle.originalURL?.absoluteString == "https://example.com/artikel")
        #expect(preparedArticle.contentAvailability == .feedContent)
    }

    @Test func readerPreparedArticleErkenntSummaryOnlyFeedInhalt() {
        let article = Article(
            title: "Artikel",
            link: "https://example.com/artikel",
            summary: "Nur Kurzfassung",
            content: nil
        )

        let preparedArticle = ReaderPreparedArticle(article: article)

        #expect(preparedArticle.contentBlocks == [.paragraph("Nur Kurzfassung")])
        #expect(preparedArticle.contentAvailability == .summaryOnly)
        #expect(preparedArticle.shouldShowSummaryOnlyNotice == false)
    }

    @Test func readerPreparedArticleBevorzugtFeedTextVorGespeichertenOfflineAltlasten() {
        let article = Article(
            title: "Artikel",
            link: "https://example.com/artikel",
            summary: "Nur Kurzfassung",
            content: "<p>Feed Text</p>"
        )
        article.offlineState = .fullText
        article.offlineContent = "<article><p>Gespeicherter Volltext</p></article>"

        let preparedArticle = ReaderPreparedArticle(article: article)

        #expect(preparedArticle.contentBlocks == [.paragraph("Feed Text")])
        #expect(preparedArticle.contentAvailability == .feedContent)
    }

    @Test func readerObservationSignatureIgnoriertSchwereInhalte() {
        let article = Article(
            title: "Artikel",
            link: "https://example.com/artikel",
            summary: "Kurzfassung",
            content: "<p>Alter Feed-Text</p>"
        )
        article.offlineContent = "<article>Alter Offline-Text</article>"

        let initialSignature = ReaderArticleObservationSignature.make(from: article)

        article.content = "<p>Neuer Feed-Text</p>"
        article.offlineContent = "<article>Neuer Offline-Text</article>"

        #expect(ReaderArticleObservationSignature.make(from: article) == initialSignature)

        article.summary = "Aktualisierte Kurzfassung"

        #expect(ReaderArticleObservationSignature.make(from: article) != initialSignature)
    }

    @MainActor
    @Test func readerRelationshipSnapshotKapseltMetadatenAlsLeichteWerte() {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Test Feed", folderName: "News")
        let firstTag = Tag(name: "Zeta", colorHex: "#ff0000")
        let secondTag = Tag(name: "Alpha", colorHex: "#00ff00")
        let article = Article(title: "Artikel", feed: feed)
        article.tags = [firstTag, secondTag]

        let metadata = ReaderArticleRelationshipMetadata.make(from: article)

        #expect(metadata.articleID == article.persistentModelID)
        #expect(metadata.feedName == "Test Feed")
        #expect(metadata.folderName == "News")
        #expect(metadata.tags.map(\.name) == ["Alpha", "Zeta"])
        #expect(metadata.tags.map(\.colorHex) == ["#00ff00", "#ff0000"])
    }

    @MainActor
    @Test func readerPreviewInputNutztNurLeichteFelder() {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Test Feed")
        let article = Article(
            title: "Artikel",
            link: "https://example.com/artikel",
            summary: "Sofort sichtbare Kurzfassung",
            content: "<p>Schwerer Volltext</p>",
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
            imageURL: "https://example.com/bild.jpg",
            feed: feed
        )
        article.offlineState = .fullText
        article.offlineContent = "<article>Schwerer Offline-Text</article>"

        let previewInput = ReaderArticleInput.makePreview(from: article)
        let preview = ReaderPreparedArticle(input: previewInput)

        #expect(previewInput.content == nil)
        #expect(previewInput.feedTitle == "Test Feed")
        #expect(preview.readingTimeText == "ca. 1 Min. Lesezeit")
        #expect(preview.metadataText.contains("Test Feed"))
        #expect(preview.contentBlocks == [
            .image(urlString: "https://example.com/bild.jpg"),
            .paragraph("Sofort sichtbare Kurzfassung")
        ])
        #expect(preview.contentAvailability == .summaryOnly)
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

}
