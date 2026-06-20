import Foundation

struct OPMLFeed: Equatable {
    let title: String
    let xmlURL: String
    let htmlURL: String?
    let folderName: String?
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

    static func exportFeeds(_ feeds: [OPMLFeed]) -> String {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<opml version="2.0">"#,
            "  <head>",
            "    <title>Feedivo Subscriptions</title>",
            "  </head>",
            "  <body>"
        ]

        var emittedFolders: [String] = []
        let feedsWithoutFolder = feeds.filter { trimmed($0.folderName) == nil }

        for feed in feeds {
            guard let folderName = trimmed(feed.folderName),
                  !emittedFolders.contains(folderName)
            else {
                continue
            }

            emittedFolders.append(folderName)
            lines.append("    <outline text=\"\(escaped(folderName))\">")

            for folderFeed in feeds.filter({ trimmed($0.folderName) == folderName }) {
                lines.append(outlineLine(for: folderFeed, indent: "      "))
            }

            lines.append("    </outline>")
        }

        for feed in feedsWithoutFolder {
            lines.append(outlineLine(for: feed, indent: "    "))
        }

        lines.append("  </body>")
        lines.append("</opml>")

        return lines.joined(separator: "\n")
    }

    private static func outlineLine(for feed: OPMLFeed, indent: String) -> String {
        var attributes = [
            "text=\"\(escaped(feed.title))\"",
            "title=\"\(escaped(feed.title))\"",
            #"type="rss""#,
            "xmlUrl=\"\(escaped(feed.xmlURL))\""
        ]

        if let htmlURL = trimmed(feed.htmlURL) {
            attributes.append("htmlUrl=\"\(escaped(htmlURL))\"")
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
