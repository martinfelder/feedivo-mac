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
