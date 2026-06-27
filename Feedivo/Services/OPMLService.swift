import Foundation

struct OPMLFeed: Equatable {
    let title: String
    let xmlURL: String
    let htmlURL: String?
    let folderName: String?
    let description: String?
    let tagNames: [String]

    init(
        title: String,
        xmlURL: String,
        htmlURL: String?,
        folderName: String?,
        description: String? = nil,
        tagNames: [String] = []
    ) {
        self.title = title
        self.xmlURL = xmlURL
        self.htmlURL = htmlURL
        self.folderName = folderName
        self.description = description
        self.tagNames = tagNames
    }
}

struct OPMLExportOptions: Equatable {
    var includesFolders = true
    var includesTags = false
    var includesDescriptions = false
}

enum OPMLServiceError: Error, Equatable, LocalizedError {
    case invalidXML
    case noFeedsFound

    var errorDescription: String? {
        switch self {
        case .invalidXML:
            String(localized: "opml.error.invalidXML")
        case .noFeedsFound:
            String(localized: "opml.error.noFeedsFound")
        }
    }
}

enum OPMLService {

    static func parseFeeds(from data: Data) throws -> [OPMLFeed] {
        let parserDelegate = OPMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate

        guard parser.parse(), parser.parserError == nil else {
            throw OPMLServiceError.invalidXML
        }

        guard !parserDelegate.feeds.isEmpty else {
            throw OPMLServiceError.noFeedsFound
        }

        return parserDelegate.feeds
    }

    static func exportFeeds(
        _ feeds: [OPMLFeed],
        options: OPMLExportOptions = OPMLExportOptions()
    ) -> String {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<opml version="2.0">"#,
            "  <head>",
            "    <title>Feedivo Subscriptions</title>",
            "  </head>",
            "  <body>"
        ]

        if options.includesFolders {
            appendGroupedFeeds(feeds, to: &lines, options: options)
        } else {
            for feed in feeds {
                lines.append(outlineLine(for: feed, indent: "    ", options: options))
            }
        }

        lines.append("  </body>")
        lines.append("</opml>")

        return lines.joined(separator: "\n")
    }

    static func defaultExportFilename(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        return "Feedivo-Export-\(formatter.string(from: date)).opml"
    }

    private static func appendGroupedFeeds(
        _ feeds: [OPMLFeed],
        to lines: inout [String],
        options: OPMLExportOptions
    ) {
        // Feeds pro Ordner in einem Durchlauf gruppieren statt pro Ordner die
        // gesamte Feed-Liste zu filtern (zuvor O(Ordner × Feeds), jetzt O(Feeds)).
        // Einfügereihenfolge der Ordner = erstes Auftreten in `feeds`.
        var groupedByFolder: [(name: String, feeds: [OPMLFeed])] = []
        var folderIndex: [String: Int] = [:]
        var feedsWithoutFolder: [OPMLFeed] = []

        for feed in feeds {
            guard let folderName = trimmed(feed.folderName) else {
                feedsWithoutFolder.append(feed)
                continue
            }

            if let index = folderIndex[folderName] {
                groupedByFolder[index].feeds.append(feed)
            } else {
                folderIndex[folderName] = groupedByFolder.count
                groupedByFolder.append((name: folderName, feeds: [feed]))
            }
        }

        for (folderName, folderFeeds) in groupedByFolder {
            lines.append("    <outline text=\"\(escaped(folderName))\">")
            for folderFeed in folderFeeds {
                lines.append(outlineLine(for: folderFeed, indent: "      ", options: options))
            }
            lines.append("    </outline>")
        }

        for feed in feedsWithoutFolder {
            lines.append(outlineLine(for: feed, indent: "    ", options: options))
        }
    }

    private static func outlineLine(
        for feed: OPMLFeed,
        indent: String,
        options: OPMLExportOptions
    ) -> String {
        var attributes = [
            "text=\"\(escaped(feed.title))\"",
            "title=\"\(escaped(feed.title))\"",
            #"type="rss""#,
            "xmlUrl=\"\(escaped(feed.xmlURL))\""
        ]

        if let htmlURL = trimmed(feed.htmlURL) {
            attributes.append("htmlUrl=\"\(escaped(htmlURL))\"")
        }

        if options.includesTags {
            let tagNames = feed.tagNames.compactMap { value in
                trimmed(value)
            }
            if !tagNames.isEmpty {
                attributes.append("category=\"\(escaped(tagNames.joined(separator: ",")))\"")
            }
        }

        if options.includesDescriptions,
           let description = trimmed(feed.description) {
            attributes.append("description=\"\(escaped(description))\"")
        }

        return "\(indent)<outline \(attributes.joined(separator: " ")) />"
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedValue.isEmpty
        else {
            return nil
        }

        return trimmedValue
    }
}

private final class OPMLParserDelegate: NSObject, XMLParserDelegate {
    private var folderStack: [String] = []
    private var outlineStack: [OutlineKind] = []

    var feeds: [OPMLFeed] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "outline" else {
            return
        }

        if let xmlURL = trimmed(attributeDict["xmlUrl"] ?? attributeDict["xmlURL"]) {
            let title = trimmed(attributeDict["title"])
                ?? trimmed(attributeDict["text"])
                ?? xmlURL
            feeds.append(
                OPMLFeed(
                    title: title,
                    xmlURL: xmlURL,
                    htmlURL: trimmed(attributeDict["htmlUrl"] ?? attributeDict["htmlURL"]),
                    folderName: folderStack.last
                )
            )
            outlineStack.append(.feed)
            return
        }

        if let folderName = trimmed(attributeDict["title"] ?? attributeDict["text"]) {
            folderStack.append(folderName)
            outlineStack.append(.folder)
        } else {
            outlineStack.append(.ignored)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "outline",
              let outlineKind = outlineStack.popLast()
        else {
            return
        }

        if outlineKind == .folder {
            _ = folderStack.popLast()
        }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedValue.isEmpty
        else {
            return nil
        }

        return trimmedValue
    }
}

private enum OutlineKind {
    case folder
    case feed
    case ignored
}
