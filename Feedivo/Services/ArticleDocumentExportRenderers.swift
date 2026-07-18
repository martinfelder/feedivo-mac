import Foundation

struct ArticlePDFExportStyle: Equatable, Sendable {
    var titleFontFamily: String
    var bodyFontFamily: String
    var titleFontIsBold: Bool
    var bodyFontIsBold: Bool
    var titleFontSize: Double
    var bodyFontSize: Double
    var lineSpacing: Double
    var titleLineSpacing: Double
    var contentWidth: Double

    nonisolated static let `default` = ArticlePDFExportStyle(
        titleFontFamily: "-apple-system",
        bodyFontFamily: "-apple-system",
        titleFontIsBold: ReaderTypography.defaultTitleFontIsBold,
        bodyFontIsBold: ReaderTypography.defaultBodyFontIsBold,
        titleFontSize: ReaderTypography.defaultTitleFontSize,
        bodyFontSize: ReaderTypography.defaultBodyFontSize,
        lineSpacing: ReaderTypography.defaultLineSpacing,
        titleLineSpacing: ReaderTypography.defaultTitleLineSpacing,
        contentWidth: ReaderTypography.defaultContentWidth
    )
}

enum ArticlePDFExportRenderer {
    static func html(
        for snapshot: ArticleExportSnapshot,
        options: ArticleExportOptions,
        style: ArticlePDFExportStyle,
        assets: [ArticleExportPackageAsset]
    ) -> String {
        let exportedHTML = ArticleExportService.text(
            for: snapshot,
            options: ArticleExportOptions(format: .html, includesMetadata: false)
        )
        return html(
            fromExportedHTML: exportedHTML,
            title: snapshot.title,
            readerMetadata: readerMetadataText(for: snapshot),
            exportMetadata: options.includesMetadata ? exportMetadataHTML(for: snapshot) : nil,
            style: style,
            assets: assets
        )
    }

    static func html(
        fromExportedHTML exportedHTML: String,
        style: ArticlePDFExportStyle,
        assets: [ArticleExportPackageAsset]
    ) -> String {
        html(
            fromExportedHTML: exportedHTML,
            title: nil,
            readerMetadata: nil,
            exportMetadata: nil,
            style: style,
            assets: assets
        )
    }

