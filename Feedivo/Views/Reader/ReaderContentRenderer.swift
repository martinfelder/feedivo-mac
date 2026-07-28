import Foundation

/// Ein einzelnes, zusammenhängendes Textstück innerhalb eines Reader-Content-Blocks
/// mit optionaler Inline-Formatierung (Fett/Kursiv/Link/Farbe). Reiner, SwiftUI-
/// unabhängiger Sendable-Werttyp — die Umwandlung in `AttributedString` passiert
/// erst an der Rendering-Grenze (siehe ReaderInlineRun+AttributedString.swift).
struct ReaderInlineRun: Equatable, Sendable {
    let text: String
    let isBold: Bool
    let isItalic: Bool
    let linkURL: URL?
    let colorHex: String?
}

enum ReaderContentBlock: Equatable, Sendable {
    case paragraph([ReaderInlineRun])
    case heading([ReaderInlineRun])
    case quote([ReaderInlineRun])
    case listItem([ReaderInlineRun])
    case image(urlString: String)

    /// Erzeugt einen einzelnen, unformatierten Run — deckt den bisherigen
    /// "reiner Text ohne Formatierung"-Fall ab, damit bestehender Aufrufcode wie
    /// `.paragraph("Text")` unverändert kompiliert.
    static func paragraph(_ text: String) -> Self {
        .paragraph([ReaderInlineRun(text: text, isBold: false, isItalic: false, linkURL: nil, colorHex: nil)])
    }

    static func heading(_ text: String) -> Self {
        .heading([ReaderInlineRun(text: text, isBold: false, isItalic: false, linkURL: nil, colorHex: nil)])
    }

    static func quote(_ text: String) -> Self {
        .quote([ReaderInlineRun(text: text, isBold: false, isItalic: false, linkURL: nil, colorHex: nil)])
    }

    static func listItem(_ text: String) -> Self {
        .listItem([ReaderInlineRun(text: text, isBold: false, isItalic: false, linkURL: nil, colorHex: nil)])
    }
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
        case .paragraph(let runs):
            return compactID(prefix: "p", value: runs.plainText)
        case .heading(let runs):
            return compactID(prefix: "h", value: runs.plainText)
        case .quote(let runs):
            return compactID(prefix: "q", value: runs.plainText)
        case .listItem(let runs):
            return compactID(prefix: "li", value: runs.plainText)
        case .image(let urlString):
            return compactID(prefix: "img", value: urlString)
        }
    }

    private func compactID(prefix: String, value: String) -> String {
        "\(prefix):\(value.count):\(value.hashValue)"
    }
}

