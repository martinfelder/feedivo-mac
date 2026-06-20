import AppKit
import Foundation

enum ReaderContentBlock: Equatable {
    case paragraph(String)
    case heading(String)
    case quote(String)
    case listItem(String)
    case image(urlString: String)
}

enum ReaderContentRenderer {
    static func blocks(summary: String?, content: String?, fallbackImageURL: String?) -> [ReaderContentBlock] {
        let source = preferredText(content: content, summary: summary)
        let imageURLs = imageURLs(inHTML: source)
        let textBlocks = structuredTextBlocks(from: source)

        let imageBlocks: [ReaderContentBlock]
        if imageURLs.isEmpty, let fallbackImageURL, !fallbackImageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            imageBlocks = [.image(urlString: fallbackImageURL)]
        } else {
            imageBlocks = imageURLs.map { .image(urlString: $0) }
        }

        return imageBlocks + textBlocks
    }

    private static func preferredText(content: String?, summary: String?) -> String {
        if let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return content
        }

        return summary ?? ""
    }

    private static func structuredTextBlocks(from htmlOrText: String) -> [ReaderContentBlock] {
        let withoutImages = htmlOrText.replacingOccurrences(
            of: #"<img\b[^>]*>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        if let blocks = structuredHTMLBlocks(from: withoutImages) {
            return blocks
        }

        return paragraphs(fromPreparedHTML: withoutImages).map { .paragraph($0) }
    }

    private static func structuredHTMLBlocks(from html: String) -> [ReaderContentBlock]? {
        guard html.contains("<") else {
            return nil
        }

        let pattern = #"<(h[1-6]|blockquote|li|p|div)\b[^>]*>(.*?)</\1>"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        let matches = expression.matches(in: html, range: range)
        guard !matches.isEmpty else {
            return nil
        }

        return matches.compactMap { match in
            guard
                let tagRange = Range(match.range(at: 1), in: html),
                let contentRange = Range(match.range(at: 2), in: html)
            else {
                return nil
            }

            let tag = String(html[tagRange]).lowercased()
            let text = normalizedWhitespace(htmlToPlainText(String(html[contentRange])))
            guard !text.isEmpty else {
                return nil
            }

            if tag.hasPrefix("h") {
                return .heading(text)
            }

            switch tag {
            case "blockquote":
                return .quote(text)
            case "li":
                return .listItem(text)
            default:
                return .paragraph(text)
            }
        }
    }

    private static func paragraphs(fromPreparedHTML htmlOrText: String) -> [String] {
        let prepared = htmlOrText
            .replacingOccurrences(of: #"</(p|div|h[1-6]|li|blockquote)>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])

        let plainText = htmlToPlainText(prepared)
        return plainText
            .components(separatedBy: .newlines)
            .map(normalizedWhitespace)
            .filter { !$0.isEmpty }
    }

    private static func htmlToPlainText(_ html: String) -> String {
        guard html.contains("<"), let data = html.data(using: .utf8) else {
            return html
        }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        guard let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        }

        return attributedString.string
    }

    private static func imageURLs(inHTML html: String) -> [String] {
        let pattern = #"<img[^>]+src\s*=\s*["']([^"']+)["']"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        return expression.matches(in: html, range: range).compactMap { match in
            guard let srcRange = Range(match.range(at: 1), in: html) else {
                return nil
            }

            let value = String(html[srcRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
    }

    nonisolated private static func normalizedWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
