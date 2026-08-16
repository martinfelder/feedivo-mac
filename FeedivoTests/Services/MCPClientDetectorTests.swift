import Foundation
import Testing
@testable import Feedivo

@Suite("MCPClientDetector")
struct MCPClientDetectorTests {
    @Test("Alle sechs unterstuetzten Clients erscheinen, auch nicht installierte")
    func alleClientsErscheinen() {
        // Nicht installierte Clients bleiben waehlbar: Die Bundle-Kennungen von Cursor,
        // Windsurf und Zed sind unverifiziert — eine veraltete Kennung darf einen Client
        // hoechstens das Haekchen kosten, nicht seine Verfuegbarkeit.
        let clients = MCPClientDetector.allClients { _ in false }

        #expect(clients.count == 6)
        #expect(clients.allSatisfy { !$0.isInstalled })
    }

    @Test("Installierte Clients stehen vorn")
    func installierteStehenVorn() {
        let clients = MCPClientDetector.allClients { $0 == "dev.zed.Zed" }

        #expect(clients.first?.displayName == "Zed")
        #expect(clients.first?.isInstalled == true)
        #expect(clients.dropFirst().allSatisfy { !$0.isInstalled })
    }

    @Test("Claude Desktop hat Pfad und flaches mcpServers-Schema")
    func claudeDesktopHatPfadUndSchema() {
        let claude = MCPClientDetector.allClients { _ in true }
            .first { $0.displayName == "Claude Desktop" }

        #expect(claude?.schema == .mcpServers)
        #expect(claude?.configPath?.hasSuffix("Claude/claude_desktop_config.json") == true)
        #expect(claude?.configPath?.hasPrefix("/") == true)
        #expect(claude?.supportsAutomaticEntry == true)
    }

    @Test("Zed nutzt context_servers und erlaubt kein automatisches Eintragen")
    func zedErlaubtKeinAutomatischesEintragen() {
        // Zeds settings.json darf Kommentare enthalten; ein JSON-Roundtrip wuerde sie loeschen.
        let zed = MCPClientDetector.allClients { _ in true }.first { $0.displayName == "Zed" }

        #expect(zed?.schema == .contextServers)
        #expect(zed?.supportsAutomaticEntry == false)
    }

    @Test("VS Code nutzt servers und erlaubt kein automatisches Eintragen")
    func vsCodeErlaubtKeinAutomatischesEintragen() {
        let code = MCPClientDetector.allClients { _ in true }.first { $0.displayName == "VS Code" }

        #expect(code?.schema == .servers)
        #expect(code?.supportsAutomaticEntry == false)
    }

    @Test("Claude Code hat keinen Pfad und gilt nie als installiert")
    func claudeCodeOhnePfad() {
        // Claude Code ist ein Kommandozeilenprogramm ohne App-Bundle — LaunchServices kennt es
        // nicht, es ist deshalb grundsaetzlich nicht erkennbar.
        let cli = MCPClientDetector.allClients { _ in true }
            .first { $0.displayName == "Claude Code" }

        #expect(cli?.configPath == nil)
        #expect(cli?.schema == .commandLine)
        #expect(cli?.isInstalled == false)
        #expect(cli?.supportsAutomaticEntry == false)
    }
}