extension Array where Element == ReaderInlineRun {
    /// Reiner, verketteter Text ohne Formatierungsinformation — Basis für die
    /// inhaltsbasierte Block-Identität oben.
    var plainText: String {
        map(\.text).joined()
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
    private static let inlineTagExpression = try! NSRegularExpression(
        pattern: #"<(a|b|strong|i|em|span)\b([^>]*)>(.*?)</\1>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let hrefAttributeExpression = try! NSRegularExpression(
        pattern: #"(?:^|\s)href\s*=\s*["']([^"']*)["']"#,
        options: [.caseInsensitive]
    )
    private static let styleAttributeExpression = try! NSRegularExpression(
        pattern: #"style\s*=\s*["']([^"']*)["']"#,
        options: [.caseInsensitive]
    )
    // Reihenfolge der Alternative bewusst 6-stellig VOR 3-stellig: NSRegularExpression
    // wählt bei einer Alternation die erste passende Variante an dieser Position, nicht
    // die längste — bei "3 vor 6" hätte "#FF0000" nur "#FF0" (die ersten 3 Hex-Ziffern)
    // gematcht, der Rest wäre abgeschnitten worden.
    private static let colorDeclarationExpression = try! NSRegularExpression(
        pattern: #"(?:^|;)\s*color\s*:\s*(#[0-9A-Fa-f]{6}|#[0-9A-Fa-f]{3})"#,
        options: [.caseInsensitive]
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

        // Fallback ohne erkannte Block-Tags (z. B. loser summary-Text): liefert nur
        // unformatierte Runs, siehe Limitations-Hinweis auf splitIntoParagraphRuns.
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

        for runs in splitIntoParagraphRuns(fromPreparedHTML: htmlWithoutListContainers) where runs.plainText != "•" {
            blocks.append(.paragraph(runs))
        }
    }

    private static func appendTextBlock(from html: String, tag: String, to blocks: inout [ReaderContentBlock]) {
        let runs = inlineRuns(fromHTML: html)
        guard !runs.isEmpty else {
            return
        }

        if tag.hasPrefix("h") {
            blocks.append(.heading(runs))
            return
        }

        switch tag {
        case "blockquote":
            blocks.append(.quote(runs))
        case "li":
            blocks.append(.listItem(runs))
        default:
            blocks.append(.paragraph(runs))
        }
    }

    /// Zerlegt HTML mit `<br>`/Block-Grenzen in mehrere Absätze (ein Aufruf von
    /// `paragraphs(fromPreparedHTML:)` liefert die Zeilengrenzen als reine
    /// Strings).
    ///
    /// Achtung: erkennt KEINE Inline-Formatierung — `paragraphs(fromPreparedHTML:)`
    /// hat den Text bereits über `htmlToPlainText` zu reinem Text reduziert, die
    /// Tags sind an dieser Stelle bereits weg. Betrifft vor allem den
    /// summary-Fallback (RSS <description>) und jeden Text außerhalb von
    /// <p>/<div>/<h*>/<li>/<blockquote> — für solchen Text bleibt Fett/Kursiv/
    /// Link/Farbe unerkannt. Bewusst akzeptierte Limitation dieser ersten
    /// Ausbaustufe, kein Bug.
    private static func splitIntoParagraphRuns(fromPreparedHTML htmlOrText: String) -> [[ReaderInlineRun]] {
        paragraphs(fromPreparedHTML: htmlOrText).map { [ReaderInlineRun(text: $0, isBold: false, isItalic: false, linkURL: nil, colorHex: nil)] }
    }

    /// Erkennt Inline-Formatierung (Fett/Kursiv/Link/Farbe) in HTML-Text und
    /// zerlegt ihn in Runs. Eine Ebene Verschachtelung unterschiedlicher Tags
    /// wird unterstützt (z. B. `<b><a href="...">Link</a></b>`); Verschachtelung
    /// des GLEICHEN Tags (`<b>a<b>b</b>c</b>`) nicht — Regex kann
    /// Verschachtelungstiefe nicht zählen (bestehende Einschränkung dieser
    /// Datei, analog zu `structuredBlockExpression` auf Block-Ebene).
    static func inlineRuns(fromHTML html: String) -> [ReaderInlineRun] {
        var runs = rawInlineRuns(fromHTML: html)
        trimOuterWhitespace(&runs)
        return runs
    }

    /// Maximale Rekursionstiefe für verschachtelte Inline-Tags — schützt gegen
    /// ungetrautes Feed-HTML mit exzessiv tiefer Verschachtelung. Ab dieser
    /// Tiefe wird der verbleibende Inhalt als reiner Text behandelt statt
    /// weiter zu rekursieren.
    private static let maxInlineNestingDepth = 8

    private static func rawInlineRuns(fromHTML html: String, depth: Int = 0) -> [ReaderInlineRun] {
        guard depth < maxInlineNestingDepth else {
            return plainInlineRuns(fromHTML: html)
        }

        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        let matches = inlineTagExpression.matches(in: html, range: range)
        guard !matches.isEmpty else {
            return plainInlineRuns(fromHTML: html)
        }

        var runs: [ReaderInlineRun] = []
        var currentIndex = html.startIndex

        for match in matches {
            guard
                let matchRange = Range(match.range, in: html),
                let tagRange = Range(match.range(at: 1), in: html),
                let attributesRange = Range(match.range(at: 2), in: html),
                let innerRange = Range(match.range(at: 3), in: html)
            else {
                continue
            }

            runs.append(contentsOf: plainInlineRuns(fromHTML: String(html[currentIndex ..< matchRange.lowerBound])))

            let tag = String(html[tagRange]).lowercased()
            let attributes = String(html[attributesRange])
            let innerRuns = rawInlineRuns(fromHTML: String(html[innerRange]), depth: depth + 1)
            runs.append(contentsOf: applyingInlineStyle(tag: tag, attributes: attributes, to: innerRuns))

            currentIndex = matchRange.upperBound
        }

        runs.append(contentsOf: plainInlineRuns(fromHTML: String(html[currentIndex ..< html.endIndex])))
        return runs
    }

    private static func plainInlineRuns(fromHTML html: String) -> [ReaderInlineRun] {
        let text = normalizedInlineWhitespace(htmlToPlainText(html))
        guard !text.isEmpty else {
            return []
        }
        return [ReaderInlineRun(text: text, isBold: false, isItalic: false, linkURL: nil, colorHex: nil)]
    }

    private static func applyingInlineStyle(
        tag: String,
        attributes: String,
        to innerRuns: [ReaderInlineRun]
    ) -> [ReaderInlineRun] {
        guard !innerRuns.isEmpty else {
            return []
        }

        let isBold = tag == "b" || tag == "strong"
        let isItalic = tag == "i" || tag == "em"
        let linkURL = tag == "a" ? safeLinkURL(fromAttributes: attributes) : nil
        let styleColorHex = colorHex(fromAttributes: attributes)

        return innerRuns.map { run in
            ReaderInlineRun(
                text: run.text,
                isBold: run.isBold || isBold,
                isItalic: run.isItalic || isItalic,
                linkURL: run.linkURL ?? linkURL,
                colorHex: run.colorHex ?? styleColorHex
            )
        }
    }

    private static func safeLinkURL(fromAttributes attributes: String) -> URL? {
        guard
            let match = hrefAttributeExpression.firstMatch(in: attributes, range: NSRange(attributes.startIndex ..< attributes.endIndex, in: attributes)),
            let hrefRange = Range(match.range(at: 1), in: attributes)
        else {
            return nil
        }

        let value = String(attributes[hrefRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: value),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return nil
        }

        return url
    }

    private static func colorHex(fromAttributes attributes: String) -> String? {
        guard
            let styleMatch = styleAttributeExpression.firstMatch(in: attributes, range: NSRange(attributes.startIndex ..< attributes.endIndex, in: attributes)),
            let styleValueRange = Range(styleMatch.range(at: 1), in: attributes)
        else {
            return nil
        }

        let styleValue = String(attributes[styleValueRange])
        guard
            let colorMatch = colorDeclarationExpression.firstMatch(in: styleValue, range: NSRange(styleValue.startIndex ..< styleValue.endIndex, in: styleValue)),
            let colorRange = Range(colorMatch.range(at: 1), in: styleValue)
        else {
            return nil
        }

        return String(styleValue[colorRange]).uppercased()
    }

    /// Wie `normalizedWhitespace`, aber ohne die Außenränder zu trimmen — das
    /// übernimmt `trimOuterWhitespace` über die gesamte Run-Liste hinweg, sonst
    /// gingen Leerzeichen an Segmentgrenzen verloren (z. B. "Text vor
    /// <b>fett</b> danach").
    private static func normalizedInlineWhitespace(_ text: String) -> String {
        var result = ""
        var previousWasWhitespace = false
        for character in text {
            if character.isWhitespace {
                if !previousWasWhitespace {
                    result.append(" ")
                }
                previousWasWhitespace = true
            } else {
                result.append(character)
                previousWasWhitespace = false
            }
        }
        return result
    }

    private static func trimOuterWhitespace(_ runs: inout [ReaderInlineRun]) {
        // Läuft in einer Schleife: das Entfernen leerer Runs (z. B. der reine
        // Leerzeichen-Run zwischen "<p> " und "<b>fett</b>") kann einen neuen,
        // bis dahin inneren Run zum neuen ersten/letzten Run machen, der selbst
        // noch führende/nachgestellte Leerzeichen trägt ("<p> <b> fett </b> </p>"
        // soll am Ende genau "fett" ergeben, nicht " fett "). Bricht ab, sobald
        // sich nichts mehr ändert.
        var previousCount = -1
        while !runs.isEmpty && runs.count != previousCount {
            previousCount = runs.count

            if let first = runs.first {
                runs[0] = ReaderInlineRun(
                    text: String(first.text.drop { $0 == " " }),
                    isBold: first.isBold,
                    isItalic: first.isItalic,
                    linkURL: first.linkURL,
                    colorHex: first.colorHex
                )
            }

            if let last = runs.last {
                let trimmedText = String(String(last.text.reversed()).drop { $0 == " " }.reversed())
                runs[runs.count - 1] = ReaderInlineRun(
                    text: trimmedText,
                    isBold: last.isBold,
                    isItalic: last.isItalic,
                    linkURL: last.linkURL,
                    colorHex: last.colorHex
                )
            }

            runs.removeAll { $0.text.isEmpty }
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

    // Nicht mehr `private`: wird auch für Vorschautexte (Artikelliste, Suche)
    // außerhalb der strukturierten Block-Darstellung genutzt.
    static func htmlToPlainText(_ html: String) -> String {
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
