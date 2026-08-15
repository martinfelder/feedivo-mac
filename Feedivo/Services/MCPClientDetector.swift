import AppKit
import Foundation

/// Ein KI-Client, der Feedivos MCP-Server über eine Konfigurationsdatei einbinden kann.
struct MCPClient: Equatable {
    let displayName: String
    /// Absoluter Pfad zur Konfigurationsdatei des Clients — wird im Einstellungen-Tab als
    /// Einrichtungsschritt angezeigt und muss deshalb direkt verwendbar sein (keine Tilde).
    let configPath: String
}

/// Ermittelt, welche unterstützten KI-Clients auf diesem Mac installiert sind.
///
/// Die Abfrage läuft über **LaunchServices** (`NSWorkspace.urlForApplication(
/// withBundleIdentifier:)`), nicht über einen Blick in `/Applications` — Feedivo ist sandboxed
/// und darf dort nicht frei lesen, die LaunchServices-Abfrage ist dagegen erlaubt.
///
/// **Bewusst nur Claude Desktop:** Auf einem Entwicklungsrechner sind typischerweise weitere
/// KI-Apps installiert (ChatGPT, Ollama). Für sie ist weder gesichert, ob sie MCP über eine
/// Konfigurationsdatei einbinden, noch wo diese läge — sie zu erkennen, ohne einen Pfad nennen
/// zu können, würde nur falsche Erwartungen wecken. Ein weiterer Client ist später eine
/// zusätzliche Zeile in `supportedClients`.
enum MCPClientDetector {
    private struct SupportedClient {
        let bundleIdentifier: String
        let displayName: String
        let configPathComponents: [String]
    }

    private static let supportedClients: [SupportedClient] = [
        SupportedClient(
            bundleIdentifier: "com.anthropic.claudefordesktop",
            displayName: "Claude Desktop",
            configPathComponents: ["Library", "Application Support", "Claude", "claude_desktop_config.json"]
        )
    ]

    /// `lookup` ist injizierbar, damit die Auswertung ohne tatsächlich installierte App testbar
    /// bleibt — der Standardwert fragt LaunchServices.
    static func installedClients(
        lookup: (String) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    ) -> [MCPClient] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return supportedClients
            .filter { lookup($0.bundleIdentifier) }
            .map { client in
                let url = client.configPathComponents.reduce(home) { $0.appendingPathComponent($1) }
                return MCPClient(displayName: client.displayName, configPath: url.path)
            }
    }
}
