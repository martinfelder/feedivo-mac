import MCP

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

        let limit = arguments?["limit"]?.intValue ?? 50
        let timeline = TimelineStore(database: database.core)
        let results = try timeline.articles(
            scope: .smartFolder(snapshot),
            includeRead: true,
            includeHidden: false,
            limit: limit
        )

        if results.isEmpty {
            return .init(content: [.text("Keine Artikel in \"\(snapshot.name)\".")], isError: false)
        }

        let lines = results.map { "[\($0.id)] \($0.title) — \($0.feedTitle)" }
        return .init(content: [.text(lines.joined(separator: "\n"))], isError: false)
    }
}
