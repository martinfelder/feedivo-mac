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

    private func sitzung(_ pid: Int, _ name: String, _ toolCount: Int) -> MCPServerSession {
        let zeitpunkt = Date(timeIntervalSince1970: 1_786_800_000)
        return MCPServerSession(
            pid: pid,
            clientName: name,
            startedAt: zeitpunkt,
            toolCount: toolCount,
            lastHeartbeatAt: zeitpunkt
        )
    }

    @Test("Ohne aktive Sitzungen gibt es keine Zeilen")
    func ohneSitzungenKeineZeilen() {
        #expect(MCPConnectionStatusText.activeLines(for: []).isEmpty)
    }

    @Test("Eine Sitzung ergibt eine Zeile mit Name und Werkzeug-Anzahl")
    func eineSitzungEineZeile() {
        let zeilen = MCPConnectionStatusText.activeLines(for: [sitzung(1, "Claude", 10)])

        #expect(zeilen.count == 1)
        #expect(zeilen[0].contains("Claude"))
        #expect(zeilen[0].contains("10"))
    }

    @Test("Zwei Sitzungen desselben Clients werden zu einer Zeile mit Anzahl")
    func gleicherClientWirdZusammengefasst() {
        // Beobachtet am 2026-08-16: Claude Desktop startet zwei Serverprozesse gleichzeitig.
        // Zwei identische Zeilen waeren nur verwirrend.
        let zeilen = MCPConnectionStatusText.activeLines(for: [
            sitzung(1, "Claude", 10),
            sitzung(2, "Claude", 10),
        ])

        #expect(zeilen.count == 1)
        #expect(zeilen[0].contains("2"))
    }

    @Test("Unterschiedliche Werkzeug-Anzahlen bleiben getrennte Zeilen")
    func unterschiedlicheWerkzeugzahlBleibtGetrennt() {
        // Genau dieser Unterschied ist die interessante Information: ein Prozess sitzt noch auf
        // einer veralteten Werkzeugliste.
        let zeilen = MCPConnectionStatusText.activeLines(for: [
            sitzung(1, "Claude", 7),
            sitzung(2, "Claude", 10),
        ])

        #expect(zeilen.count == 2)
    }

    @Test("Mehrere Clients ergeben mehrere Zeilen")
    func mehrereClientsMehrereZeilen() {
        let zeilen = MCPConnectionStatusText.activeLines(for: [
            sitzung(1, "Claude", 10),
            sitzung(2, "Cursor", 7),
        ])

        #expect(zeilen.count == 2)
        #expect(zeilen[0].contains("Claude"))
        #expect(zeilen[1].contains("Cursor"))
    }

    @Test("Ohne laufende Sitzung gibt es nichts zu melden")
    func ohneSitzungKeineZeile() {
        // Ohne verbundenen Client holt der naechste Start ohnehin die aktuelle Liste — ein
        // "starte ihn neu" waere hier schlicht falscher Rat.
        let zeile = MCPConnectionStatusText.staleToolListLine(
            sessions: [],
            isAccessEnabled: true,
            isWriteAccessEnabled: true
        )

        #expect(zeile == nil)
    }

    @Test("Bei ausgeschaltetem Zugriff wird nicht verglichen")
    func ohneZugriffKeineZeile() {
        // Dann laeuft kein Server, gegen den sich vergleichen liesse.
        let zeile = MCPConnectionStatusText.staleToolListLine(
            sessions: [sitzung(1, "Claude", 7)],
            isAccessEnabled: false,
            isWriteAccessEnabled: true
        )

        #expect(zeile == nil)
    }

    @Test("Passende Werkzeug-Anzahl ergibt keine Zeile")
    func passendeAnzahlKeineZeile() {
        let zeile = MCPConnectionStatusText.staleToolListLine(
            sessions: [sitzung(1, "Claude", 7)],
            isAccessEnabled: true,
            isWriteAccessEnabled: false
        )

        #expect(zeile == nil)
    }

    @Test("Abweichende Anzahl nennt beide Zahlen")
    func abweichendeAnzahlNenntBeideZahlen() {
        // Der reale Fall vom 2026-08-15: Schreibzugriff eingeschaltet, Client nicht neu gestartet.
        let zeile = MCPConnectionStatusText.staleToolListLine(
            sessions: [sitzung(1, "Claude", 7)],
            isAccessEnabled: true,
            isWriteAccessEnabled: true
        )

        #expect(zeile?.contains("7") == true)
        #expect(zeile?.contains("10") == true)
    }

    @Test("Bei mehreren Sitzungen zaehlt die niedrigste abweichende")
    func mehrereSitzungenNiedrigsteAbweichende() {
        // Am 2026-08-16 liefen unbemerkt zwei Serverprozesse gleichzeitig.
        let zeile = MCPConnectionStatusText.staleToolListLine(
            sessions: [sitzung(1, "Claude", 10), sitzung(2, "Claude", 7)],
            isAccessEnabled: true,
            isWriteAccessEnabled: true
        )

        #expect(zeile?.contains("7") == true)
    }
}
