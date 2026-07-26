import Foundation
import GRDB

/// App-eigene, durable Warteschlange für Datensätze, die noch zu CloudKit hochgeladen werden
/// müssen (siehe `CloudSyncPendingChangeRecord`-Dokumentation). Analog zu den übrigen
/// `*Store`-Typen (ein Store pro Tabelle) aufgebaut.
struct CloudSyncPendingChangeStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    func enqueue(recordType: String, recordName: String, changeType: CloudSyncChangeType, changedFields: [String]? = nil) throws {
        try database.write { db in
            try Self.enqueue(db, recordType: recordType, recordName: recordName, changeType: changeType, changedFields: changedFields)
        }
    }

    /// Variante für Aufrufer, die bereits in einer eigenen `database.write`-Transaktion stecken
    /// (z. B. `TagStore`) — hält die fachliche Mutation und das Pending-Change-Markieren atomar.
    static func enqueue(_ db: Database, recordType: String, recordName: String, changeType: CloudSyncChangeType, changedFields: [String]? = nil) throws {
        var change = CloudSyncPendingChangeRecord(
            id: recordName,
            recordType: recordType,
            changeType: changeType,
            queuedAt: Date(),
            changedFields: changedFields
        )
        try change.save(db)
    }

    func dequeue(recordName: String) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM cloud_sync_pending_changes WHERE id = ?", arguments: [recordName])
        }
    }

    /// Leert die komplette Warteschlange bedingungslos — genutzt vom iCloud-Sync-Reset
    /// (`CloudSyncEngine.resetLocalState`), der alle ausstehenden Änderungen verwirft, bevor ein
    /// vollständiger Backfill sie neu einreiht.
    func deleteAll() throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM cloud_sync_pending_changes")
        }
    }

    func pendingChanges() throws -> [CloudSyncPendingChangeRecord] {
        try database.read { db in
            try CloudSyncPendingChangeRecord.fetchAll(db, sql: """
                SELECT * FROM cloud_sync_pending_changes ORDER BY queuedAt
                """)
        }
    }

    /// Liefert die Pending-Change-Zeile für eine einzelne `recordName`, falls vorhanden — nötig,
    /// um beim Ausliefern eines ausstehenden Batches (`nextRecordZoneChangeBatch`) den
    /// `recordType` zu einer bloßen `CKRecord.ID` zu ermitteln (die ID selbst trägt den Typ
    /// nicht mit).
    func pendingChange(recordName: String) throws -> CloudSyncPendingChangeRecord? {
        try database.read { db in
            try CloudSyncPendingChangeRecord.fetchOne(db, sql: """
                SELECT * FROM cloud_sync_pending_changes WHERE id = ?
                """, arguments: [recordName])
        }
    }

    /// Anzahl ausstehender Änderungen je `recordType`, für die Sync-Status-Übersicht in den
    /// Einstellungen (siehe Design-Spec
    /// `docs/superpowers/specs/2026-07-24-icloud-sync-status-uebersicht-design.md`).
    func pendingCounts() throws -> [String: Int] {
        struct RecordTypeCount: FetchableRecord, Decodable {
            let recordType: String
            let count: Int
        }
        return try database.read { db in
            let rows = try RecordTypeCount.fetchAll(db, sql: """
                SELECT recordType, COUNT(*) AS count FROM cloud_sync_pending_changes GROUP BY recordType
                """)
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.recordType, $0.count) })
        }
    }
}
