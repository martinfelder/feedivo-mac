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
}
