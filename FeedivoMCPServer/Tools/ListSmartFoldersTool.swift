import MCP

enum ListSmartFoldersTool {
    static let definition = Tool(
        name: "list_smart_folders",
        description: "Listet alle Intelligenten Ordner (Standard + eigene) mit ihrer ID auf.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    )

    static func call(database: FeedivoMCPServerDatabase) throws -> CallTool.Result {
        let store = SQLiteSmartFolderStore(database: database.core)
        let folders = try store.sidebarSnapshots()

        if folders.isEmpty {
            return .init(content: [.text("Keine Intelligenten Ordner vorhanden.")], isError: false)
        }

        let lines = folders.map { folder -> String in
            let suffix = folder.defaultKey != nil ? ", Standard" : ""
            return "\(folder.name) (id: \(folder.id)\(suffix))"
        }
        return .init(content: [.text(lines.joined(separator: "\n"))], isError: false)
    }
}
