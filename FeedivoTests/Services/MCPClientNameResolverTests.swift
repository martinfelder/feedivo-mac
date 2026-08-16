import Foundation
import Testing
@testable import Feedivo

@Suite("MCPClientNameResolver")
struct MCPClientNameResolverTests {
    @Test("Aus einem App-Bundle-Pfad wird der App-Name")
    func appBundleWirdZuAppName() {
        // Genau dieser Pfad wurde am 2026-08-16 auf dem Rechner des Nutzers beobachtet:
        // Claude Desktop startet den Server ueber einen Hilfsprozess.
        let name = MCPClientNameResolver.clientName(
            forExecutablePath: "/Applications/Claude.app/Contents/Helpers/disclaimer"
        )

        #expect(name == "Claude")
    }

    @Test("Bei verschachtelten Bundles gewinnt das aeussere")
    func aeusseresBundleGewinnt() {
        // Das aeussere Bundle ist die App, die der Nutzer kennt — ein inneres Helper-Bundle
        // traegt einen technischen Namen, der ihm nichts sagt.
        let name = MCPClientNameResolver.clientName(
            forExecutablePath: "/Applications/Cursor.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"
        )

        #expect(name == "Cursor")
    }

    @Test("Ohne Bundle wird der Dateiname genutzt")
    func ohneBundleDateiname() {
        let name = MCPClientNameResolver.clientName(forExecutablePath: "/opt/homebrew/bin/node")

        #expect(name == "node")
    }

    @Test("Ein leerer Pfad ergibt einen Platzhalter")
    func leererPfadErgibtPlatzhalter() {
        // Tritt auf, wenn die Ermittlung des Elternprozesses fehlschlaegt.
        #expect(MCPClientNameResolver.clientName(forExecutablePath: "") == "Unbekannt")
    }
}
