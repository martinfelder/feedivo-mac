import Darwin
import Foundation
import GRDB

/// Hält beim Serverstart fest, dass ein KI-Client verbunden ist und mit wie vielen Werkzeugen —
/// und meldet danach regelmäßig, dass die Verbindung noch besteht.
///
/// **Bewusst unabhängig vom Schreibzugriff-Schalter:** Ohne diesen Vermerk kann der
/// Einstellungen-Tab „KI-Zugriff" nicht anzeigen, ob eine Verbindung besteht — am 2026-08-15
/// lief ein Serverprozess stundenlang mit einer veralteten Werkzeugliste, ohne dass das sichtbar
/// war. Die Zusage „rein lesend" gilt weiterhin uneingeschränkt für INHALTE (Artikel, Tags,
/// Status, Feeds); geschrieben werden ausschließlich Verbindungsmetadaten.
///
/// Nutzt eine eigene Verbindung statt `FeedivoMCPServerWritableDatabase`: jene wird nur bei
/// aktiviertem Schreibzugriff geöffnet und prüft zusätzlich eine Precondition, die hier keine
/// Rolle spielt.
enum FeedivoMCPServerConnectionRecorder {
    /// Abstand zwischen zwei Lebenszeichen. Die App wertet eine Sitzung als beendet, wenn das
    /// letzte Lebenszeichen älter als `MCPServerSessionStore.heartbeatTolerance` ist.
    static let heartbeatInterval: TimeInterval = 15

    /// Ab wann eine Sitzungszeile beim Start weggeräumt wird. Großzügig gewählt: Sie darf nur
    /// Prozesse treffen, die nachweislich nicht mehr laufen.
    static let staleSessionCutoff: TimeInterval = 600

    /// Schluckt jeden Fehler bewusst (nach Protokollierung auf stderr): Ein fehlender
    /// Verbindungsvermerk ist ein kosmetisches Problem und darf den Dienst nie blockieren.
    /// Das gilt auch für eine veraltete Datenbank ohne Tabelle `mcp_server_sessions` — der
    /// Server führt den Migrator nie aus (ADR-011).
    static func record(toolCount: Int, at fileURL: URL = FeedivoContainerDatabaseLocation.databaseURL()) {
        do {
            var configuration = Configuration()
            configuration.busyMode = .timeout(5)
            let pool = try DatabasePool(path: fileURL.path, configuration: configuration)
            let database = FeedivoDatabase(writer: pool)
            let jetzt = Date()
            let prozessID = Int(getpid())

            try MCPServerSettingsStore(database: database)
                .recordConnection(at: jetzt, toolCount: toolCount)

            let sitzungen = MCPServerSessionStore(database: database)
            try sitzungen.deleteSessions(lastSeenBefore: jetzt.addingTimeInterval(-staleSessionCutoff))
            try sitzungen.startSession(
                pid: prozessID,
                clientName: MCPClientNameResolver.clientName(forExecutablePath: parentExecutablePath()),
                at: jetzt,
                toolCount: toolCount
            )

            startHeartbeat(pool: pool, pid: prozessID)
        } catch {
            let message = "Feedivo MCP Server: Verbindungsvermerk konnte nicht geschrieben werden (\(error)).\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }

    /// Faengt bewusst den `DatabasePool` ein (GRDB-eigener, nebenlaeufigkeitssicherer Typ) und
    /// baut die Huelle in der Schleife neu — so muss nichts anderes ueber die Task-Grenze.
    private static func startHeartbeat(pool: DatabasePool, pid: Int) {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(heartbeatInterval))
                // Fehler werden hier still verschluckt: Ein einzelnes verpasstes Lebenszeichen
                // laesst die Anzeige hoechstens kurz auf "nicht verbunden" springen; den Dienst
                // dafuer mit Logzeilen zu fluten, waere unverhaeltnismaessig.
                try? MCPServerSessionStore(database: FeedivoDatabase(writer: pool))
                    .recordHeartbeat(pid: pid, at: Date())
            }
        }
    }

    /// Pfad des Prozesses, der diesen Server gestartet hat — bei Claude Desktop ein Hilfsprogramm
    /// innerhalb des App-Bundles. Leerer String, wenn das fehlschlaegt; der Aufrufer bildet das
    /// auf einen Platzhalternamen ab.
    private static func parentExecutablePath() -> String {
        var puffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let laenge = puffer.withUnsafeMutableBufferPointer { zeiger in
            proc_pidpath(getppid(), zeiger.baseAddress, UInt32(MAXPATHLEN))
        }
        guard laenge > 0 else { return "" }
        return String(cString: puffer)
    }
}
