import Foundation
import Testing
@testable import Feedivo

struct ArticleExportServiceTests {
    @Test func markdownExportEnthaeltMetadatenUndLesbarenArtikeltext() {
        let article = Article(
            title: "Swift & RSS",
            link: "https://example.com/swift-rss",
            summary: "Kurze Zusammenfassung",
            content: "<h2>Untertitel</h2><p>Ein <strong>lesbarer</strong> Absatz.</p><blockquote>Zitat</blockquote><ul><li>Erster Punkt</li></ul>",
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let markdown = ArticleExportService.markdown(for: article)

        #expect(markdown.contains("# Swift & RSS"))
        #expect(markdown.contains("Link: https://example.com/swift-rss"))
        #expect(markdown.contains("## Untertitel"))
        #expect(markdown.contains("Ein lesbarer Absatz."))
        #expect(markdown.contains("> Zitat"))
        #expect(markdown.contains("- Erster Punkt"))
    }

    @Test func markdownExportBevorzugtOfflineContentVorFeedContentUndSummary() {
        let article = Article(
            title: "Offline",
            summary: "Summary",
            content: "Feed Content"
        )
        article.offlineState = .fullText
        article.offlineContent = "<p>Gespeicherter Volltext</p>"

        let markdown = ArticleExportService.markdown(for: article)

        #expect(markdown.contains("Gespeicherter Volltext"))
        #expect(!markdown.contains("Feed Content"))
        #expect(!markdown.contains("Summary"))
    }

    @Test func markdownExportVerarbeitetUnvollstaendigesHTMLOhneAppKitHTMLImporter() {
        let article = Article(
            title: "Kaputtes HTML",
            content: "<article><p>Absatz &amp; Text<script>window.crash()</script><blockquote>Zitat"
        )

        let markdown = ArticleExportService.markdown(for: article)

        #expect(markdown.contains("Absatz & Text"))
        #expect(markdown.contains("> Zitat"))
        #expect(!markdown.contains("window.crash"))
    }

    @Test func defaultFilenameBereinigtArtikeltitelFuerDateisystem() {
        let article = Article(title: "Swift/RSS: Was ist neu?")

        #expect(ArticleExportService.defaultFilename(for: article) == "Swift-RSS- Was ist neu.md")
    }

    @Test func markdownExportKannMetadatenAusblenden() {
        let article = Article(
            title: "Swift & RSS",
            link: "https://example.com/swift-rss",
            summary: "Kurze Zusammenfassung",
            content: "<p>Artikeltext</p>",
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let text = ArticleExportService.text(
            for: ArticleExportSnapshot(article: article),
            options: ArticleExportOptions(format: .markdown, includesMetadata: false)
        )

        #expect(text.contains("# Swift & RSS"))
        #expect(text.contains("Artikeltext"))
        #expect(!text.contains("Link:"))
        #expect(!text.contains("Veröffentlicht:"))
    }

    @Test func markdownVorschauRendertBlockMarkdownAlsHTML() {
        let markdown = """
        # Swift & RSS

        Autor: Ada

        ---

        ## Untertitel

        - Erster Punkt
        - Zweiter Punkt

        > Zitat
        """

        let html = ArticleExportPreviewRenderer.htmlForMarkdownPreview(markdown)

        #expect(html.contains("<h1>Swift &amp; RSS</h1>"))
        #expect(html.contains("<hr>"))
        #expect(html.contains("<h2>Untertitel</h2>"))
        #expect(html.contains("<ul>"))
        #expect(html.contains("<li>Erster Punkt</li>"))
        #expect(html.contains("<blockquote>"))
        #expect(!html.contains("# Swift & RSS"))
    }

    @Test func markdownVorschauRendertOfflineBilderAusExportPaket() {
        let markdown = """
        # Bild

        ![](Pictures/image-1.png)
        """
        let html = ArticleExportPreviewRenderer.htmlForMarkdownPreview(
            markdown,
            assets: [
                ArticleExportPackageAsset(path: "Pictures/image-1.png", data: Data([0x01, 0x02]))
            ]
        )

        #expect(html.contains(#"<img src="data:image/png;base64,AQI=" alt="">"#))
        #expect(!html.contains(#"src="Pictures/image-1.png""#))
    }

    @Test func plainTextExportEnthaeltKeineMarkdownSyntax() {
        let article = Article(
            title: "Swift & RSS",
            link: "https://example.com/swift-rss",
            summary: "Kurze Zusammenfassung",
            content: "<h2>Untertitel</h2><p>Ein <strong>lesbarer</strong> Absatz.</p>"
        )

        let text = ArticleExportService.text(
            for: ArticleExportSnapshot(article: article),
            options: ArticleExportOptions(format: .plainText, includesMetadata: true)
        )

        #expect(text.contains("Swift & RSS"))
        #expect(text.contains("Untertitel"))
        #expect(text.contains("Ein lesbarer Absatz."))
        #expect(!text.contains("# Swift & RSS"))
        #expect(!text.contains("<strong>"))
    }

    @Test func htmlExportEscapedTitelUndMetadaten() {
        let article = Article(
            title: "Swift <RSS>",
            link: "https://example.com/swift-rss",
            summary: "Kurze Zusammenfassung",
            content: "<p>Ein <strong>lesbarer</strong> Absatz.</p>"
        )

        let html = ArticleExportService.text(
            for: ArticleExportSnapshot(article: article),
            options: ArticleExportOptions(format: .html, includesMetadata: true)
        )

        #expect(html.contains("<!doctype html>"))
        #expect(html.contains("<title>Swift &lt;RSS&gt;</title>"))
        #expect(html.contains("<h1>Swift &lt;RSS&gt;</h1>"))
        #expect(html.contains("<p>Link: <a href=\"https://example.com/swift-rss\">https://example.com/swift-rss</a></p>"))
        #expect(html.contains("<strong>lesbarer</strong>"))
    }

    @Test func htmlExportRendertUnsichereMetadatenLinksNurAlsText() {
        let article = Article(
            title: "Unsicherer Link",
            link: "javascript:alert(1)",
            content: "<p>Artikeltext</p>"
        )

        let html = ArticleExportService.text(
            for: ArticleExportSnapshot(article: article),
            options: ArticleExportOptions(format: .html, includesMetadata: true)
        )

        #expect(!html.contains("href=\"javascript:alert(1)\""))
        #expect(html.contains("<p>Link: javascript:alert(1)</p>"))
    }

    @Test func htmlExportErhaeltSichereArtikelbilder() {
        let article = Article(
            title: "Bild",
            content: #"<p>Intro</p><img src="https://example.com/photo.jpg" alt="Foto" onclick="bad()">"#
        )

        let html = ArticleExportService.text(
            for: ArticleExportSnapshot(article: article),
            options: ArticleExportOptions(format: .html, includesMetadata: false)
        )

        #expect(html.contains(#"<img src="https://example.com/photo.jpg">"#))
        #expect(!html.contains("onclick"))
    }

    @Test func offlineBildPaketSchreibtMarkdownPfadeRelativUndZipptAssets() async throws {
        let article = Article(
            title: "Bilder Export",
            content: #"<p>Intro</p><img src="https://example.com/photo.jpg">"#
        )
        let imageURL = try #require(URL(string: "https://example.com/photo.jpg"))
        let package = await ArticleExportPackageBuilder.package(
            for: ArticleExportSnapshot(article: article),
            options: ArticleExportOptions(format: .markdown, includesMetadata: false),
            includesOfflineImages: true,
            imageLoader: StubArticleExportImageLoader(payloads: [
                imageURL: Data([0x01, 0x02, 0x03])
            ])
        )

        #expect(package.filename == "Bilder Export.zip")
        #expect(package.text.contains("![](Pictures/image-1.jpg)"))
        #expect(package.assets.map(\.path) == ["Pictures/image-1.jpg"])
        #expect(package.failedImageURLs.isEmpty)
        #expect(package.archiveData.contains(Data("Bilder Export.md".utf8)))
        #expect(package.archiveData.contains(Data("Pictures/image-1.jpg".utf8)))
    }

    @Test func offlineBildPaketSchreibtHTMLPfadeRelativUndMeldetFehlendeBilder() async throws {
        let article = Article(
            title: "HTML Export",
            content: #"<p>Intro</p><img src="https://example.com/photo.jpg"><img src="https://example.com/missing.png">"#
        )
        let imageURL = try #require(URL(string: "https://example.com/photo.jpg"))
        let missingURL = try #require(URL(string: "https://example.com/missing.png"))
        let package = await ArticleExportPackageBuilder.package(
            for: ArticleExportSnapshot(article: article),
            options: ArticleExportOptions(format: .html, includesMetadata: false),
            includesOfflineImages: true,
            imageLoader: StubArticleExportImageLoader(payloads: [
                imageURL: Data([0x04, 0x05, 0x06])
            ])
        )

        #expect(package.filename == "HTML Export.zip")
        #expect(package.text.contains(#"<img src="Pictures/image-1.jpg">"#))
        #expect(package.text.contains(#"<img src="https://example.com/missing.png">"#))
        #expect(package.assets.map(\.path) == ["Pictures/image-1.jpg"])
        #expect(package.failedImageURLs == [missingURL])
    }

    @Test func offlineBildPaketMeldetFortschrittFuerBildDownloadUndArchiv() async throws {
        let article = Article(
            title: "Status Export",
            content: #"<p>Intro</p><img src="https://example.com/photo.jpg">"#
        )
        let imageURL = try #require(URL(string: "https://example.com/photo.jpg"))
        var progressEvents: [ArticleExportPackageProgress] = []

        _ = await ArticleExportPackageBuilder.package(
            for: ArticleExportSnapshot(article: article),
            options: ArticleExportOptions(format: .html, includesMetadata: false),
            includesOfflineImages: true,
            imageLoader: StubArticleExportImageLoader(payloads: [
                imageURL: Data([0x01])
            ]),
            progress: { progressEvents.append($0) }
        )

        #expect(progressEvents == [
            .preparingDocument,
            .downloadingImage(current: 1, total: 1),
            .creatingArchive
        ])
    }

