import Foundation
import GRDB

/// Eine laufende Verbindung eines KI-Clients zum MCP-Server.
struct MCPServerSession: Equatable {
    let pid: Int
    /// Anzeigename des Clients, abgeleitet aus dem Elternprozess (siehe `MCPClientNameResolver`).
    let clientName: String
    let startedAt: Date
    /// Werkzeuge, die GENAU DIESER Prozess anbietet — nicht, was die aktuellen Schalter ergäben.
    let toolCount: Int
    let lastHeartbeatAt: Date
}

/// Liest und schreibt die Tabelle `mcp_server_sessions`.
///
/// Der Serverprozess trägt sich beim Start ein und aktualisiert danach regelmäßig sein
/// Lebenszeichen; die App wertet aus, welche Sitzungen frisch genug sind, um als „verbunden" zu
/// gelten. Eine sandboxed App kann fremde Prozesse nicht zuverlässig beobachten — dieser Umweg
/// über die gemeinsame Datenbank ist der einzige verlässliche Weg.
struct MCPServerSessionStore {
    /// Wie alt ein Lebenszeichen höchstens sein darf, damit die Sitzung als verbunden gilt:
    /// zwei verpasste Intervalle (15 s) plus Puffer.
    static let heartbeatTolerance: TimeInterval = 40

    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    /// Trägt eine neue Sitzung ein. `INSERT OR REPLACE`, weil das Betriebssystem Prozess-IDs
    /// wiederverwendet — eine alte Zeile derselben ID gehört überschrieben, nicht dupliziert.
    func startSession(pid: Int, clientName: String, at date: Date, toolCount: Int) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO mcp_server_sessions
                        (pid, clientName, startedAt, toolCount, lastHeartbeatAt)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [pid, clientName, date, toolCount, date]
            )
        }
    }

    func recordHeartbeat(pid: Int, at date: Date) throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE mcp_server_sessions SET lastHeartbeatAt = ? WHERE pid = ?",
                arguments: [date, pid]
            )
        }
    }

    /// Räumt Zeilen von Prozessen weg, die sich nie ordentlich abgemeldet haben (etwa nach einem
    /// harten Abbruch). Wird vom Server beim Start aufgerufen, damit die Tabelle nicht wächst.
    func deleteSessions(lastSeenBefore cutoff: Date) throws {
        try database.write { db in
            try db.execute(
                sql: "DELETE FROM mcp_server_sessions WHERE lastHeartbeatAt < ?",
                arguments: [cutoff]
            )
        }
    }

    /// Sitzungen mit frischem Lebenszeichen, stabil sortiert nach Name und Werkzeug-Anzahl —
    /// sonst könnte die Anzeige zwischen zwei Aktualisierungen die Reihenfolge tauschen.
    func activeSessions(
        now: Date,
        tolerance: TimeInterval = MCPServerSessionStore.heartbeatTolerance
    ) throws -> [MCPServerSession] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT pid, clientName, startedAt, toolCount, lastHeartbeatAt
                    FROM mcp_server_sessions
                    WHERE lastHeartbeatAt >= ?
                    ORDER BY clientName COLLATE NOCASE, toolCount, pid
                    """,
                arguments: [now.addingTimeInterval(-tolerance)]
            ).map { row in
                MCPServerSession(
                    pid: row["pid"],
                    clientName: row["clientName"],
                    startedAt: row["startedAt"],
                    toolCount: row["toolCount"],
                    lastHeartbeatAt: row["lastHeartbeatAt"]
                )
            }
        }
    }
}
