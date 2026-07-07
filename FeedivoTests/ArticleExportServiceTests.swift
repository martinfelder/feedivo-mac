import Foundation
import PDFKit
import Testing
@testable import Feedivo

struct ArticleExportServiceTests {
    @Test func markdownExportEnthaeltMetadatenUndLesbarenArtikeltext() {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                title: "Swift & RSS",
                link: "https://example.com/swift-rss",
                summary: "Kurze Zusammenfassung",
                content: "<h2>Untertitel</h2><p>Ein <strong>lesbarer</strong> Absatz.</p><blockquote>Zitat</blockquote><ul><li>Erster Punkt</li></ul>",
                publishedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        let markdown = ArticleExportService.markdown(for: snapshot)

        #expect(markdown.contains("# Swift & RSS"))
        #expect(markdown.contains("Link: https://example.com/swift-rss"))
        #expect(markdown.contains("## Untertitel"))
        #expect(markdown.contains("Ein lesbarer Absatz."))
        #expect(markdown.contains("> Zitat"))
        #expect(markdown.contains("- Erster Punkt"))
    }

    @Test func markdownExportBevorzugtOfflineContentVorFeedContentUndSummary() {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                title: "Offline",
                summary: "Summary",
                content: "Feed Content",
                offlineStateRaw: ArticleOfflineState.fullText.rawValue,
                offlineContent: "<p>Gespeicherter Volltext</p>"
            )
        )

        let markdown = ArticleExportService.markdown(for: snapshot)

        #expect(markdown.contains("Gespeicherter Volltext"))
        #expect(!markdown.contains("Feed Content"))
        #expect(!markdown.contains("Summary"))
    }

    @Test func markdownExportVerarbeitetUnvollstaendigesHTMLOhneAppKitHTMLImporter() {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                title: "Kaputtes HTML",
                content: "<article><p>Absatz &amp; Text<script>window.crash()</script><blockquote>Zitat"
            )
        )

        let markdown = ArticleExportService.markdown(for: snapshot)

        #expect(markdown.contains("Absatz & Text"))
        #expect(markdown.contains("> Zitat"))
        #expect(!markdown.contains("window.crash"))
    }

    @Test func defaultFilenameBereinigtArtikeltitelFuerDateisystem() {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(title: "Swift/RSS: Was ist neu?")
        )

        #expect(ArticleExportService.defaultFilename(for: snapshot) == "Swift-RSS- Was ist neu.md")
    }

    @Test func markdownExportKannMetadatenAusblenden() {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                title: "Swift & RSS",
                link: "https://example.com/swift-rss",
                summary: "Kurze Zusammenfassung",
                content: "<p>Artikeltext</p>",
                publishedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        let text = ArticleExportService.text(
            for: snapshot,
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
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                title: "Swift & RSS",
                link: "https://example.com/swift-rss",
                summary: "Kurze Zusammenfassung",
                content: "<h2>Untertitel</h2><p>Ein <strong>lesbarer</strong> Absatz.</p>"
            )
        )

        let text = ArticleExportService.text(
            for: snapshot,
            options: ArticleExportOptions(format: .plainText, includesMetadata: true)
        )

        #expect(text.contains("Swift & RSS"))
        #expect(text.contains("Untertitel"))
        #expect(text.contains("Ein lesbarer Absatz."))
        #expect(!text.contains("# Swift & RSS"))
        #expect(!text.contains("<strong>"))
    }

    @Test func htmlExportEscapedTitelUndMetadaten() {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                title: "Swift <RSS>",
                link: "https://example.com/swift-rss",
                summary: "Kurze Zusammenfassung",
                content: "<p>Ein <strong>lesbarer</strong> Absatz.</p>"
            )
        )

        let html = ArticleExportService.text(
            for: snapshot,
            options: ArticleExportOptions(format: .html, includesMetadata: true)
        )

        #expect(html.contains("<!doctype html>"))
        #expect(html.contains("<title>Swift &lt;RSS&gt;</title>"))
        #expect(html.contains("<h1>Swift &lt;RSS&gt;</h1>"))
        #expect(html.contains("<p>Link: <a href=\"https://example.com/swift-rss\">https://example.com/swift-rss</a></p>"))
        #expect(html.contains("<strong>lesbarer</strong>"))
    }

    @Test func htmlExportRendertUnsichereMetadatenLinksNurAlsText() {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                title: "Unsicherer Link",
                link: "javascript:alert(1)",
                content: "<p>Artikeltext</p>"
            )
        )

        let html = ArticleExportService.text(
            for: snapshot,
            options: ArticleExportOptions(format: .html, includesMetadata: true)
        )

        #expect(!html.contains("href=\"javascript:alert(1)\""))
        #expect(html.contains("<p>Link: javascript:alert(1)</p>"))
    }

    @Test func htmlExportErhaeltSichereArtikelbilder() {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                title: "Bild",
                content: #"<p>Intro</p><img src="https://example.com/photo.jpg" alt="Foto" onclick="bad()">"#
            )
        )

        let html = ArticleExportService.text(
            for: snapshot,
            options: ArticleExportOptions(format: .html, includesMetadata: false)
        )

        #expect(html.contains(#"<img src="https://example.com/photo.jpg">"#))
        #expect(!html.contains("onclick"))
    }

    @Test func offlineBildPaketSchreibtMarkdownPfadeRelativUndZipptAssets() async throws {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                title: "Bilder Export",
                content: #"<p>Intro</p><img src="https://example.com/photo.jpg">"#
            )
        )
        let imageURL = try #require(URL(string: "https://example.com/photo.jpg"))
        let package = await ArticleExportPackageBuilder.package(
            for: snapshot,
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
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                title: "HTML Export",
                content: #"<p>Intro</p><img src="https://example.com/photo.jpg"><img src="https://example.com/missing.png">"#
            )
        )
        let imageURL = try #require(URL(string: "https://example.com/photo.jpg"))
        let missingURL = try #require(URL(string: "https://example.com/missing.png"))
        let package = await ArticleExportPackageBuilder.package(
            for: snapshot,
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
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                title: "Status Export",
                content: #"<p>Intro</p><img src="https://example.com/photo.jpg">"#
            )
        )
        let imageURL = try #require(URL(string: "https://example.com/photo.jpg"))
        var progressEvents: [ArticleExportPackageProgress] = []

        _ = await ArticleExportPackageBuilder.package(
            for: snapshot,
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

    @Test func offlineBildPaketLaedtBilderParallelMitDrosselungUndErhaeltReihenfolge() async throws {
        // Mehr Bilder als das Drossel-Limit, damit ohne Drosselung alle gleichzeitig laden.
        let count = 12
        let imageTags = (0 ..< count).map { offset in
            "<img src=\"https://example.com/bild-\(offset).png\">"
        }.joined()
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(title: "Export", content: "<p>Intro</p>\(imageTags)")
        )

        let loader = ConcurrencyTrackingArticleExportImageLoader()
        let package = await ArticleExportPackageBuilder.package(
            for: snapshot,
            options: ArticleExportOptions(format: .html, includesMetadata: false),
            includesOfflineImages: true,
            imageLoader: loader
        )

        // Gleichzeitigkeit wird auf das Drossel-Limit beschränkt (nicht alle 12 auf einmal).
        #expect(loader.maxInFlight <= ArticleExportPackageBuilder.maxConcurrentImageDownloads, "maxInFlight=\(loader.maxInFlight) – Gleichzeitigkeit nicht gedrosselt")
        // Alle Bilder wurden ausgelöst und geladen.
        #expect(loader.completedCount == count)
        #expect(package.failedImageURLs.isEmpty)
        // Asset-Pfade behalten die Dokumentenreihenfolge (image-1 … image-12).
        let expectedPaths = (1 ... count).map { "Pictures/image-\($0).png" }
        #expect(package.assets.map(\.path) == expectedPaths)
    }

    @Test func artikelExportDocumentSchreibtZipDatenUnveraendert() throws {
        let archiveData = Data([0x50, 0x4b, 0x03, 0x04])
        let document = ArticleExportDocument(data: archiveData)

        #expect(document.data == archiveData)
    }

    @Test func artikelExportDocumentSchreibtBinaereDokumentdatenUnveraendert() throws {
        let documentData = Data("%PDF-1.7\n".utf8)
        let document = ArticleExportDocument(data: documentData)

        #expect(document.data == documentData)
    }

    @Test func pdfExportErzeugtGueltigePDFDaten() {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                title: "PDF Export",
                link: "https://example.com/pdf",
                content: "<h2>Untertitel</h2><p>Ein lesbarer Absatz.</p>"
            )
        )

        let data = ArticleExportService.data(
            for: snapshot,
            options: ArticleExportOptions(format: .pdf, includesMetadata: true)
        )

        #expect(data.starts(with: Data("%PDF".utf8)))
        #expect(data.count > 500)
    }

    @Test func pdfHTMLVerwendetReaderTypografieUndEingebetteteBilder() {
        let style = ArticlePDFExportStyle(
            titleFontFamily: "Literata",
            bodyFontFamily: "Inter",
            titleFontIsBold: true,
            bodyFontIsBold: false,
            titleFontSize: 33,
            bodyFontSize: 19,
            lineSpacing: 8,
            titleLineSpacing: 4,
            contentWidth: 680
        )

        let html = ArticlePDFExportRenderer.html(
            fromExportedHTML: #"<body><h1>PDF mit Bild</h1><p>Intro</p><img src="Pictures/image-1.png"><p>Outro</p></body>"#,
            style: style,
            assets: [
                ArticleExportPackageAsset(path: "Pictures/image-1.png", data: Data([0x01, 0x02]))
            ]
        )

        #expect(html.contains("font-family: Inter"))
        #expect(html.contains("font-size: 19px"))
        #expect(html.contains("line-height: 27px"))
        #expect(html.contains("font-family: Literata"))
        #expect(html.contains("font-size: 33px"))
        #expect(html.contains(#"<img src="data:image/png;base64,AQI=">"#))
        #expect(html.contains("Intro"))
        #expect(html.contains("Outro"))
    }

    @Test func pdfHTMLEnthaeltReaderHeaderUndSichtbareMetadaten() {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                feedTitle: "Example Feed",
                title: "PDF Metadaten",
                link: "https://example.com/pdf",
                content: "<p>Ein lesbarer Absatz.</p>",
                author: "Ada",
                publishedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            tagNames: ["Swift", "RSS"]
        )

        let html = ArticlePDFExportRenderer.html(
            for: snapshot,
            options: ArticleExportOptions(format: .pdf, includesMetadata: true),
            style: .default,
            assets: []
        )

        #expect(html.contains(#"<p class="reader-metadata">Example Feed"#))
        #expect(html.contains(#"<h1 class="reader-title">PDF Metadaten</h1>"#))
        #expect(html.contains(#"<section class="export-metadata""#))
        #expect(html.contains("<strong>Autor:</strong> Ada"))
        #expect(html.contains("<strong>Veröffentlicht:</strong> 2023-11-14T22:13:20Z"))
        #expect(html.contains("<strong>Feed:</strong> Example Feed"))
        #expect(html.contains("<strong>Link:</strong> <a href=\"https://example.com/pdf\">https://example.com/pdf</a>"))
        #expect(html.contains("<strong>Tags:</strong> RSS, Swift"))
        #expect(html.contains("Ein lesbarer Absatz."))
    }

    @Test func pdfPaketLaedtArtikelbilderAutomatischUndBleibtEinPDFDokument() async throws {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                title: "PDF Bilder",
                content: #"<p>Intro</p><img src="https://example.com/photo.png"><p>Outro</p>"#
            )
        )
        let imageURL = try #require(URL(string: "https://example.com/photo.png"))
        var progressEvents: [ArticleExportPackageProgress] = []

        let package = await ArticleExportPackageBuilder.package(
            for: snapshot,
            options: ArticleExportOptions(format: .pdf, includesMetadata: false),
            includesOfflineImages: false,
            imageLoader: StubArticleExportImageLoader(payloads: [
                imageURL: Data([0x01, 0x02, 0x03])
            ]),
            progress: { progressEvents.append($0) }
        )

        #expect(package.filename == "PDF Bilder.pdf")
        #expect(package.contentType == .document)
        #expect(package.archiveData.starts(with: Data("%PDF".utf8)))
        #expect(package.assets.map(\.path) == ["Pictures/image-1.png"])
        #expect(package.failedImageURLs.isEmpty)
        #expect(progressEvents == [
            .preparingDocument,
            .downloadingImage(current: 1, total: 1),
            .creatingArchive
        ])
    }

    @Test func pdfExportPaginatesLangeArtikelUeberMehrereSeiten() {
        let paragraphs = (1 ... 180)
            .map { "<p>Absatz \($0): Dies ist bewusst langer Exporttext für die PDF-Paginierung.</p>" }
            .joined()
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(title: "Langer PDF Export", content: paragraphs)
        )

        let data = ArticleExportService.data(
            for: snapshot,
            options: ArticleExportOptions(format: .pdf, includesMetadata: false)
        )

        #expect(pdfPageCount(in: data) > 1)
    }

    @Test func pdfExportBehältLesereihenfolgeUndStartetObenAufErsterSeite() throws {
        let paragraphs = (1 ... 120)
            .map { "<p>Absatz-\($0) Lesereihenfolge im PDF Export.</p>" }
            .joined()
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(title: "PDF Reihenfolge", content: paragraphs)
        )
        let data = ArticleExportService.data(
            for: snapshot,
            options: ArticleExportOptions(format: .pdf, includesMetadata: false)
        )
        let document = try #require(PDFDocument(data: data))
        let firstPage = try #require(document.page(at: 0))
        let lastPage = try #require(document.page(at: document.pageCount - 1))
        let firstPageText = firstPage.string ?? ""
        let lastPageText = lastPage.string ?? ""
        let titleSelection = try #require(document.findString("PDF Reihenfolge", withOptions: []).first)
        let titleBounds = titleSelection.bounds(for: firstPage)
        let pageBounds = firstPage.bounds(for: .mediaBox)

        #expect(firstPageText.contains("PDF Reihenfolge"))
        #expect(firstPageText.contains("Absatz-1"))
        #expect(!firstPageText.contains("Absatz-120"))
        #expect(lastPageText.contains("Absatz-120"))
        #expect(titleBounds.midY > pageBounds.height * 0.65)
    }

    @Test func docxExportErzeugtOpenXMLDokumentMitArtikeltext() {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                title: "DOCX & Export",
                link: "https://example.com/docx",
                content: "<p>Ein <strong>lesbarer</strong> Absatz.</p><script>bad()</script>"
            )
        )

        let data = ArticleExportService.data(
            for: snapshot,
            options: ArticleExportOptions(format: .docx, includesMetadata: true)
        )
        let archiveText = String(decoding: data, as: UTF8.self)

        #expect(data.starts(with: Data([0x50, 0x4b, 0x03, 0x04])))
        #expect(archiveText.contains("[Content_Types].xml"))
        #expect(archiveText.contains("word/document.xml"))
        #expect(archiveText.contains("DOCX &amp; Export"))
        #expect(archiveText.contains("Ein lesbarer Absatz."))
        #expect(!archiveText.contains("bad()"))
    }

    @Test func packageBuilderGibtPDFAlsNormalesDokumentZurueck() async {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(title: "PDF Paket", content: "<p>Artikeltext</p>")
        )

        let package = await ArticleExportPackageBuilder.package(
            for: snapshot,
            options: ArticleExportOptions(format: .pdf, includesMetadata: false),
            includesOfflineImages: true
        )

        #expect(package.filename == "PDF Paket.pdf")
        #expect(package.contentType == .document)
        #expect(package.archiveData.starts(with: Data("%PDF".utf8)))
    }

    @Test func packageBuilderGibtDOCXAlsNormalesDokumentZurueck() async {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(title: "DOCX Paket", content: "<p>Artikeltext</p>")
        )

        let package = await ArticleExportPackageBuilder.package(
            for: snapshot,
            options: ArticleExportOptions(format: .docx, includesMetadata: false),
            includesOfflineImages: true
        )

        #expect(package.filename == "DOCX Paket.docx")
        #expect(package.contentType == .document)
        #expect(package.archiveData.starts(with: Data([0x50, 0x4b, 0x03, 0x04])))
    }

    @Test func metadatenEnthaltenAutorFeedUndTags() {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(
                feedTitle: "Example Feed",
                title: "Metadaten",
                link: "https://example.com/a",
                author: "Ada"
            ),
            tagNames: ["Swift", "RSS"]
        )

        let markdown = ArticleExportService.text(
            for: snapshot,
            options: ArticleExportOptions(format: .markdown, includesMetadata: true)
        )

        #expect(markdown.contains("Autor: Ada"))
        #expect(markdown.contains("Feed: Example Feed"))
        #expect(markdown.contains("Tags: RSS, Swift"))
    }

    @Test func defaultFilenameNutztGewaehltesFormat() {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: makeReaderSnapshot(title: "Swift/RSS: Was ist neu?")
        )

        #expect(ArticleExportService.defaultFilename(for: snapshot, format: .markdown) == "Swift-RSS- Was ist neu.md")
        #expect(ArticleExportService.defaultFilename(for: snapshot, format: .plainText) == "Swift-RSS- Was ist neu.txt")
        #expect(ArticleExportService.defaultFilename(for: snapshot, format: .html) == "Swift-RSS- Was ist neu.html")
        #expect(ArticleExportService.defaultFilename(for: snapshot, format: .pdf) == "Swift-RSS- Was ist neu.pdf")
        #expect(ArticleExportService.defaultFilename(for: snapshot, format: .docx) == "Swift-RSS- Was ist neu.docx")
    }

    @Test func sqliteExportSnapshotNutztOfflineVolltextUndTags() {
        let snapshot = ArticleExportSnapshot(
            sqliteSnapshot: ArticleReaderSnapshot(
                id: "article-1",
                feedID: "feed-1",
                feedTitle: "SQLite Feed",
                title: "SQLite Artikel",
                link: "https://example.com/article",
                summary: "Kurzfassung",
                content: "<p>Feed-Inhalt</p>",
                imageURL: nil,
                author: "Autorin",
                publishedAt: Date(timeIntervalSince1970: 1_000),
                arrivedAt: Date(timeIntervalSince1970: 1_100),
                estimatedReadingMinutes: nil,
                isRead: false,
                isStarred: false,
                isArchived: false,
                isHidden: false,
                offlineStateRaw: ArticleOfflineState.fullText.rawValue,
                offlineContent: "<article>Offline-Volltext</article>"
            ),
            tagNames: ["Swift", "RSS"]
        )

        let markdown = ArticleExportService.markdown(for: snapshot)

        #expect(markdown.contains("Offline-Volltext"))
        #expect(!markdown.contains("Feed-Inhalt"))
        #expect(markdown.contains("SQLite Feed"))
        #expect(markdown.contains("RSS, Swift"))
    }

    @Test func exportDialogBietetVorerstNurMarkdownTextUndHTMLAn() {
        #expect(ArticleExportFormat.dialogFormats == [.markdown, .plainText, .html])
        #expect(!ArticleExportFormat.dialogFormats.contains(.pdf))
        #expect(!ArticleExportFormat.dialogFormats.contains(.docx))
    }
}

