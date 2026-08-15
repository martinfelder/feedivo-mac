import Foundation
import Testing
import GRDB
@testable import Feedivo

@Suite("CloudSyncSettingsStore")
struct CloudSyncSettingsStoreTests {
    @Test("Standardwert nach Migration ist deaktiviert")
    func standardwertIstDeaktiviert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncSettingsStore(database: database)

        #expect(try store.isEnabled() == false)
    }

    @Test("setEnabled persistiert den neuen Wert")
    func setEnabledPersistiertWert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncSettingsStore(database: database)

        try store.setEnabled(true)
        #expect(try store.isEnabled() == true)

        try store.setEnabled(false)
        #expect(try store.isEnabled() == false)
    }

    @Test("isEnabled(in:) liest ueber eine bereits offene Transaktions-Verbindung")
    func isEnabledInTransaktionLiestAktuellenWert() throws {
        // Genau der Aufrufweg, den die Store-Gates (enqueuePendingSync) nutzen: sie stehen
        // bereits INNERHALB eines database.write-Blocks. Ein dortiger database.read-Aufruf
        // wuerde GRDBs Reentranz-Precondition verletzen ("Database methods are not
        // reentrant.") — dieser Test sichert ab, dass der Lesepfad ueber `db` laeuft.
        let database = try FeedivoDatabase.inMemoryForTests()
        try CloudSyncSettingsStore(database: database).setEnabled(true)

        let gelesen = try database.write { db in
            CloudSyncSettingsStore.isEnabled(in: db)
        }
        #expect(gelesen == true)
    }

    @Test("Fehlende Tabelle wird fail-closed als false behandelt")
    func fehlendeTabelleWirdFailClosedAlsFalseBehandelt() throws {
        // Simuliert eine Datenbank, die nur bis vor Migration v33 migriert wurde. Ein Gate,
        // das im Zweifel NICHT synct, ist sicherer als eines, das im Zweifel synct: der Wert
        // wird dann hoechstens verzoegert gepusht, es geht nichts verloren.
        let queue = try DatabaseQueue()
        try FeedivoDatabaseMigrator.migrator.migrate(queue, upTo: "v32_add_mcp_server_write_access")
        let database = FeedivoDatabase(writer: queue)

        let ueberTransaktion = try database.write { db in
            CloudSyncSettingsStore.isEnabled(in: db)
        }
        #expect(ueberTransaktion == false)

        let ueberInstanz = (try? CloudSyncSettingsStore(database: database).isEnabled()) ?? false
        #expect(ueberInstanz == false)
    }

    @Test("mirrorFromUserDefaults uebernimmt einen bestehenden UserDefaults-Wert")
    func mirrorUebernimmtBestehendenWert() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncSettingsStore(database: database)
        let suiteName = "CloudSyncSettingsStoreTests.mirror"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        defaults.set(true, forKey: CloudSyncSettings.isEnabledKey)
        try store.mirrorFromUserDefaults(defaults)
        #expect(try store.isEnabled() == true)

        defaults.set(false, forKey: CloudSyncSettings.isEnabledKey)
        try store.mirrorFromUserDefaults(defaults)
        #expect(try store.isEnabled() == false)
    }

    @Test("mirrorFromUserDefaults faellt ohne gesetzten Schluessel auf den Standard zurueck")
    func mirrorNutztStandardOhneGesetztenSchluessel() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = CloudSyncSettingsStore(database: database)
        try store.setEnabled(true)

        let suiteName = "CloudSyncSettingsStoreTests.mirrorLeer"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        try store.mirrorFromUserDefaults(defaults)
        #expect(try store.isEnabled() == CloudSyncSettings.defaultIsEnabled)
    }
}
