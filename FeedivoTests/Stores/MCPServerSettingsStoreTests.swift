import Foundation
import Testing
import GRDB
@testable import Feedivo

@Suite("MCPServerSettingsStore")
struct MCPServerSettingsStoreTests {
    @Test("Standardwert nach Migration ist deaktiviert")
    func standardwertIstDeaktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = MCPServerSettingsStore(database: database)

        #expect(try store.isEnabled() == false)
    }

    @Test("setEnabled persistiert den neuen Wert")
    func setEnabledPersistiertWert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = MCPServerSettingsStore(database: database)

        try store.setEnabled(true)
        #expect(try store.isEnabled() == true)

        try store.setEnabled(false)
        #expect(try store.isEnabled() == false)
    }

    @Test("Standardwert für Schreibzugriff nach Migration ist deaktiviert")
    func standardwertSchreibzugriffIstDeaktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = MCPServerSettingsStore(database: database)

        #expect(try store.isWriteAccessEnabled() == false)
    }

    @Test("setWriteAccessEnabled persistiert den neuen Wert unabhängig vom Hauptschalter")
    func setWriteAccessEnabledPersistiertWert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = MCPServerSettingsStore(database: database)

        try store.setWriteAccessEnabled(true)
        #expect(try store.isWriteAccessEnabled() == true)
        // Hauptschalter bleibt vom Schreibzugriff-Flag unberührt.
        #expect(try store.isEnabled() == false)

        try store.setWriteAccessEnabled(false)
        #expect(try store.isWriteAccessEnabled() == false)
    }

    @Test("Fehlende Tabelle wird fail-closed als false behandelt")
    func fehlendeTabelleWirdFailClosedAlsFalseBehandelt() throws {
        // Simuliert eine Datenbank, die nur bis vor Migration v31 migriert wurde
        // (z. B. weil Feedivo seit dem Update auf diese Version noch nicht
        // gestartet wurde) — die Store-Methode darf dabei NICHT crashen und
        // NICHT true zurückgeben.
        //
        // Gespiegelt aus FeedivoMCPServerTests/MCPServerAccessGateTests.swift
        // (identischer Test gegen MCPServerSettingsStore aus dem
        // FeedivoMCPServer-Target) — das FeedivoMCPServerTests-Target kann in
        // diesem Projekt strukturell nie per `xcodebuild test` ausgeführt
        // werden ("Could not find test host" bei Command-Line-Tool-Targets),
        // dieser Test hier läuft dagegen ganz normal über das Haupt-App-
        // Test-Target und verifiziert damit dasselbe sicherheitskritische
        // Fail-Closed-Verhalten tatsächlich zur Laufzeit.
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v30_backfill_article_estimated_reading_minutes")
        let database = FeedivoDatabase(writer: queue)
        let store = MCPServerSettingsStore(database: database)

        let isEnabled = (try? store.isEnabled()) ?? false
        #expect(isEnabled == false)
    }

    @Test("Ohne Verbindungsvermerk liefert lastConnection nil")
    func ohneVermerkLiefertNil() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = MCPServerSettingsStore(database: database)

        #expect(try store.lastConnection() == nil)
    }

    @Test("recordConnection speichert Zeitpunkt und Werkzeug-Anzahl")
    func recordConnectionSpeichertBeideWerte() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = MCPServerSettingsStore(database: database)
        let zeitpunkt = Date(timeIntervalSince1970: 1_786_800_000)

        try store.recordConnection(at: zeitpunkt, toolCount: 10)

        let vermerk = try store.lastConnection()
        #expect(vermerk?.toolCount == 10)
        // Sekundengenauer Vergleich: GRDB speichert DATETIME mit Millisekunden, ein exakter
        // Date-Vergleich waere unnoetig bruechig.
        #expect(abs((vermerk?.connectedAt ?? .distantPast).timeIntervalSince(zeitpunkt)) < 1)
    }

    @Test("Ein zweiter Vermerk ersetzt den ersten")
    func zweiterVermerkErsetztDenErsten() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = MCPServerSettingsStore(database: database)

        try store.recordConnection(at: Date(timeIntervalSince1970: 1_786_800_000), toolCount: 7)
        try store.recordConnection(at: Date(timeIntervalSince1970: 1_786_900_000), toolCount: 10)

        #expect(try store.lastConnection()?.toolCount == 10)
    }

    @Test("Fehlende Spalten werden als nie verbunden behandelt")
    func fehlendeSpaltenWerdenAlsNieVerbundenBehandelt() throws {
        // Fail-safe: Ein Lesefehler darf den Tab nicht unbedienbar machen — er zeigt dann
        // denselben Zustand wie "noch nie verbunden".
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v30_backfill_article_estimated_reading_minutes")
        let database = FeedivoDatabase(writer: queue)

        let vermerk = try? MCPServerSettingsStore(database: database).lastConnection()
        #expect((vermerk ?? nil) == nil)
    }
}