/// Baut ein `ArticleReaderSnapshot` mit sinnvollen Defaults für Export-Tests.
/// Nur die im jeweiligen Test tatsächlich relevanten Felder werden übergeben —
/// der Rest bekommt neutrale/leere Werte, die vom Export-Code nicht ausgewertet
/// werden (z. B. `id`, `feedID`, `arrivedAt`).
private func makeReaderSnapshot(
    feedTitle: String = "",
    title: String,
    link: String? = nil,
    summary: String? = nil,
    content: String? = nil,
    imageURL: String? = nil,
    author: String? = nil,
    publishedAt: Date? = nil,
    offlineStateRaw: String = ArticleOfflineState.none.rawValue,
    offlineContent: String? = nil
) -> ArticleReaderSnapshot {
    ArticleReaderSnapshot(
        id: "article-1",
        feedID: "feed-1",
        feedTitle: feedTitle,
        title: title,
        link: link,
        summary: summary,
        content: content,
        imageURL: imageURL,
        author: author,
        publishedAt: publishedAt,
        arrivedAt: Date(timeIntervalSince1970: 0),
        estimatedReadingMinutes: nil,
        isRead: false,
        isStarred: false,
        isArchived: false,
        isHidden: false,
        offlineStateRaw: offlineStateRaw,
        offlineContent: offlineContent
    )
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

/// Zählt, wie viele Ladevorgänge gleichzeitig aktiv sind, um eine Drosselung
/// der Gleichzeitigkeit im Export-Builder verifizieren zu können. Analog zum
/// `ConcurrencyTrackingImageDataLoader` der `ImageCacheServiceTests`.
private final class ConcurrencyTrackingArticleExportImageLoader: ArticleExportImageDataLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = 0
    private(set) var maxInFlight = 0
    private(set) var completedCount = 0

    nonisolated init() {}

    func data(from url: URL) async throws -> Data {
        lock.lock()
        inFlight += 1
        if inFlight > maxInFlight {
            maxInFlight = inFlight
        }
        lock.unlock()

        try await Task.sleep(nanoseconds: 30_000_000)

        lock.lock()
        inFlight -= 1
        completedCount += 1
        lock.unlock()

        return Data(repeating: 1, count: 8)
    }
}

private func pdfPageCount(in data: Data) -> Int {
    String(decoding: data, as: UTF8.self)
        .components(separatedBy: "/Type /Page")
        .count - 1
}
