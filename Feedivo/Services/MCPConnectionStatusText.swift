import Foundation

/// Baut den Statustext des Einstellungen-Tabs „KI-Zugriff".
///
/// Bewusst als reine Funktion getrennt von der View: Sie ist die einzige Stelle des
/// Statusbereichs mit echter Logik und dadurch ohne View-Test abzudecken.
///
/// Die Werkzeug-Anzahl stammt aus dem LETZTEN TATSÄCHLICHEN Serverstart, nicht aus den aktuell
/// gesetzten Schaltern — weicht sie vom erwarteten Umfang ab, sitzt ein laufender Client noch
/// auf einer veralteten Liste und muss neu gestartet werden. Genau dieser Fall blieb am
/// 2026-08-15 stundenlang unbemerkt.
enum MCPConnectionStatusText {
    static func text(
        for record: MCPConnectionRecord?,
        isWriteAccessEnabled: Bool,
        locale: Locale = .current
    ) -> String {
        guard let record else {
            return String(localized: "settings.mcpServer.status.neverConnected")
        }

        var formatStyle = Date.FormatStyle(date: .abbreviated, time: .shortened)
        formatStyle.locale = locale
        let zeitpunkt = record.connectedAt.formatted(formatStyle)

        let umfang = isWriteAccessEnabled
            ? String(localized: "settings.mcpServer.status.scopeWithWriteAccess")
            : String(localized: "settings.mcpServer.status.scopeReadOnly")

        return String(
            format: String(localized: "settings.mcpServer.status.connected"),
            zeitpunkt,
            record.toolCount,
            umfang
        )
    }

    /// Eine Zeile je Gruppe aktiver Sitzungen.
    ///
    /// Gruppiert wird nach Client-Name UND Werkzeug-Anzahl: Ein Client startet durchaus mehrere
    /// Serverprozesse gleichzeitig (am 2026-08-16 beobachtet), zwei identische Zeilen wären nur
    /// verwirrend. Unterscheiden sich die Werkzeug-Anzahlen dagegen, bleiben es getrennte Zeilen
    /// — dann sitzt einer der Prozesse noch auf einer veralteten Liste, und genau das ist die
    /// Information, die der Nutzer sehen soll.
    ///
    /// Die Reihenfolge stammt aus der Sortierung von `MCPServerSessionStore.activeSessions`.
    static func activeLines(for sessions: [MCPServerSession]) -> [String] {
        var reihenfolge: [String] = []
        var anzahlProGruppe: [String: Int] = [:]
        var beispielProGruppe: [String: MCPServerSession] = [:]

        for sitzung in sessions {
            let schluessel = "\(sitzung.clientName)\u{0}\(sitzung.toolCount)"
            if anzahlProGruppe[schluessel] == nil {
                reihenfolge.append(schluessel)
                beispielProGruppe[schluessel] = sitzung
            }
            anzahlProGruppe[schluessel, default: 0] += 1
        }

        return reihenfolge.compactMap { schluessel in
            guard let sitzung = beispielProGruppe[schluessel],
                  let anzahl = anzahlProGruppe[schluessel] else { return nil }

            if anzahl > 1 {
                return String(
                    format: String(localized: "settings.mcpServer.status.sessionGrouped"),
                    sitzung.clientName,
                    anzahl,
                    sitzung.toolCount
                )
            }
            return String(
                format: String(localized: "settings.mcpServer.status.session"),
                sitzung.clientName,
                sitzung.toolCount
            )
        }
    }
}
