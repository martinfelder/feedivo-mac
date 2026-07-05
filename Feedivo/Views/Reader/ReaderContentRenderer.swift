import Foundation

enum ReaderContentBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(String)
    case quote(String)
    case listItem(String)
    case image(urlString: String)
}

struct ReaderContentBlockEntry: Identifiable, Equatable, Sendable {
    let id: String
    let index: Int
    let block: ReaderContentBlock

    static func entries(from blocks: [ReaderContentBlock]) -> [ReaderContentBlockEntry] {
        var occurrenceCountsByID: [String: Int] = [:]

        return blocks.enumerated().map { index, block in
            let blockID = block.id
            let occurrence = occurrenceCountsByID[blockID, default: 0]
            occurrenceCountsByID[blockID] = occurrence + 1

            return ReaderContentBlockEntry(
                id: "\(blockID):\(occurrence)",
                index: index,
                block: block
            )
        }
    }
}

extension ReaderContentBlock: Identifiable {
    // Kompakte, inhaltsbasierte Basis-Identität (statt Positions-Index). Früher nutzte
    // ForEach `contentBlocks.indices, id: \.self`. Wenn der Inhalt per Refresh
    // verschoben wurde, blieb die Identität an der Position hängen und veraltete
    // Darstellung/Animationen. ReaderContentBlockEntry ergänzt bei doppelten
    // Blöcken eine Vorkommensnummer, damit SwiftUI eindeutige Listen-IDs erhält.
    var id: String {
        switch self {
        case .paragraph(let text):
            return compactID(prefix: "p", value: text)
        case .heading(let text):
            return compactID(prefix: "h", value: text)
        case .quote(let text):
            return compactID(prefix: "q", value: text)
        case .listItem(let text):
            return compactID(prefix: "li", value: text)
        case .image(let urlString):
            return compactID(prefix: "img", value: urlString)
        }
    }

    private func compactID(prefix: String, value: String) -> String {
        "\(prefix):\(value.count):\(value.hashValue)"
    }
}

enum ReaderContentRenderer {
    private static let structuredBlockExpression = try! NSRegularExpression(
        pattern: #"<img\b[^>]*>|<(h[1-6]|blockquote|li|p|div)\b[^>]*>(.*?)</\1>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let inlineImageExpression = try! NSRegularExpression(
        pattern: #"<img\b[^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let imageSourceExpression = try! NSRegularExpression(
        pattern: #"<img[^>]+src\s*=\s*["']([^"']+)["']"#,
        options: [.caseInsensitive]
    )
    private static let listContainerExpression = try! NSRegularExpression(
        pattern: #"</?(ul|ol)\b[^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let blockClosingExpression = try! NSRegularExpression(
        pattern: #"</(p|div|h[1-6]|li|blockquote)>"#,
        options: [.caseInsensitive]
    )
    private static let lineBreakExpression = try! NSRegularExpression(
        pattern: #"<br\s*/?>"#,
        options: [.caseInsensitive]
    )
    private static let tagExpression = try! NSRegularExpression(
        pattern: #"<[^>]+>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let entityExpression = try! NSRegularExpression(
        pattern: #"&(#x[0-9A-Fa-f]+|#[0-9]+|[A-Za-z][A-Za-z0-9]+);"#,
        options: []
    )

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

        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        let matches = structuredBlockExpression.matches(in: html, range: range)
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
            if isImageHTMLBlock(matchedHTML) {
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

    static func isImageHTMLBlock(_ html: String) -> Bool {
        html.range(of: "<img", options: [.caseInsensitive]) != nil
    }

    private static func appendInlineBlocks(from html: String, tag: String, to blocks: inout [ReaderContentBlock]) {
        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        let matches = inlineImageExpression.matches(in: html, range: range)
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
        let htmlWithoutListContainers = stringByReplacingMatches(
            in: html,
            expression: listContainerExpression,
            replacement: ""
        )

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
        let withBlockBreaks = stringByReplacingMatches(
            in: htmlOrText,
            expression: blockClosingExpression,
            replacement: "\n"
        )
        let prepared = stringByReplacingMatches(
            in: withBlockBreaks,
            expression: lineBreakExpression,
            replacement: "\n"
        )

        let plainText = htmlToPlainText(prepared)
        return plainText
            .components(separatedBy: .newlines)
            .map(normalizedWhitespace)
            .filter { !$0.isEmpty }
    }

    private static func htmlToPlainText(_ html: String) -> String {
        let withLineBreakSpaces = stringByReplacingMatches(
            in: html,
            expression: lineBreakExpression,
            replacement: " "
        )
        let withoutTags = stringByReplacingMatches(
            in: withLineBreakSpaces,
            expression: tagExpression,
            replacement: ""
        )
        return decodedHTMLEntities(in: withoutTags)
    }

    private static func appendImageBlock(from html: String, to blocks: inout [ReaderContentBlock]) {
        guard
            let match = imageSourceExpression.firstMatch(in: html, range: NSRange(html.startIndex ..< html.endIndex, in: html)),
            let srcRange = Range(match.range(at: 1), in: html)
        else {
            return
        }

        let value = String(html[srcRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty, ArticleResourceURLPolicy.isArticleImageURLCandidate(value) {
            blocks.append(.image(urlString: value))
        }
    }

    private static func normalizedImageURL(_ urlString: String?) -> String? {
        guard let urlString else {
            return nil
        }

        let value = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, ArticleResourceURLPolicy.isArticleImageURLCandidate(value) else {
            return nil
        }

        return value
    }

    private static func stringByReplacingMatches(
        in text: String,
        expression: NSRegularExpression,
        replacement: String
    ) -> String {
        expression.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex ..< text.endIndex, in: text),
            withTemplate: replacement
        )
    }

    private static func decodedHTMLEntities(in text: String) -> String {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = entityExpression.matches(in: text, range: range)
        guard !matches.isEmpty else {
            return text
        }

        var decodedText = text
        for match in matches.reversed() {
            let entity = nsText.substring(with: match.range)
            let decodedEntity = decodedHTMLEntity(entity) ?? entity
            if let range = Range(match.range, in: decodedText) {
                decodedText.replaceSubrange(range, with: decodedEntity)
            }
        }

        return decodedText
    }

    private static func decodedHTMLEntity(_ entity: String) -> String? {
        switch entity {
        case "&amp;":
            return "&"
        case "&lt;":
            return "<"
        case "&gt;":
            return ">"
        case "&quot;":
            return "\""
        case "&apos;":
            return "'"
        case "&nbsp;":
            return " "
        case "&ndash;":
            return "–"
        case "&mdash;":
            return "—"
        case "&hellip;":
            return "…"
        case "&copy;":
            return "©"
        case "&reg;":
            return "®"
        case "&trade;":
            return "™"
        default:
            return decodedNumericHTMLEntity(entity)
        }
    }

    private static func decodedNumericHTMLEntity(_ entity: String) -> String? {
        guard entity.hasPrefix("&#"), entity.hasSuffix(";") else {
            return nil
        }

        let value = entity.dropFirst(2).dropLast()
        let scalarValue: UInt32?
        if value.lowercased().hasPrefix("x") {
            scalarValue = UInt32(value.dropFirst(), radix: 16)
        } else {
            scalarValue = UInt32(value, radix: 10)
        }

        guard let scalarValue,
              let scalar = UnicodeScalar(scalarValue)
        else {
            return nil
        }

        return String(Character(scalar))
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
