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
}
