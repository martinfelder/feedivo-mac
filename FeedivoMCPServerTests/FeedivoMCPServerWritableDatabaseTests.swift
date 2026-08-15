import Testing
import Foundation
import GRDB
@testable import FeedivoMCPServer

@Suite("FeedivoMCPServerWritableDatabase")
struct FeedivoMCPServerWritableDatabaseTests {
    @Test("Öffnet eine bestehende, migrierte Feedivo-Datenbank schreibbar")
    func oeffnetBestehendeDatenbankSchreibbar() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dbURL = tempDir.appendingPathComponent("feedivo.sqlite")

        _ = try FeedivoDatabase.open(at: dbURL)

        let server = try FeedivoMCPServerWritableDatabase.open(at: dbURL)
        try server.core.write { db in
            try db.execute(sql: "DELETE FROM feeds")
        }
        let count = try server.core.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feeds") ?? -1
        }
        #expect(count == 0)
    }

    @Test("Setzt PRAGMA foreign_keys — Fremdschlüsselverletzung schlägt fehl")
    func setztForeignKeysPragma() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dbURL = tempDir.appendingPathComponent("feedivo.sqlite")
        _ = try FeedivoDatabase.open(at: dbURL)

        let server = try FeedivoMCPServerWritableDatabase.open(at: dbURL)

        #expect(throws: (any Error).self) {
            try server.core.write { db in
                try db.execute(
                    sql: "INSERT INTO article_tags (articleID, tagID, assignedAt) VALUES (?, ?, ?)",
                    arguments: ["does-not-exist", "does-not-exist", Date()]
                )
            }
        }
    }

    @Test("Wirft databaseFileNotFound, wenn die Datei nicht existiert")
    func wirftFehlerBeiFehlenderDatei() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).sqlite")

        #expect(throws: FeedivoMCPServerDatabaseError.self) {
            try FeedivoMCPServerWritableDatabase.open(at: missing)
        }
    }
}
