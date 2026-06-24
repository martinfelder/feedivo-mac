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
}
