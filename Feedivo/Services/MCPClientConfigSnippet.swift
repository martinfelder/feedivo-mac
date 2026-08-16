import Foundation

/// Erzeugt den Text, den der Nutzer in die Konfiguration seines KI-Clients übernimmt.
///
/// Bewusst von Hand zusammengesetzt statt über `JSONSerialization`: Der Text wird zum Kopieren
/// angeboten und soll so aussehen, wie ein Mensch ihn schreiben würde — mit Einrückung und in
/// stabiler Reihenfolge. `JSONSerialization` sortiert Schlüssel nicht verlässlich und liefert
/// ohne `.prettyPrinted` eine einzige Zeile.
enum MCPClientConfigSnippet {
    /// Der Name, unter dem Feedivo in der Konfiguration des Clients steht.
    static let serverName = "feedivo"

    static func text(for schema: MCPClientConfigSchema, executablePath: String) -> String {
        switch schema {
        case .commandLine:
            return "claude mcp add \(serverName) \(executablePath)"

        case .contextServers:
            return """
            {
              "context_servers": {
                "\(serverName)": {
                  "command": {
                    "path": "\(executablePath)",
                    "args": []
                  }
                }
              }
            }
            """

        case .mcpServers, .servers:
            // Beide unterscheiden sich nur im äußeren Schlüssel.
            let schluessel = schema.rootKey ?? "mcpServers"
            return """
            {
              "\(schluessel)": {
                "\(serverName)": { "command": "\(executablePath)" }
              }
            }
            """
        }
    }
}
