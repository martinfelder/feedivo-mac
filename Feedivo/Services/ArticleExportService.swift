import Foundation

struct ArticleExportSnapshot {
    let title: String
    let link: String?
    let summary: String?
    let content: String?
    let publishedAt: Date?
    let offlineState: ArticleOfflineState
    let offlineContent: String?

    init(article: Article) {
        self.title = article.title
        self.link = article.link
        self.summary = article.summary
        self.content = article.content
        self.publishedAt = article.publishedAt
        self.offlineState = article.offlineState
        self.offlineContent = article.offlineContent
    }
}

enum ArticleExportService {
    static func markdown(for article: Article) -> String {
        markdown(for: ArticleExportSnapshot(article: article))
    }

    static func markdown(for snapshot: ArticleExportSnapshot) -> String {
        var lines: [String] = [
            "# \(singleLine(snapshot.title))",
            ""
        ]

        let metadataLines = metadataLines(for: snapshot)
        if !metadataLines.isEmpty {
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

    static func defaultFilename(for article: Article) -> String {
        defaultFilename(forTitle: article.title)
    }

    static func defaultFilename(for snapshot: ArticleExportSnapshot) -> String {
        defaultFilename(forTitle: snapshot.title)
    }

    private static func defaultFilename(forTitle title: String) -> String {
        let sanitizedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: forbiddenFilenameCharacters)
            .joined(separator: "-")
            .replacingOccurrences(of: #"-{2,}"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- "))

        let baseName = sanitizedTitle.isEmpty ? "Artikel" : String(sanitizedTitle.prefix(80))
        return "\(baseName).md"
    }

    private static var forbiddenFilenameCharacters: CharacterSet {
        var characters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        characters.formUnion(.newlines)
        return characters
    }

    private static func metadataLines(for snapshot: ArticleExportSnapshot) -> [String] {
        var lines: [String] = []

        if let publishedAt = snapshot.publishedAt {
            lines.append("Veröffentlicht: \(publishedDateFormatter.string(from: publishedAt))")
        }

        if let link = normalizedText(snapshot.link) {
            lines.append("Link: \(link)")
        }

        return lines
    }

    private static let publishedDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

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
        text = text.replacingOccurrences(
            of: #"<(script|style)\b[^>]*>.*?</\1>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
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

    private static func replacingImages(in html: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"<img[^>]+src\s*=\s*["']([^"']+)["'][^>]*>"#,
            options: [.caseInsensitive]
        ) else {
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

        decoded = replacingNumericEntities(in: decoded, pattern: #"&#(\d+);"#, radix: 10)
        decoded = replacingNumericEntities(in: decoded, pattern: #"&#x([0-9a-fA-F]+);"#, radix: 16)
        return decoded
    }

    private static func replacingNumericEntities(in text: String, pattern: String, radix: Int) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
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
