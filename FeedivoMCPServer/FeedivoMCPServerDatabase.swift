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

        // Bewusst `configuration.readonly = true` (NICHT nur eine manuell gesetzte
        // `PRAGMA query_only = ON`): Ein vorheriger Versuch, die Schreibsperre allein über
        // `configuration.prepareDatabase { PRAGMA query_only = ON }` zu erzwingen, erwies sich
        // per eigenem Nachbau als wirkungslos — GRDBs `DatabaseQueue.read { … }`/`.write { … }`
        // verwalten `PRAGMA query_only` intern selbst (`Database.beginReadOnly()`/
        // `endReadOnly()`, siehe GRDB.swift/GRDB/Core/Database.swift) und setzen es nach JEDEM
        // `.read`-Block automatisch wieder auf `0` zurück, sobald `configuration.readonly` nicht
        // gesetzt ist — unabhängig vom eigenen `prepareDatabase`-Hook. Ein späterer `.write`-
        // Aufruf würde dadurch trotz der eigenen Pragma-Setzung klaglos durchgehen (empirisch
        // reproduziert: `read` gefolgt von `write` legte tatsächlich eine Tabelle an). Nur
        // `configuration.readonly = true` liefert echten Schreibschutz, da GRDBs eigene
        // Read-Only-Verwaltung dann von vornherein gar nicht erst eingreift (`if
        // configuration.readonly { return }` in `beginReadOnly`/`endReadOnly`) und SQLite die
        // Verbindung selbst mit `SQLITE_OPEN_READONLY` öffnet.
        //
        // `DatabaseQueue` (NICHT `DatabasePool`) mit `readonly = true` öffnet zusätzlich in den
        // beiden praktisch relevanten Fällen erfolgreich: laufende Feedivo-App (aktives "-wal")
        // und sauber beendete Feedivo-App (vorhandenes, aber leeres "-wal" — Feedivo nutzt seit
        // dem DatabasePool-Umstieg im Haupt-Target durchgehend WAL-Modus, das "-wal" wird beim
        // allerersten Öffnen angelegt und danach nie mehr gelöscht). Nur ein komplett fehlendes
        // "-wal" (kein Feedivo-Datenbank-Zustand, der durch normalen Betrieb entsteht) würde
        // hier noch scheitern — `DatabasePool` bräuchte dafür ohnehin einen Schreibzugriff beim
        // WAL-Setup, den `readonly = true` grundsätzlich verbietet. Die Pool-Parallelität von
        // `DatabasePool` wird für einen rein lesenden, single-connection MCP-Server ohnehin
        // nicht gebraucht.
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.readonly = true

        do {
            let queue = try DatabaseQueue(path: fileURL.path, configuration: configuration)
            return FeedivoMCPServerDatabase(core: FeedivoDatabase(writer: queue))
        } catch {
            throw FeedivoMCPServerDatabaseError.openFailed(description: "\(error)")
        }
    }
}
