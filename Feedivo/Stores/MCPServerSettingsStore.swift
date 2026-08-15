import Foundation
import GRDB

/// Vermerk über die letzte Verbindung eines KI-Clients: wann der Serverprozess zuletzt startete
/// und wie viele Werkzeuge er dabei anbot.
struct MCPConnectionRecord: Equatable {
    let connectedAt: Date
    let toolCount: Int
}

struct MCPServerSettingsStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func isEnabled() throws -> Bool {
        try database.read { db in
            try Bool.fetchOne(db, sql: "SELECT isEnabled FROM mcp_server_settings WHERE id = 1") ?? false
        }
    }

    func setEnabled(_ isEnabled: Bool) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE mcp_server_settings SET isEnabled = ? WHERE id = 1", arguments: [isEnabled])
        }
    }

    func isWriteAccessEnabled() throws -> Bool {
        try database.read { db in
            try Bool.fetchOne(db, sql: "SELECT writeAccessIsEnabled FROM mcp_server_settings WHERE id = 1") ?? false
        }
    }

    func setWriteAccessEnabled(_ isEnabled: Bool) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE mcp_server_settings SET writeAccessIsEnabled = ? WHERE id = 1", arguments: [isEnabled])
        }
    }

    /// Letzter Verbindungsvermerk, oder `nil`, wenn noch nie ein Client verbunden war.
    func lastConnection() throws -> MCPConnectionRecord? {
        try database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT lastConnectedAt, lastConnectedToolCount FROM mcp_server_settings WHERE id = 1"
            ) else { return nil }
            guard let connectedAt: Date = row["lastConnectedAt"],
                  let toolCount: Int = row["lastConnectedToolCount"] else { return nil }
            return MCPConnectionRecord(connectedAt: connectedAt, toolCount: toolCount)
        }
    }

    /// Hält fest, dass ein Client den Server gestartet hat. Wird vom `FeedivoMCPServer`-Prozess
    /// aufgerufen — bewusst unabhängig vom Schreibzugriff-Schalter: die Zusage „rein lesend"
    /// gilt für Inhalte (Artikel, Tags, Status, Feeds), nicht für diesen Verbindungsvermerk.
    func recordConnection(at date: Date, toolCount: Int) throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE mcp_server_settings SET lastConnectedAt = ?, lastConnectedToolCount = ? WHERE id = 1",
                arguments: [date, toolCount]
            )
        }
    }
}
