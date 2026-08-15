import Foundation
import Testing
@testable import Feedivo

@Suite("MCPClientDetector")
struct MCPClientDetectorTests {
    @Test("Erkennt Claude Desktop, wenn installiert")
    func erkenntClaudeDesktop() {
        let clients = MCPClientDetector.installedClients { bundleID in
            bundleID == "com.anthropic.claudefordesktop"
        }

        #expect(clients.count == 1)
        #expect(clients.first?.displayName == "Claude Desktop")
        #expect(clients.first?.configPath.hasSuffix("claude_desktop_config.json") == true)
    }

    @Test("Liefert nichts, wenn kein unterstuetzter Client installiert ist")
    func ohneInstallationLeer() {
        // Deckt den Fall ab, in dem der Einrichtungsbereich durch einen Hinweis ersetzt wird —
        // ein Konfigurationsschnipsel ohne Ziel hilft niemandem.
        let clients = MCPClientDetector.installedClients { _ in false }

        #expect(clients.isEmpty)
    }

    @Test("Konfigurationspfad ist absolut, nicht mit Tilde abgekuerzt")
    func konfigurationspfadIstAbsolut() {
        // Der Pfad wird im Tab zum Kopieren angeboten und muss direkt verwendbar sein.
        let clients = MCPClientDetector.installedClients { _ in true }

        #expect(clients.first?.configPath.hasPrefix("/") == true)
    }
}
