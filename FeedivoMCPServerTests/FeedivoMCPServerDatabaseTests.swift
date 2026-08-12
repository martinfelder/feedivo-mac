import Testing
import Foundation
import GRDB
@testable import FeedivoMCPServer

@Suite("FeedivoMCPServerDatabase")
struct FeedivoMCPServerDatabaseTests {
    @Test("Öffnet eine bestehende, migrierte Feedivo-Datenbank read-only")
    func oeffnetBestehendeDatenbankReadOnly() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dbURL = tempDir.appendingPathComponent("feedivo.sqlite")

        // Legt eine echte, vollständig migrierte Datenbank an — genau wie
        // FeedivoDatabase.open(at:) es beim echten App-Start tun würde.
        _ = try FeedivoDatabase.open(at: dbURL)

        let server = try FeedivoMCPServerDatabase.openReadOnly(at: dbURL)
        let count = try server.core.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feeds") ?? -1
        }
        #expect(count == 0)
    }

    @Test("Wirft databaseFileNotFound, wenn die Datei nicht existiert")
    func wirftFehlerBeiFehlenderDatei() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).sqlite")

        #expect(throws: FeedivoMCPServerDatabaseError.self) {
            try FeedivoMCPServerDatabase.openReadOnly(at: missing)
        }
    }

    @Test("Schreibversuche schlagen fehl, weil die Verbindung read-only ist")
    func schreibversucheSchlagenFehl() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dbURL = tempDir.appendingPathComponent("feedivo.sqlite")
        _ = try FeedivoDatabase.open(at: dbURL)

        let server = try FeedivoMCPServerDatabase.openReadOnly(at: dbURL)

        #expect(throws: (any Error).self) {
            try server.core.write { db in
                try db.execute(sql: "DELETE FROM feeds")
            }
        }
    }
}
