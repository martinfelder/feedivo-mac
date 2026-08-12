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

        if let statusRaw = arguments?["status"]?.stringValue,
            let status = ArticleSearchStatusFilter(rawValue: statusRaw)
        {
            state.statusFilter = status
        }
        state.feedID = (arguments?["feedID"]?.stringValue).flatMap { UUID(uuidString: $0) }
        if let tagIDStrings = arguments?["tagIDs"]?.arrayValue {
            state.tagIDs = Set(tagIDStrings.compactMap { $0.stringValue.flatMap { UUID(uuidString: $0) } })
        }
        if let tagMatchRaw = arguments?["tagMatchMode"]?.stringValue,
            let tagMatch = ArticleSearchTagMatchMode(rawValue: tagMatchRaw)
        {
            state.tagMatchMode = tagMatch
        }
        if let dateFilterRaw = arguments?["dateFilter"]?.stringValue,
            let dateFilter = ArticleSearchDateFilter(rawValue: dateFilterRaw)
        {
            state.dateFilter = dateFilter
        }
        let limit = arguments?["limit"]?.intValue ?? 50

        let articleDatabase = ArticleDatabase(database: database.core)
        let results = try articleDatabase.searchArticles(state: state, includeHidden: false, limit: limit)

        if results.isEmpty {
            return .init(content: [.text("Keine Artikel gefunden.")], isError: false)
        }

        let lines = results.map { article -> String in
            let statusMarker = article.isRead ? "gelesen" : "ungelesen"
            let starMarker = article.isStarred ? ", ★" : ""
            let excerpt = String((article.summary ?? "").prefix(200))
            return "[\(article.id)] \(article.title) — \(article.feedTitle) (\(statusMarker)\(starMarker))\n\(excerpt)"
        }
        return .init(content: [.text(lines.joined(separator: "\n\n"))], isError: false)
    }
}
