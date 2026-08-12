import Foundation
import MCP

let database: FeedivoMCPServerDatabase
do {
    database = try FeedivoMCPServerDatabase.openReadOnly()
} catch {
    let message = "Feedivo MCP Server konnte die Datenbank nicht öffnen: \(error)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}

let server = Server(
    name: "feedivo-mcp-server",
    version: "1.0.0",
    capabilities: .init(
        tools: .init(listChanged: false)
    )
)

// Task 10 ergänzt hier einen weiteren Eintrag.
var availableTools: [Tool] = [
    ListFeedsTool.definition,
    ListFoldersTool.definition,
    ListTagsTool.definition,
    SearchArticlesTool.definition,
    GetArticleTool.definition,
]

await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: availableTools)
}

await server.withMethodHandler(CallTool.self) { params in
    switch params.name {
    case "list_feeds":
        return try ListFeedsTool.call(database: database)
    case "list_folders":
        return try ListFoldersTool.call(database: database)
    case "list_tags":
        return try ListTagsTool.call(database: database)
    case "search_articles":
        return try SearchArticlesTool.call(database: database, arguments: params.arguments)
    case "get_article":
        return try GetArticleTool.call(database: database, arguments: params.arguments)
    // Task 10 ergänzt hier einen weiteren case.
    default:
        return .init(content: [.text("Unbekanntes Tool: \(params.name)")], isError: true)
    }
}

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