    @Test func artikelExportDocumentSchreibtZipDatenUnveraendert() throws {
        let archiveData = Data([0x50, 0x4b, 0x03, 0x04])
        let document = ArticleExportDocument(data: archiveData)

        #expect(document.data == archiveData)
    }

    @Test func metadatenEnthaltenAutorFeedUndTags() {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Example Feed")
        let article = Article(
            title: "Metadaten",
            link: "https://example.com/a",
            author: "Ada",
            feed: feed
        )
        article.tags = [
            Tag(name: "Swift"),
            Tag(name: "RSS")
        ]

        let markdown = ArticleExportService.text(
            for: ArticleExportSnapshot(article: article),
            options: ArticleExportOptions(format: .markdown, includesMetadata: true)
        )

        #expect(markdown.contains("Autor: Ada"))
        #expect(markdown.contains("Feed: Example Feed"))
        #expect(markdown.contains("Tags: RSS, Swift"))
    }

    @Test func defaultFilenameNutztGewaehltesFormat() {
        let snapshot = ArticleExportSnapshot(article: Article(title: "Swift/RSS: Was ist neu?"))

        #expect(ArticleExportService.defaultFilename(for: snapshot, format: .markdown) == "Swift-RSS- Was ist neu.md")
        #expect(ArticleExportService.defaultFilename(for: snapshot, format: .plainText) == "Swift-RSS- Was ist neu.txt")
        #expect(ArticleExportService.defaultFilename(for: snapshot, format: .html) == "Swift-RSS- Was ist neu.html")
    }
}

private struct StubArticleExportImageLoader: ArticleExportImageDataLoading {
    let payloads: [URL: Data]

    func data(from url: URL) async throws -> Data {
        guard let data = payloads[url] else {
            throw URLError(.fileDoesNotExist)
        }

        return data
    }
}
