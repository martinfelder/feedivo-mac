import Foundation

/// Schreibt Feedivos Servereintrag in die Konfigurationsdatei eines KI-Clients.
///
/// Der Aufrufer muss die Datei zuvor über ein `NSOpenPanel` vom Nutzer freigeben lassen — ohne
/// diese Freigabe verweigert die App-Sandbox jeden Zugriff auf fremde Konfigurationsordner.
///
/// Reihenfolge ist Absicht: erst lesen, dann zusammenführen, dann sichern, erst zuletzt
/// schreiben. Schlägt einer der Schritte fehl, bleibt die Originaldatei unangetastet.
enum MCPConfigWriter {
    /// Endung der Sicherungskopie, die neben der Originaldatei entsteht.
    static let backupSuffix = ".feedivo-backup"

    static func write(to url: URL, schema: MCPClientConfigSchema, executablePath: String) throws {
        // Eine noch nicht vorhandene Datei ist kein Fehler — dann wird sie neu angelegt.
        let vorhanden = (try? Data(contentsOf: url)) ?? Data()

        let neu = try MCPConfigMerger.merged(
            existing: vorhanden,
            schema: schema,
            executablePath: executablePath
        )

        if !vorhanden.isEmpty {
            // Ueberschreibt eine aeltere Kopie bewusst: Sonst schluege jeder zweite Durchlauf
            // fehl, und die interessante Sicherung ist die vom letzten Stand.
            try vorhanden.write(to: url.appendingPathExtension(String(backupSuffix.dropFirst())))
        }

        try neu.write(to: url)
    }
}
