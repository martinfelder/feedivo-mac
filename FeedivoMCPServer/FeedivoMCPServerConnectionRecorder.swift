import Foundation
import GRDB

/// Hält beim Serverstart fest, dass ein KI-Client verbunden ist und mit wie vielen Werkzeugen.
///
/// **Bewusst unabhängig vom Schreibzugriff-Schalter:** Ohne diesen Vermerk kann der
/// Einstellungen-Tab „KI-Zugriff" nicht anzeigen, ob je eine Verbindung bestand — am 2026-08-15
/// lief ein Serverprozess stundenlang mit einer veralteten Werkzeugliste, ohne dass das sichtbar
/// war. Die Zusage „rein lesend" gilt weiterhin uneingeschränkt für INHALTE (Artikel, Tags,
/// Status, Feeds); vermerkt wird ausschließlich, dass und womit sich ein Client verbunden hat.
///
/// Nutzt eine eigene, kurzlebige Verbindung statt `FeedivoMCPServerWritableDatabase`: jene wird
/// nur bei aktiviertem Schreibzugriff geöffnet und prüft zusätzlich eine Precondition, die für
/// diesen Vermerk keine Rolle spielt.
enum FeedivoMCPServerConnectionRecorder {
    /// Schluckt jeden Fehler bewusst (nach Protokollierung auf stderr): Ein fehlender
    /// Verbindungsvermerk ist ein kosmetisches Problem und darf den Dienst nie blockieren.
    static func record(toolCount: Int, at fileURL: URL = FeedivoContainerDatabaseLocation.databaseURL()) {
        do {
            var configuration = Configuration()
            configuration.busyMode = .timeout(5)
            let pool = try DatabasePool(path: fileURL.path, configuration: configuration)
            try MCPServerSettingsStore(database: FeedivoDatabase(writer: pool))
                .recordConnection(at: Date(), toolCount: toolCount)
        } catch {
            let message = "Feedivo MCP Server: Verbindungsvermerk konnte nicht geschrieben werden (\(error)).\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }
}
