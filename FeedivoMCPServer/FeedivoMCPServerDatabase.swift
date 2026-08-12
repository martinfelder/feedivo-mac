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

        var configuration = Configuration()
        configuration.readonly = true
        configuration.busyMode = .timeout(5)

        do {
            let pool = try DatabasePool(path: fileURL.path, configuration: configuration)
            return FeedivoMCPServerDatabase(core: FeedivoDatabase(writer: pool))
        } catch {
            throw FeedivoMCPServerDatabaseError.openFailed(description: "\(error)")
        }
    }
}
