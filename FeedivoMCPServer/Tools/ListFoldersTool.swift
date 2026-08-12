import MCP

enum ListFoldersTool {
    static let definition = Tool(
        name: "list_folders",
        description: "Listet alle Feed-Ordner auf.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    )

    static func call(database: FeedivoMCPServerDatabase) throws -> CallTool.Result {
        let store = FeedFolderStore(database: database.core)
        let folders = try store.folders()

        if folders.isEmpty {
            return .init(content: [.text("Keine Ordner angelegt.")], isError: false)
        }

        let lines = folders.map { "\($0.name) (id: \($0.id))" }
        return .init(content: [.text(lines.joined(separator: "\n"))], isError: false)
    }
}
