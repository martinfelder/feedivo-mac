import AppKit
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
    static func data(
        for snapshot: ArticleExportSnapshot,
        options: ArticleExportOptions,
        style: ArticlePDFExportStyle = .default,
        assets: [ArticleExportPackageAsset] = []
    ) -> Data {
        data(
            fromHTML: html(
                for: snapshot,
                options: options,
                style: style,
                assets: assets
            )
        )
    }

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

    static func data(fromHTML html: String) -> Data {
        let attributedString = attributedString(fromHTML: html)
        return pdfData(from: attributedString)
    }

    private static func attributedString(fromHTML html: String) -> NSAttributedString {
        let data = Data(html.utf8)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        return (try? NSAttributedString(
            data: data,
            options: options,
            documentAttributes: nil
        )) ?? NSAttributedString(string: html)
    }

    private static func pdfData(from attributedString: NSAttributedString) -> Data {
        let pageSize = CGSize(width: 595, height: 842)
        let pageInsets = NSEdgeInsets(top: 54, left: 54, bottom: 54, right: 54)
        let contentRect = CGRect(
            x: pageInsets.left,
            y: pageInsets.top,
            width: pageSize.width - pageInsets.left - pageInsets.right,
            height: pageSize.height - pageInsets.top - pageInsets.bottom
        )

        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureGlyphs(forCharacterRange: NSRange(location: 0, length: attributedString.length))

        var pageRanges: [NSRange] = []
        var glyphLocation = 0

        while glyphLocation < layoutManager.numberOfGlyphs {
            let textContainer = NSTextContainer(containerSize: contentRect.size)
            textContainer.lineFragmentPadding = 0
            layoutManager.addTextContainer(textContainer)

            let glyphRange = layoutManager.glyphRange(for: textContainer)
            guard glyphRange.length > 0 else {
                break
            }

            pageRanges.append(glyphRange)
            glyphLocation = NSMaxRange(glyphRange)
        }

        if pageRanges.isEmpty {
            pageRanges.append(NSRange(location: 0, length: 0))
        }

        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            return Data()
        }

        for glyphRange in pageRanges {
            context.beginPDFPage(nil)
            context.saveGState()
            NSGraphicsContext.saveGraphicsState()

            context.translateBy(x: 0, y: pageSize.height)
            context.scaleBy(x: 1, y: -1)
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.current = graphicsContext

            NSColor.white.setFill()
            CGRect(origin: .zero, size: pageSize).fill()

            layoutManager.drawBackground(forGlyphRange: glyphRange, at: contentRect.origin)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: contentRect.origin)

            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
            context.endPDFPage()
        }

        context.closePDF()
        return output as Data
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

        return String(html[range])
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
            lines.append(#"<p class="reader-metadata">\#(escapedHTML(readerMetadata))</p>"#)
        }

        if let title = normalizedText(title) {
            lines.append(#"<h1 class="reader-title">\#(escapedHTML(title))</h1>"#)
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
            lines.append("<p><strong>Autor:</strong> \(escapedHTML(author))</p>")
        }

        if let publishedAt = snapshot.publishedAt {
            lines.append("<p><strong>Veröffentlicht:</strong> \(escapedHTML(publishedDateFormatter.string(from: publishedAt)))</p>")
        }

        if let feedTitle = normalizedText(snapshot.feedTitle) {
            lines.append("<p><strong>Feed:</strong> \(escapedHTML(feedTitle))</p>")
        }

        if let link = normalizedText(snapshot.link) {
            if isSafeLinkTarget(link) {
                lines.append("<p><strong>Link:</strong> <a href=\"\(escapedHTMLAttribute(link))\">\(escapedHTML(link))</a></p>")
            } else {
                lines.append("<p><strong>Link:</strong> \(escapedHTML(link))</p>")
            }
        }

        let tagNames = snapshot.tagNames.compactMap { normalizedText($0) }
        if !tagNames.isEmpty {
            lines.append("<p><strong>Tags:</strong> \(escapedHTML(tagNames.joined(separator: ", ")))</p>")
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

    private static func escapedHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func escapedHTMLAttribute(_ text: String) -> String {
        escapedHTML(text).replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func isSafeLinkTarget(_ value: String) -> Bool {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased()
        else {
            return false
        }

        return ["http", "https", "mailto"].contains(scheme)
    }

    private static let publishedDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

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
