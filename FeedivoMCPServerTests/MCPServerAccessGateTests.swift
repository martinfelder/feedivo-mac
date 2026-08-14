import Testing
import GRDB
@testable import FeedivoMCPServer

@Suite("MCP-Server-Zugriffsprüfung")
struct MCPServerAccessGateTests {
    @Test("Deaktivierter Schalter wird korrekt als false gelesen")
    func deaktivierterSchalterWirdAlsFalseGelesen() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let store = MCPServerSettingsStore(database: core)

        #expect(try store.isEnabled() == false)
    }

    @Test("Aktivierter Schalter wird korrekt als true gelesen")
    func aktivierterSchalterWirdAlsTrueGelesen() throws {
        let core = try FeedivoDatabase.inMemoryForTests()
        let store = MCPServerSettingsStore(database: core)
        try store.setEnabled(true)

        #expect(try store.isEnabled() == true)
    }

    @Test("Fehlende Tabelle wird fail-closed als false behandelt")
    func fehlendeTabelleWirdFailClosedAlsFalseBehandelt() throws {
        // Simuliert eine Datenbank, die nur bis vor Migration v31 migriert wurde
        // (z. B. weil Feedivo seit dem Update auf diese Version noch nicht
        // gestartet wurde) — die Store-Methode darf dabei NICHT crashen und
        // NICHT true zurückgeben.
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v30_backfill_article_estimated_reading_minutes")
        let core = FeedivoDatabase(writer: queue)
        let store = MCPServerSettingsStore(database: core)

        let isEnabled = (try? store.isEnabled()) ?? false
        #expect(isEnabled == false)
    }
}
