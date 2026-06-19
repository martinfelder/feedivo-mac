import AppKit
import Foundation

enum ReaderContentBlock: Equatable {
    case paragraph(String)
    case image(urlString: String)
}

enum ReaderContentRenderer {
    static func blocks(summary: String?, content: String?, fallbackImageURL: String?) -> [ReaderContentBlock] {
        let source = preferredText(content: content, summary: summary)
        let imageURLs = imageURLs(inHTML: source)
        let paragraphBlocks = paragraphs(from: source).map { ReaderContentBlock.paragraph($0) }

        let imageBlocks: [ReaderContentBlock]
        if imageURLs.isEmpty, let fallbackImageURL, !fallbackImageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            imageBlocks = [.image(urlString: fallbackImageURL)]
        } else {
            imageBlocks = imageURLs.map { .image(urlString: $0) }
        }

        return imageBlocks + paragraphBlocks
    }

    private static func preferredText(content: String?, summary: String?) -> String {
        if let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return content
        }

        return summary ?? ""
    }

    private static func paragraphs(from htmlOrText: String) -> [String] {
        let withoutImages = htmlOrText.replacingOccurrences(
            of: #"<img\b[^>]*>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        let prepared = withoutImages
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

    private static func normalizedWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
