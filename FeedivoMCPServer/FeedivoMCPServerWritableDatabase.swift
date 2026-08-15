import Foundation
import GRDB

/// Schreibbarer Zugriff auf die Feedivo-Datenbank für Schreib-Tools (Phase 1 des
/// MCP-Server-V2-Plans) — nur genutzt, wenn der Nutzer den Schreibzugriff-Schalter in den
/// Einstellungen ZUSÄTZLICH zum Hauptschalter aktiviert hat (siehe MCPServerSettingsStore).
///
/// Nutzt DatabasePool (nicht DatabaseQueue) — matcht den Schreib-Modus der Haupt-App (siehe
/// FeedivoDatabase.swift) und erlaubt echte WAL-Parallelität zur ggf. gleichzeitig laufenden
/// Feedivo-App. `PRAGMA foreign_keys = ON` wird explizit gesetzt (anders als bei
/// FeedivoMCPServerDatabase.openReadOnly, die das nie braucht) — die Schreib-Tools verlassen
/// sich auf Fremdschlüssel-Verletzungen, um Schreibvorgänge mit ungültigen IDs zuverlässig
/// abzulehnen. Führt bewusst NIE FeedivoDatabaseMigrator aus, wie die readonly-Verbindung auch.
struct FeedivoMCPServerWritableDatabase {
    let core: FeedivoDatabase

    static func open(
        at fileURL: URL = FeedivoContainerDatabaseLocation.databaseURL()
    ) throws -> FeedivoMCPServerWritableDatabase {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw FeedivoMCPServerDatabaseError.databaseFileNotFound(fileURL)
        }

        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }

        do {
            let pool = try DatabasePool(path: fileURL.path, configuration: configuration)
            return FeedivoMCPServerWritableDatabase(core: FeedivoDatabase(writer: pool))
        } catch {
            throw FeedivoMCPServerDatabaseError.openFailed(description: "\(error)")
        }
    }
}
