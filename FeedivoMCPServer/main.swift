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

// Tasks 7–10 ergänzen hier jeweils einen Eintrag.
var availableTools: [Tool] = []

await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: availableTools)
}

await server.withMethodHandler(CallTool.self) { params in
    switch params.name {
    // Tasks 7–10 ergänzen hier jeweils einen case.
    default:
        return .init(content: [.text("Unbekanntes Tool: \(params.name)")], isError: true)
    }
}

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
