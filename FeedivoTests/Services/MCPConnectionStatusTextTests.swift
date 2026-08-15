import Foundation
import Testing
@testable import Feedivo

@Suite("MCPConnectionStatusText")
struct MCPConnectionStatusTextTests {
    @Test("Ohne Vermerk wird zur Einrichtung aufgefordert")
    func ohneVermerkFordertZurEinrichtungAuf() {
        let text = MCPConnectionStatusText.text(for: nil, isWriteAccessEnabled: false)

        #expect(text.contains("Noch nie verbunden"))
    }

    @Test("Mit Vermerk erscheinen Werkzeug-Anzahl und Umfang")
    func mitVermerkErscheintAnzahlUndUmfang() {
        let vermerk = MCPConnectionRecord(connectedAt: Date(timeIntervalSince1970: 1_786_800_000), toolCount: 10)

        let text = MCPConnectionStatusText.text(
            for: vermerk,
            isWriteAccessEnabled: true,
            locale: Locale(identifier: "de_DE")
        )

        #expect(text.contains("10"))
        #expect(text.contains("Schreibzugriff"))
    }

    @Test("Ohne Schreibzugriff wird der Umfang als nur lesend benannt")
    func ohneSchreibzugriffNurLesend() {
        let vermerk = MCPConnectionRecord(connectedAt: Date(timeIntervalSince1970: 1_786_800_000), toolCount: 7)

        let text = MCPConnectionStatusText.text(
            for: vermerk,
            isWriteAccessEnabled: false,
            locale: Locale(identifier: "de_DE")
        )

        #expect(text.contains("7"))
        #expect(text.contains("lesend"))
        #expect(!text.contains("Schreibzugriff"))
    }
}