    private static func html(
        fromExportedHTML exportedHTML: String,
        title: String?,
        readerMetadata: String?,
        exportMetadata: String?,
        style: ArticlePDFExportStyle,
        assets: [ArticleExportPackageAsset]
    ) -> String {
        let body = bodyHTML(from: exportedHTML)
        let bodyWithoutTitle = title == nil ? body : removingFirstH1(from: body)
        let assetDataURLs = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (
                asset.path,
                "data:\(mimeType(for: asset.path));base64,\(asset.data.base64EncodedString())"
            )
        })
        let bodyWithEmbeddedImages = assetDataURLs.reduce(bodyWithoutTitle) { partialResult, replacement in
            partialResult.replacingOccurrences(of: replacement.key, with: replacement.value)
        }

        let bodyFontSize = ReaderTypography.clampedBodyFontSize(style.bodyFontSize)
        let titleFontSize = max(style.titleFontSize, bodyFontSize + 8)
        let metadataFontSize = max(13, (bodyFontSize * 0.75).rounded())
        let lineHeight = bodyFontSize + ReaderTypography.clampedLineSpacing(style.lineSpacing)
        let titleLineHeight = titleFontSize + ReaderTypography.clampedTitleLineSpacing(style.titleLineSpacing)
        let metadataLineHeight = metadataFontSize + 4
        let contentWidth = ReaderTypography.clampedContentWidth(style.contentWidth)
        let headerHTML = readerHeaderHTML(
            title: title,
            readerMetadata: readerMetadata,
            exportMetadata: exportMetadata
        )

        return """
        <!doctype html>
        <html lang="de">
        <head>
        <meta charset="utf-8">
        <style>
        body {
            margin: 0;
            color: #111111;
            background: #ffffff;
            font-family: \(style.bodyFontFamily);
            font-size: \(formattedCSSValue(bodyFontSize))px;
            line-height: \(formattedCSSValue(lineHeight))px;
            font-weight: \(style.bodyFontIsBold ? "700" : "400");
        }
        article {
            max-width: \(formattedCSSValue(contentWidth))px;
        }
        .reader-metadata {
            color: #6f6f76;
            font-size: \(formattedCSSValue(metadataFontSize))px;
            line-height: \(formattedCSSValue(metadataLineHeight))px;
            font-weight: 600;
            margin: 0 0 14px;
        }
        .reader-title, h1 {
            font-family: \(style.titleFontFamily);
            font-size: \(formattedCSSValue(titleFontSize))px;
            line-height: \(formattedCSSValue(titleLineHeight))px;
            font-weight: \(style.titleFontIsBold ? "700" : "600");
            margin: 0 0 22px;
        }
        .export-metadata {
            border-top: 1px solid #dddddd;
            border-bottom: 1px solid #dddddd;
            color: #444444;
            font-size: \(formattedCSSValue(metadataFontSize))px;
            line-height: \(formattedCSSValue(metadataLineHeight))px;
            font-weight: 400;
            margin: 0 0 24px;
            padding: 10px 0;
        }
        .export-metadata p {
            margin: 0 0 6px;
        }
        h2 {
            font-size: \(formattedCSSValue(bodyFontSize + 6))px;
            line-height: \(formattedCSSValue(lineHeight + 4))px;
            margin: 28px 0 10px;
        }
        h3 {
            font-size: \(formattedCSSValue(bodyFontSize + 3))px;
            line-height: \(formattedCSSValue(lineHeight + 2))px;
            margin: 24px 0 8px;
        }
        p, ul, ol, blockquote {
            margin: 0 0 22px;
        }
        ul, ol {
            padding-left: 24px;
        }
        blockquote {
            border-left: 4px solid #d0d0d0;
            color: #444444;
            padding-left: 12px;
        }
        img {
            display: block;
            max-width: 100%;
            height: auto;
            margin: 18px 0;
        }
        a {
            color: #1f5fbf;
            text-decoration: none;
        }
        </style>
        </head>
        <body>
        <article>
        \(headerHTML)
        \(bodyWithEmbeddedImages)
        </article>
        </body>
        </html>
        """
    }

    private static func bodyHTML(from html: String) -> String {
        guard
            let expression = try? NSRegularExpression(
                pattern: #"<body[^>]*>([\s\S]*?)</body>"#,
                options: [.caseInsensitive]
            ),
            let match = expression.firstMatch(in: html, range: NSRange(html.startIndex ..< html.endIndex, in: html)),
            let range = Range(match.range(at: 1), in: html)
        else {
            return html
        }

        return removingOuterArticleWrapper(from: String(html[range]))
    }

    // Die von ArticleExportService.text(for:options: .html) erzeugte Body-HTML wickelt
    // ihren Inhalt bereits in ein eigenes <article>...</article> (fuer den eigenstaendigen
    // HTML-Export gedacht) — diese Datei baut aussen selbst ein neues <article>-Element um
    // headerHTML + body (siehe html(fromExportedHTML:...) unten), daher muss der innere
    // Wrapper hier entfernt werden. Ohne diesen Schritt entstehen verschachtelte
    // <article>-Elemente, und removingFirstH1() findet das Titel-<h1> nicht mehr (es steht
    // dann nicht mehr am Stringanfang) — der Titel erschien dadurch doppelt im PDF/Druck
    // (Live-Bug-Fund 2026-07-17, erst durch echtes WebKit-Rendering sichtbar geworden).
    private static func removingOuterArticleWrapper(from html: String) -> String {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let expression = try? NSRegularExpression(
            pattern: #"^<article[^>]*>([\s\S]*)</article>$"#,
            options: [.caseInsensitive]
        ),
        let match = expression.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex ..< trimmed.endIndex, in: trimmed)),
        let range = Range(match.range(at: 1), in: trimmed)
        else {
            return html
        }

        return String(trimmed[range])
    }

    private static func removingFirstH1(from html: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"^\s*<h1[^>]*>[\s\S]*?</h1>\s*"#,
            options: [.caseInsensitive]
        ) else {
            return html
        }

        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        return expression.stringByReplacingMatches(in: html, range: range, withTemplate: "")
    }

    private static func readerHeaderHTML(title: String?, readerMetadata: String?, exportMetadata: String?) -> String {
        var lines: [String] = []

        if let readerMetadata = normalizedText(readerMetadata) {
            lines.append(#"<p class="reader-metadata">\#(ArticleExportSanitizing.escapedHTML(readerMetadata))</p>"#)
        }

        if let title = normalizedText(title) {
            lines.append(#"<h1 class="reader-title">\#(ArticleExportSanitizing.escapedHTML(title))</h1>"#)
        }

        if let exportMetadata {
            lines.append(exportMetadata)
        }

        return lines.joined(separator: "\n")
    }

    private static func readerMetadataText(for snapshot: ArticleExportSnapshot) -> String? {
        ReaderMetadataFormatter.metadataParts(
            feedName: snapshot.feedTitle,
            readingTime: ReaderMetadataFormatter.readingTimeText(
                content: preferredContent(for: snapshot),
                summary: snapshot.summary
            ),
            publishedAt: snapshot.publishedAt
        )
        .joined(separator: " · ")
    }

    private static func exportMetadataHTML(for snapshot: ArticleExportSnapshot) -> String? {
        var lines: [String] = []

        if let author = normalizedText(snapshot.author) {
            lines.append("<p><strong>Autor:</strong> \(ArticleExportSanitizing.escapedHTML(author))</p>")
        }

        if let publishedAt = snapshot.publishedAt {
            lines.append("<p><strong>Veröffentlicht:</strong> \(ArticleExportSanitizing.escapedHTML(ArticleExportSanitizing.publishedDateFormatter.string(from: publishedAt)))</p>")
        }

        if let feedTitle = normalizedText(snapshot.feedTitle) {
            lines.append("<p><strong>Feed:</strong> \(ArticleExportSanitizing.escapedHTML(feedTitle))</p>")
        }

        if let link = normalizedText(snapshot.link) {
            if ArticleExportSanitizing.isSafeLinkTarget(link) {
                lines.append("<p><strong>Link:</strong> <a href=\"\(ArticleExportSanitizing.escapedHTMLAttribute(link))\">\(ArticleExportSanitizing.escapedHTML(link))</a></p>")
            } else {
                lines.append("<p><strong>Link:</strong> \(ArticleExportSanitizing.escapedHTML(link))</p>")
            }
        }

        let tagNames = snapshot.tagNames.compactMap { normalizedText($0) }
        if !tagNames.isEmpty {
            lines.append("<p><strong>Tags:</strong> \(ArticleExportSanitizing.escapedHTML(tagNames.joined(separator: ", ")))</p>")
        }

        guard !lines.isEmpty else {
            return nil
        }

        return """
        <section class="export-metadata">
        \(lines.joined(separator: "\n"))
        </section>
        """
    }

    private static func preferredContent(for snapshot: ArticleExportSnapshot) -> String? {
        if snapshot.offlineState.isAvailable,
           let offlineContent = normalizedText(snapshot.offlineContent) {
            return offlineContent
        }

        return snapshot.content
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static func formattedCSSValue(_ value: Double) -> String {
        let roundedValue = (value * 10).rounded() / 10
        if roundedValue.rounded() == roundedValue {
            return String(Int(roundedValue))
        }

        return String(roundedValue)
    }

    private static func mimeType(for path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "avif":
            "image/avif"
        case "gif":
            "image/gif"
        case "jpeg", "jpg":
            "image/jpeg"
        case "png":
            "image/png"
        case "svg":
            "image/svg+xml"
        case "webp":
            "image/webp"
        default:
            "application/octet-stream"
        }
    }
}

enum ArticleDOCXExportRenderer {
    static func data(for snapshot: ArticleExportSnapshot, options: ArticleExportOptions) -> Data {
        let text = ArticleExportService.text(
            for: snapshot,
            options: ArticleExportOptions(format: .plainText, includesMetadata: options.includesMetadata)
        )
        let paragraphs = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
        \(paragraphs.map(paragraphXML).joined(separator: "\n"))
            <w:sectPr>
              <w:pgSz w:w="11906" w:h="16838"/>
              <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """

        let files = [
            ArticleExportZIPFile(path: "[Content_Types].xml", data: Data(contentTypesXML.utf8)),
            ArticleExportZIPFile(path: "_rels/.rels", data: Data(rootRelationshipsXML.utf8)),
            ArticleExportZIPFile(path: "word/document.xml", data: Data(documentXML.utf8))
        ]
        return ArticleExportZIPArchive.data(files: files)
    }

    nonisolated private static func paragraphXML(_ text: String) -> String {
        """
            <w:p>
              <w:r>
                <w:t>\(escapedXML(text))</w:t>
              </w:r>
            </w:p>
        """
    }

    nonisolated private static func escapedXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    nonisolated private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """

    nonisolated private static let rootRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """
}
