import MCP
import Foundation

enum SearchArticlesTool {
    static let definition = Tool(
        name: "search_articles",
        description: """
            Durchsucht Artikel per Volltextsuche und Filtern (Status, Tags, Feed, Zeitraum). \
            Liefert Kurztext, keinen Volltext — für den vollen Inhalt eines Treffers get_article \
            mit der hier zurückgegebenen Artikel-ID aufrufen.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Suchtext, leer lassen für keine Volltextsuche"),
                ]),
                "status": .object([
                    "type": .string("string"),
                    "description": .string("all, unread, read, starred oder archived"),
                    "enum": .array([.string("all"), .string("unread"), .string("read"), .string("starred"), .string("archived")]),
                ]),
                "feedID": .object([
                    "type": .string("string"),
                    "description": .string("Nur Artikel dieses Feeds (optional, ID aus list_feeds)"),
                ]),
                "tagIDs": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Nur Artikel mit einem dieser Tags (optional, IDs aus list_tags)"),
                ]),
                "tagMatchMode": .object([
                    "type": .string("string"),
                    "enum": .array([.string("any"), .string("all")]),
                ]),
                "dateFilter": .object([
                    "type": .string("string"),
                    "enum": .array([.string("anytime"), .string("today"), .string("thisWeek")]),
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Maximale Anzahl Treffer, Standard 50"),
                ]),
            ]),
        ])
    )

    static func call(database: FeedivoMCPServerDatabase, arguments: [String: Value]?) throws -> CallTool.Result {
        var state = ArticleSearchWindowState(searchText: arguments?["query"]?.stringValue ?? "")

        // Ungültige Filterwerte werden bewusst NICHT still verworfen (das würde den
        // Filter unbemerkt entfallen lassen oder auf einen Default zurückfallen),
        // sondern als echter Fehler gemeldet — konsistent zu get_article/
        // get_smart_folder_articles, die unbekannte IDs ebenfalls als isError: true
        // melden.
        if let statusRaw = arguments?["status"]?.stringValue {
            guard let status = ArticleSearchStatusFilter(rawValue: statusRaw) else {
                return .init(content: [.text("Ungültiger Wert für status: \(statusRaw)")], isError: true)
            }
            state.statusFilter = status
        }

        if let feedIDRaw = arguments?["feedID"]?.stringValue {
            guard let feedID = UUID(uuidString: feedIDRaw) else {
                return .init(content: [.text("Ungültiger Wert für feedID: \(feedIDRaw)")], isError: true)
            }
            state.feedID = feedID
        }

        if let tagIDValues = arguments?["tagIDs"]?.arrayValue {
            var tagIDs = Set<UUID>()
            for value in tagIDValues {
                guard let raw = value.stringValue, let tagID = UUID(uuidString: raw) else {
                    return .init(content: [.text("Ungültiger Wert für tagIDs: \(value)")], isError: true)
                }
                tagIDs.insert(tagID)
            }
            state.tagIDs = tagIDs
        }

        if let tagMatchRaw = arguments?["tagMatchMode"]?.stringValue {
            guard let tagMatch = ArticleSearchTagMatchMode(rawValue: tagMatchRaw) else {
                return .init(content: [.text("Ungültiger Wert für tagMatchMode: \(tagMatchRaw)")], isError: true)
            }
            state.tagMatchMode = tagMatch
        }

        if let dateFilterRaw = arguments?["dateFilter"]?.stringValue {
            guard let dateFilter = ArticleSearchDateFilter(rawValue: dateFilterRaw) else {
                return .init(content: [.text("Ungültiger Wert für dateFilter: \(dateFilterRaw)")], isError: true)
            }
            state.dateFilter = dateFilter
        }

        // Obergrenze 200: ein Client könnte sonst z. B. limit: 100000 anfragen und
        // faktisch die komplette Datenbank in eine einzige Antwort schreiben.
        let limit = min(arguments?["limit"]?.intValue ?? 50, 200)

        let articleDatabase = ArticleDatabase(database: database.core)
        let results = try articleDatabase.searchArticles(state: state, includeHidden: false, limit: limit)

        if results.isEmpty {
            return .init(content: [.text("Keine Artikel gefunden.")], isError: false)
        }

        let dateFormatter = ISO8601DateFormatter()
        let lines = results.map { article -> String in
            let statusMarker = article.isRead ? "gelesen" : "ungelesen"
            let starMarker = article.isStarred ? ", ★" : ""
            let dateString = dateFormatter.string(from: article.publishedAt ?? article.arrivedAt)
            // Erst zu Klartext konvertieren, dann kürzen — nicht umgekehrt, sonst
            // könnten HTML-Entities mitten im Kürzungspunkt zerschnitten werden.
            let excerpt = String(HTMLPlainTextConverter.plainText(fromHTML: article.summary ?? "").prefix(200))
            return "[\(article.id)] \(article.title) — \(article.feedTitle) (\(dateString), \(statusMarker)\(starMarker))\n\(excerpt)"
        }
        return .init(content: [.text(lines.joined(separator: "\n\n"))], isError: false)
    }
}
