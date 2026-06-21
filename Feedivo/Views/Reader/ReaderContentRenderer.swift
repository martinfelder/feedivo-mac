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
        let contentBlocks = structuredContentBlocks(from: source)
        let normalizedFallbackImageURL = normalizedImageURL(fallbackImageURL)

        if let normalizedFallbackImageURL {
            return [.image(urlString: normalizedFallbackImageURL)] + contentBlocks.filter {
                $0.imageURL != normalizedFallbackImageURL
            }
        }

        guard let firstImageIndex = contentBlocks.firstIndex(where: \.isImage) else {
            return contentBlocks
        }

        var reorderedBlocks = contentBlocks
        let firstImageBlock = reorderedBlocks.remove(at: firstImageIndex)
        return [firstImageBlock] + reorderedBlocks
    }

    private static func preferredText(content: String?, summary: String?) -> String {
        if let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return content
        }

        return summary ?? ""
    }

    private static func structuredContentBlocks(from htmlOrText: String) -> [ReaderContentBlock] {
        if let blocks = structuredHTMLBlocks(from: htmlOrText) {
            return blocks
        }

        return paragraphs(fromPreparedHTML: htmlOrText).map { .paragraph($0) }
    }

    private static func structuredHTMLBlocks(from html: String) -> [ReaderContentBlock]? {
        guard html.contains("<") else {
            return nil
        }

        let pattern = #"<img\b[^>]*>|<(h[1-6]|blockquote|li|p|div)\b[^>]*>(.*?)</\1>"#
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

        var blocks: [ReaderContentBlock] = []
        var currentIndex = html.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: html) else {
                continue
            }

            appendTextBlocks(
                from: String(html[currentIndex ..< matchRange.lowerBound]),
                to: &blocks
            )

            let matchedHTML = String(html[matchRange])
            if matchedHTML.range(of: #"<img\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                appendImageBlock(from: matchedHTML, to: &blocks)
                currentIndex = matchRange.upperBound
                continue
            }

            guard
                let tagRange = Range(match.range(at: 1), in: html),
                let contentRange = Range(match.range(at: 2), in: html)
            else {
                currentIndex = matchRange.upperBound
                continue
            }

            let tag = String(html[tagRange]).lowercased()
            appendInlineBlocks(
                from: String(html[contentRange]),
                tag: tag,
                to: &blocks
            )
            currentIndex = matchRange.upperBound
        }

        appendTextBlocks(
            from: String(html[currentIndex ..< html.endIndex]),
            to: &blocks
        )

        return blocks
    }

    private static func appendInlineBlocks(from html: String, tag: String, to blocks: inout [ReaderContentBlock]) {
        let pattern = #"<img\b[^>]*>"#
        guard
            let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else {
            appendTextBlock(from: html, tag: tag, to: &blocks)
            return
        }

        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        let matches = expression.matches(in: html, range: range)
        guard !matches.isEmpty else {
            appendTextBlock(from: html, tag: tag, to: &blocks)
            return
        }

        var currentIndex = html.startIndex
        for match in matches {
            guard let matchRange = Range(match.range, in: html) else {
                continue
            }

            appendTextBlock(
                from: String(html[currentIndex ..< matchRange.lowerBound]),
                tag: tag,
                to: &blocks
            )
            appendImageBlock(from: String(html[matchRange]), to: &blocks)
            currentIndex = matchRange.upperBound
        }

        appendTextBlock(
            from: String(html[currentIndex ..< html.endIndex]),
            tag: tag,
            to: &blocks
        )
    }

    private static func appendTextBlocks(from html: String, to blocks: inout [ReaderContentBlock]) {
        let htmlWithoutListContainers = html
            .replacingOccurrences(of: #"</?(ul|ol)\b[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])

        for paragraph in paragraphs(fromPreparedHTML: htmlWithoutListContainers) where paragraph != "•" {
            blocks.append(.paragraph(paragraph))
        }
    }

    private static func appendTextBlock(from html: String, tag: String, to blocks: inout [ReaderContentBlock]) {
        let text = normalizedWhitespace(htmlToPlainText(html))
        guard !text.isEmpty else {
            return
        }

        if tag.hasPrefix("h") {
            blocks.append(.heading(text))
            return
        }

        switch tag {
        case "blockquote":
            blocks.append(.quote(text))
        case "li":
            blocks.append(.listItem(text))
        default:
            blocks.append(.paragraph(text))
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

    private static func appendImageBlock(from html: String, to blocks: inout [ReaderContentBlock]) {
        let pattern = #"<img[^>]+src\s*=\s*["']([^"']+)["']"#
        guard
            let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = expression.firstMatch(in: html, range: NSRange(html.startIndex ..< html.endIndex, in: html)),
            let srcRange = Range(match.range(at: 1), in: html)
        else {
            return
        }

        let value = String(html[srcRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            blocks.append(.image(urlString: value))
        }
    }

    private static func normalizedImageURL(_ urlString: String?) -> String? {
        guard let urlString else {
            return nil
        }

        let value = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    nonisolated private static func normalizedWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension ReaderContentBlock {
    var isImage: Bool {
        if case .image = self {
            return true
        }

        return false
    }

    var imageURL: String? {
        if case .image(let urlString) = self {
            return urlString
        }

        return nil
    }
}
