import MCP
import Foundation

enum GetSmartFolderArticlesTool {
    static let definition = Tool(
        name: "get_smart_folder_articles",
        description: "Liest die Artikel eines Intelligenten Ordners (per ID aus list_smart_folders).",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "smartFolderID": .object(["type": .string("string")]),
                "limit": .object(["type": .string("integer")]),
            ]),
            "required": .array([.string("smartFolderID")]),
        ])
    )

    static func call(database: FeedivoMCPServerDatabase, arguments: [String: Value]?) throws -> CallTool.Result {
        guard let folderID = arguments?["smartFolderID"]?.stringValue else {
            return .init(content: [.text("Fehlender Parameter: smartFolderID")], isError: true)
        }

        let smartFolderStore = SQLiteSmartFolderStore(database: database.core)
        guard let snapshot = try smartFolderStore.sidebarSnapshots().first(where: { $0.id == folderID }) else {
            return .init(content: [.text("Kein Intelligenter Ordner mit ID \(folderID) gefunden.")], isError: true)
        }

        // Obergrenze 200: ein Client könnte sonst z. B. limit: 100000 anfragen und
        // faktisch die komplette Datenbank in eine einzige Antwort schreiben.
        let limit = min(arguments?["limit"]?.intValue ?? 50, 200)
        let timeline = TimelineStore(database: database.core)
        let results = try timeline.articles(
            scope: .smartFolder(snapshot),
            includeRead: true,
            includeHidden: snapshot.includesHiddenArticles,
            limit: limit
        )

        if results.isEmpty {
            return .init(content: [.text("Keine Artikel in \"\(snapshot.name)\".")], isError: false)
        }

        let dateFormatter = ISO8601DateFormatter()
        let lines = results.map { article -> String in
            let dateString = dateFormatter.string(from: article.publishedAt ?? article.arrivedAt)
            return "[\(article.id)] \(article.title) — \(article.feedTitle) (\(dateString))"
        }
        return .init(content: [.text(lines.joined(separator: "\n"))], isError: false)
    }
}
