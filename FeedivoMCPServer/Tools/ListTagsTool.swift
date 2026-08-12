import MCP

enum ListTagsTool {
    static let definition = Tool(
        name: "list_tags",
        description: "Listet alle Tags mit der Anzahl zugeordneter Artikel auf.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    )

    static func call(database: FeedivoMCPServerDatabase) throws -> CallTool.Result {
        let store = TagStore(database: database.core)
        let tags = try store.sidebarTags()

        if tags.isEmpty {
            return .init(content: [.text("Keine Tags angelegt.")], isError: false)
        }

        let lines = tags.map { "\($0.name) (id: \($0.id), Artikel: \($0.articleCount))" }
        return .init(content: [.text(lines.joined(separator: "\n"))], isError: false)
    }
}
