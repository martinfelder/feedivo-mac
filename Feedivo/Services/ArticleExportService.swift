import Foundation
import UniformTypeIdentifiers

enum ArticleExportFormat: String, CaseIterable, Identifiable {
    case markdown
    case plainText
    case html
    case pdf
    case docx

    static let dialogFormats: [ArticleExportFormat] = [
        .markdown,
        .plainText,
        .html
    ]

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .markdown:
            "md"
        case .plainText:
            "txt"
        case .html:
            "html"
        case .pdf:
            "pdf"
        case .docx:
            "docx"
        }
    }

    var contentType: UTType {
        switch self {
        case .markdown:
            .markdownText
        case .plainText:
            .plainText
        case .html:
            .html
        case .pdf:
            .pdf
        case .docx:
            .docxDocument
        }
    }
}

struct ArticleExportOptions: Equatable {
    var format: ArticleExportFormat = .markdown
    var includesMetadata = true
}

struct ArticleExportSnapshot {
    let title: String
    let link: String?
    let summary: String?
    let content: String?
    let author: String?
    let publishedAt: Date?
    let feedTitle: String?
    let tagNames: [String]
    let offlineState: ArticleOfflineState
    let offlineContent: String?

    init(article: Article) {
        self.title = article.title
        self.link = article.link
        self.summary = article.summary
        self.content = article.content
        self.author = article.author
        self.publishedAt = article.publishedAt
        self.feedTitle = article.feed?.title
        self.tagNames = (article.tags ?? []).map(\.name).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        self.offlineState = article.offlineState
        self.offlineContent = article.offlineContent
    }
}

enum ArticleExportService {
    static func markdown(for article: Article) -> String {
        markdown(for: ArticleExportSnapshot(article: article))
    }

    static func markdown(for snapshot: ArticleExportSnapshot) -> String {
        text(for: snapshot, options: ArticleExportOptions(format: .markdown, includesMetadata: true))
    }

    static func text(for snapshot: ArticleExportSnapshot, options: ArticleExportOptions) -> String {
        switch options.format {
        case .markdown:
            markdownText(for: snapshot, includesMetadata: options.includesMetadata)
        case .plainText:
            plainText(for: snapshot, includesMetadata: options.includesMetadata)
        case .html:
            htmlText(for: snapshot, includesMetadata: options.includesMetadata)
        case .pdf, .docx:
            plainText(for: snapshot, includesMetadata: options.includesMetadata)
        }
    }

    static func data(for snapshot: ArticleExportSnapshot, options: ArticleExportOptions) -> Data {
        switch options.format {
        case .markdown, .plainText, .html:
            Data(text(for: snapshot, options: options).utf8)
        case .pdf:
            ArticlePDFExportRenderer.data(for: snapshot, options: options)
        case .docx:
            ArticleDOCXExportRenderer.data(for: snapshot, options: options)
        }
    }

    static func previewText(for snapshot: ArticleExportSnapshot, options: ArticleExportOptions) -> String {
        previewText(from: text(for: snapshot, options: options))
    }

    static func previewText(from text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .prefix(40)
        return lines.joined(separator: "\n")
    }

    static func defaultFilename(for article: Article) -> String {
        defaultFilename(for: ArticleExportSnapshot(article: article), format: .markdown)
    }

    static func defaultFilename(for snapshot: ArticleExportSnapshot) -> String {
        defaultFilename(for: snapshot, format: .markdown)
    }

    static func defaultFilename(for snapshot: ArticleExportSnapshot, format: ArticleExportFormat) -> String {
        "\(defaultFilenameBase(forTitle: snapshot.title)).\(format.fileExtension)"
    }

