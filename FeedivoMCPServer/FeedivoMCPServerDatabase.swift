import Foundation
import GRDB

enum FeedivoMCPServerDatabaseError: Error, CustomStringConvertible, Equatable {
    case databaseFileNotFound(URL)
    case openFailed(description: String)

    var description: String {
        switch self {
        case .databaseFileNotFound(let url):
            return "Feedivo-Datenbank nicht gefunden unter \(url.path). Wurde Feedivo mindestens einmal gestartet?"
        case .openFailed(let description):
            return "Feedivo-Datenbank konnte nicht geöffnet werden: \(description)"
        }
    }

    static func == (lhs: FeedivoMCPServerDatabaseError, rhs: FeedivoMCPServerDatabaseError) -> Bool {
        lhs.description == rhs.description
    }
}

/// Read-only-Zugriff auf die Feedivo-Datenbank aus einem separaten,
/// unsandboxed Prozess heraus. Führt bewusst NIE `FeedivoDatabaseMigrator`
/// aus — die Datenbank wird als bereits existierend und aktuell vorausgesetzt
/// (gepflegt von der laufenden oder zuletzt gelaufenen Feedivo-App).
struct FeedivoMCPServerDatabase {
    let core: FeedivoDatabase

    static func openReadOnly(
        at fileURL: URL = FeedivoContainerDatabaseLocation.databaseURL()
    ) throws -> FeedivoMCPServerDatabase {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw FeedivoMCPServerDatabaseError.databaseFileNotFound(fileURL)
        }

        // Bewusst KEIN `configuration.readonly = true`: SQLite kann eine WAL-Datenbank
        // nicht read-only öffnen, wenn die zugehörige "-shm"-Datei fehlt — diese Datei
        // existiert nur, solange mindestens eine offene Verbindung besteht, und
        // verschwindet z. B. wenn Feedivo komplett beendet wurde. Der zentrale
        // Anwendungsfall dieses Servers ("funktioniert auch ohne laufende Feedivo-App")
        // wäre dadurch kaputt. Stattdessen wird eine normale Verbindung geöffnet (kann bei
        // Bedarf die fehlende "-shm"-Datei anlegen), die Schreibsperre aber zusätzlich hart
        // auf SQLite-Ebene über `PRAGMA query_only = ON` erzwungen — lehnt jede schreibende
        // SQL-Anweisung ab, bietet dieselbe Garantie wie `readonly = true`.
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA query_only = ON")
        }

        do {
            let pool = try DatabasePool(path: fileURL.path, configuration: configuration)
            return FeedivoMCPServerDatabase(core: FeedivoDatabase(writer: pool))
        } catch {
            throw FeedivoMCPServerDatabaseError.openFailed(description: "\(error)")
        }
    }
}