    private static func markdownText(for snapshot: ArticleExportSnapshot, includesMetadata: Bool) -> String {
        var lines: [String] = [
            "# \(singleLine(snapshot.title))",
            ""
        ]

        let metadataLines = includesMetadata ? metadataLines(for: snapshot) : []
        if includesMetadata, !metadataLines.isEmpty {
            lines.append(contentsOf: metadataLines)
            lines.append("")
            lines.append("---")
            lines.append("")
        }

        let bodyLines = markdownBodyLines(from: preferredContent(for: snapshot) ?? snapshot.summary)

        if bodyLines.isEmpty {
            return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        }

        lines.append(contentsOf: bodyLines)
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func plainText(for snapshot: ArticleExportSnapshot, includesMetadata: Bool) -> String {
        var lines: [String] = [
            singleLine(snapshot.title),
            ""
        ]

        let metadataLines = includesMetadata ? metadataLines(for: snapshot) : []
        if includesMetadata, !metadataLines.isEmpty {
            lines.append(contentsOf: metadataLines)
            lines.append("")
        }

        lines.append(contentsOf: plainBodyLines(from: preferredContent(for: snapshot) ?? snapshot.summary))
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func htmlText(for snapshot: ArticleExportSnapshot, includesMetadata: Bool) -> String {
        let title = singleLine(snapshot.title)
        var lines: [String] = [
            "<!doctype html>",
            "<html lang=\"de\">",
            "<head>",
            "<meta charset=\"utf-8\">",
            "<title>\(escapedHTML(title))</title>",
            "</head>",
            "<body>",
            "<article>",
            "<h1>\(escapedHTML(title))</h1>"
        ]

        if includesMetadata {
            let metadataParagraphs = htmlMetadataParagraphs(for: snapshot)
            if !metadataParagraphs.isEmpty {
                lines.append("<section>")
                lines.append(contentsOf: metadataParagraphs)
                lines.append("</section>")
            }
        }

        if let body = normalizedText(preferredContent(for: snapshot) ?? snapshot.summary) {
            lines.append(sanitizedHTMLBody(from: body))
        }

        lines.append(contentsOf: [
            "</article>",
            "</body>",
            "</html>"
        ])

        return lines.joined(separator: "\n") + "\n"
    }

    private static func defaultFilenameBase(forTitle title: String) -> String {
        let sanitizedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: forbiddenFilenameCharacters)
            .joined(separator: "-")
            .replacingOccurrences(of: #"-{2,}"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- "))

        let baseName = sanitizedTitle.isEmpty ? "Artikel" : String(sanitizedTitle.prefix(80))
        return baseName
    }

    private static var forbiddenFilenameCharacters: CharacterSet {
        var characters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        characters.formUnion(.newlines)
        return characters
    }

    private static func metadataLines(for snapshot: ArticleExportSnapshot) -> [String] {
        var lines: [String] = []

        if let author = normalizedText(snapshot.author) {
            lines.append("Autor: \(author)")
        }

        if let publishedAt = snapshot.publishedAt {
            lines.append("Veröffentlicht: \(publishedDateFormatter.string(from: publishedAt))")
        }

        if let feedTitle = normalizedText(snapshot.feedTitle) {
            lines.append("Feed: \(feedTitle)")
        }

        if let link = normalizedText(snapshot.link) {
            lines.append("Link: \(link)")
        }

        let tagNames = snapshot.tagNames.compactMap { normalizedText($0) }
        if !tagNames.isEmpty {
            lines.append("Tags: \(tagNames.joined(separator: ", "))")
        }

        return lines
    }

    private static func htmlMetadataParagraphs(for snapshot: ArticleExportSnapshot) -> [String] {
        var paragraphs: [String] = []

        if let author = normalizedText(snapshot.author) {
            paragraphs.append("<p>Autor: \(escapedHTML(author))</p>")
        }

        if let publishedAt = snapshot.publishedAt {
            paragraphs.append("<p>Veröffentlicht: \(escapedHTML(publishedDateFormatter.string(from: publishedAt)))</p>")
        }

        if let feedTitle = normalizedText(snapshot.feedTitle) {
            paragraphs.append("<p>Feed: \(escapedHTML(feedTitle))</p>")
        }

        if let link = normalizedText(snapshot.link) {
            if isSafeLinkTarget(link) {
                paragraphs.append("<p>Link: <a href=\"\(escapedHTMLAttribute(link))\">\(escapedHTML(link))</a></p>")
            } else {
                paragraphs.append("<p>Link: \(escapedHTML(link))</p>")
            }
        }

        let tagNames = snapshot.tagNames.compactMap { normalizedText($0) }
        if !tagNames.isEmpty {
            paragraphs.append("<p>Tags: \(escapedHTML(tagNames.joined(separator: ", ")))</p>")
        }

        return paragraphs
    }

    private static let publishedDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // M7: Reguläre Ausdrücke werden einmal pro App-Lebensdauer kompiliert
    // statt bei jedem Export-Aufruf neu. Die Muster sind konstant und
    // NSRegularExpression ist beim Matchen unveränderlich sowie threadsicher.
    // `try?` liefert nur nil, falls ein festes Literalmuster ungültig wäre —
    // die jeweiligen Aufrufer haben wie bisher einen nil-Fallback-Pfad.
    private static let safeTagExpression: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>"#,
        options: [.caseInsensitive]
    )

    private static let imageTagExpression: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"<img[^>]+src\s*=\s*["']([^"']+)["'][^>]*>"#,
        options: [.caseInsensitive]
    )

    private static let hrefAttributeExpression: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#,
        options: [.caseInsensitive]
    )

    private static let srcAttributeExpression: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#,
        options: [.caseInsensitive]
    )

    private static let numericEntityDecimalExpression: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"&#(\d+);"#
    )

    private static let numericEntityHexExpression: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"&#x([0-9a-fA-F]+);"#
    )

    private static func preferredContent(for snapshot: ArticleExportSnapshot) -> String? {
        if snapshot.offlineState.isAvailable,
           let offlineContent = normalizedText(snapshot.offlineContent) {
            return offlineContent
        }

        return normalizedText(snapshot.content)
    }

    private static func markdownBodyLines(from htmlOrText: String?) -> [String] {
        guard let htmlOrText = normalizedText(htmlOrText) else {
            return []
        }

        var text = htmlOrText
        text = replacingImages(in: text)
        text = removingScriptsAndStyles(from: text)
        text = text.replacingOccurrences(
            of: #"<br\s*/?>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"<h[1-6]\b[^>]*>"#,
            with: "\n## ",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"</h[1-6]>"#,
            with: "\n\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"<blockquote\b[^>]*>"#,
            with: "\n> ",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"</blockquote>"#,
            with: "\n\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"<li\b[^>]*>"#,
            with: "\n- ",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"</li>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"</?(p|div|article|section|ul|ol)\b[^>]*>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
        text = decodedHTMLEntities(in: text)

        return markdownLines(fromPlainText: text)
    }

    private static func plainBodyLines(from htmlOrText: String?) -> [String] {
        guard let htmlOrText = normalizedText(htmlOrText) else {
            return []
        }

        var text = removingScriptsAndStyles(from: htmlOrText)
        text = text.replacingOccurrences(
            of: #"<img[^>]+alt\s*=\s*["']([^"']+)["'][^>]*>"#,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"<br\s*/?>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"</h[1-6]>"#,
            with: "\n\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"<h[1-6]\b[^>]*>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"<li\b[^>]*>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"</li>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"</?(p|div|article|section|ul|ol|blockquote)\b[^>]*>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
        text = decodedHTMLEntities(in: text)

        return markdownLines(fromPlainText: text)
    }

    private static func sanitizedHTMLBody(from htmlOrText: String) -> String {
        var html = removingScriptsAndStyles(from: htmlOrText)
        html = replacingHTMLTagsWithSafeSubset(in: html)
        return html.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removingScriptsAndStyles(from text: String) -> String {
        text.replacingOccurrences(
            of: #"(?is)<(script|style)\b[^>]*>.*?</\1>"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func replacingHTMLTagsWithSafeSubset(in html: String) -> String {
        guard let expression = safeTagExpression else {
            return escapedHTML(html)
        }

        let allowedTags: Set<String> = [
            "a", "blockquote", "br", "code", "div", "em", "h1", "h2", "h3", "h4", "h5", "h6",
            "img", "li", "ol", "p", "pre", "section", "strong", "ul"
        ]

        var result = ""
        var currentIndex = html.startIndex
        let matches = expression.matches(in: html, range: NSRange(html.startIndex ..< html.endIndex, in: html))
        for match in matches {
            guard
                let matchRange = Range(match.range, in: html),
                let slashRange = Range(match.range(at: 1), in: html),
                let tagRange = Range(match.range(at: 2), in: html),
                let attributeRange = Range(match.range(at: 3), in: html)
            else {
                continue
            }

            if currentIndex < matchRange.lowerBound {
                result += escapedHTML(decodedHTMLEntities(in: String(html[currentIndex ..< matchRange.lowerBound])))
            }

            let slash = String(html[slashRange])
            let tag = String(html[tagRange]).lowercased()
            let attributes = String(html[attributeRange])
            let replacement: String

            if !allowedTags.contains(tag) {
                replacement = ""
            } else if tag == "br" {
                replacement = "<br>"
            } else if tag == "img" {
                replacement = slash == "/" ? "" : safeImageTag(from: attributes)
            } else if slash == "/" {
                replacement = "</\(tag)>"
            } else if tag == "a" {
                replacement = safeLinkTag(from: attributes)
            } else {
                replacement = "<\(tag)>"
            }

            result += replacement
            currentIndex = matchRange.upperBound
        }

        if currentIndex < html.endIndex {
            result += escapedHTML(decodedHTMLEntities(in: String(html[currentIndex ..< html.endIndex])))
        }

        return result
    }

    private static func safeLinkTag(from attributes: String) -> String {
        guard
            let href = htmlAttributeValue(expression: hrefAttributeExpression, in: attributes),
            let normalizedHref = normalizedText(decodedHTMLEntities(in: href)),
            isSafeLinkTarget(normalizedHref)
        else {
            return "<a>"
        }

        return "<a href=\"\(escapedHTMLAttribute(normalizedHref))\">"
    }

    private static func safeImageTag(from attributes: String) -> String {
        guard
            let src = htmlAttributeValue(expression: srcAttributeExpression, in: attributes),
            let normalizedSource = normalizedText(decodedHTMLEntities(in: src)),
            isSafeImageSource(normalizedSource)
        else {
            return ""
        }

        return "<img src=\"\(escapedHTMLAttribute(normalizedSource))\">"
    }

    private static func htmlAttributeValue(expression: NSRegularExpression?, in attributes: String) -> String? {
        guard let expression else {
            return nil
        }

        let nsRange = NSRange(attributes.startIndex ..< attributes.endIndex, in: attributes)
        guard let match = expression.firstMatch(in: attributes, range: nsRange) else {
            return nil
        }

        for index in 1 ... 3 {
            let range = match.range(at: index)
            guard range.location != NSNotFound,
                  let valueRange = Range(range, in: attributes)
            else {
                continue
            }

            return String(attributes[valueRange])
        }

        return nil
    }

    private static func isSafeLinkTarget(_ value: String) -> Bool {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased()
        else {
            return false
        }

        return ["http", "https", "mailto"].contains(scheme)
    }

    private static func isSafeImageSource(_ value: String) -> Bool {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased()
        else {
            return false
        }

        return ["http", "https"].contains(scheme)
    }

    private static func replacingImages(in html: String) -> String {
        guard let expression = imageTagExpression else {
            return html
        }

        var result = html
        let matches = expression.matches(in: html, range: NSRange(html.startIndex ..< html.endIndex, in: html))
        for match in matches.reversed() {
            guard
                let matchRange = Range(match.range, in: result),
                let srcRange = Range(match.range(at: 1), in: result)
            else {
                continue
            }

            let urlString = String(result[srcRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            result.replaceSubrange(matchRange, with: urlString.isEmpty ? "" : "\n![](\(urlString))\n\n")
        }

        return result
    }

    private static func markdownLines(fromPlainText text: String) -> [String] {
        var lines: [String] = []
        var previousLineWasBlank = true

        for rawLine in text.components(separatedBy: .newlines) {
            let line = normalizedWhitespace(rawLine)

            if line.isEmpty {
                if !previousLineWasBlank {
                    lines.append("")
                    previousLineWasBlank = true
                }
                continue
            }

            lines.append(line)
            previousLineWasBlank = false
        }

        while lines.last == "" {
            lines.removeLast()
        }

        return lines
    }

    private static func decodedHTMLEntities(in text: String) -> String {
        var decoded = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")

        decoded = replacingNumericEntities(in: decoded, expression: numericEntityDecimalExpression, radix: 10)
        decoded = replacingNumericEntities(in: decoded, expression: numericEntityHexExpression, radix: 16)
        return decoded
    }

    private static func escapedHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapedHTMLAttribute(_ text: String) -> String {
        escapedHTML(text)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func replacingNumericEntities(in text: String, expression: NSRegularExpression?, radix: Int) -> String {
        guard let expression else {
            return text
        }

        var result = text
        let matches = expression.matches(in: text, range: NSRange(text.startIndex ..< text.endIndex, in: text))
        for match in matches.reversed() {
            guard
                let matchRange = Range(match.range, in: result),
                let valueRange = Range(match.range(at: 1), in: result),
                let scalarValue = UInt32(String(result[valueRange]), radix: radix),
                let scalar = UnicodeScalar(scalarValue)
            else {
                continue
            }

            result.replaceSubrange(matchRange, with: String(Character(scalar)))
        }

        return result
    }

    private static func singleLine(_ value: String) -> String {
        normalizedWhitespace(value).isEmpty ? "Artikel" : normalizedWhitespace(value)
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static func normalizedWhitespace(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

enum ArticleExportPreviewRenderer {
    static func htmlForMarkdownPreview(_ markdown: String, assets: [ArticleExportPackageAsset] = []) -> String {
        let body = markdownBodyHTML(from: markdown, assetDataURLs: assetDataURLs(from: assets))

        return """
        <!doctype html>
        <html lang="de">
        <head>
        <meta charset="utf-8">
        <style>
        :root { color-scheme: light dark; }
        body {
            font: -apple-system-body;
            margin: 14px;
            line-height: 1.45;
            color: CanvasText;
            background: transparent;
        }
        h1, h2, h3 {
            line-height: 1.2;
            margin: 0 0 10px;
        }
        h1 { font-size: 24px; }
        h2 { font-size: 19px; margin-top: 18px; }
        h3 { font-size: 16px; margin-top: 16px; }
        p, ul, ol, blockquote { margin: 0 0 12px; }
        ul, ol { padding-left: 22px; }
        blockquote {
            border-left: 3px solid color-mix(in srgb, CanvasText 25%, transparent);
            padding-left: 10px;
            color: color-mix(in srgb, CanvasText 78%, transparent);
        }
        hr {
            border: 0;
            border-top: 1px solid color-mix(in srgb, CanvasText 18%, transparent);
            margin: 16px 0;
        }
        img {
            max-width: 100%;
            height: auto;
        }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    static func htmlForHTMLPreview(_ html: String, assets: [ArticleExportPackageAsset] = []) -> String {
        htmlByReplacingAssetPaths(in: html, assetDataURLs: assetDataURLs(from: assets))
    }

    private static func markdownBodyHTML(from markdown: String, assetDataURLs: [String: String]) -> String {
        var html: [String] = []
        var paragraphLines: [String] = []
        var listItems: [String] = []
        var blockquoteLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            html.append("<p>\(inlineHTML(paragraphLines.joined(separator: " ")))</p>")
            paragraphLines.removeAll()
        }

        func flushList() {
            guard !listItems.isEmpty else { return }
            html.append("<ul>\(listItems.joined())</ul>")
            listItems.removeAll()
        }

        func flushBlockquote() {
            guard !blockquoteLines.isEmpty else { return }
            html.append("<blockquote><p>\(inlineHTML(blockquoteLines.joined(separator: " ")))</p></blockquote>")
            blockquoteLines.removeAll()
        }

        func flushBlocks() {
            flushParagraph()
            flushList()
            flushBlockquote()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            guard !line.isEmpty else {
                flushBlocks()
                continue
            }

            if line == "---" {
                flushBlocks()
                html.append("<hr>")
            } else if line.hasPrefix("### ") {
                flushBlocks()
                html.append("<h3>\(inlineHTML(String(line.dropFirst(4))))</h3>")
            } else if line.hasPrefix("## ") {
                flushBlocks()
                html.append("<h2>\(inlineHTML(String(line.dropFirst(3))))</h2>")
            } else if line.hasPrefix("# ") {
                flushBlocks()
                html.append("<h1>\(inlineHTML(String(line.dropFirst(2))))</h1>")
            } else if line.hasPrefix("- ") {
                flushParagraph()
                flushBlockquote()
                listItems.append("<li>\(inlineHTML(String(line.dropFirst(2))))</li>")
            } else if line.hasPrefix("> ") {
                flushParagraph()
                flushList()
                blockquoteLines.append(String(line.dropFirst(2)))
            } else if line.hasPrefix("![]("), line.hasSuffix(")") {
                flushBlocks()
                let source = String(line.dropFirst(4).dropLast())
                let previewSource = assetDataURLs[source] ?? source
                html.append("<img src=\"\(escapedHTMLAttribute(previewSource))\" alt=\"\">")
            } else {
                flushList()
                flushBlockquote()
                paragraphLines.append(line)
            }
        }

        flushBlocks()
        return html.joined(separator: "\n")
    }

    private static func htmlByReplacingAssetPaths(in html: String, assetDataURLs: [String: String]) -> String {
        assetDataURLs.reduce(html) { partialResult, replacement in
            partialResult.replacingOccurrences(of: replacement.key, with: replacement.value)
        }
    }

    private static func assetDataURLs(from assets: [ArticleExportPackageAsset]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: assets.map { asset in
            let encodedData = asset.data.base64EncodedString()
            return (asset.path, "data:\(mimeType(for: asset.path));base64,\(encodedData)")
        })
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

    private static func inlineHTML(_ text: String) -> String {
        escapedHTML(text)
    }

    private static func escapedHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapedHTMLAttribute(_ text: String) -> String {
        escapedHTML(text)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
