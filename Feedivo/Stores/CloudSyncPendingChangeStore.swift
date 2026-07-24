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

    func enqueue(recordType: String, recordName: String, changeType: CloudSyncChangeType) throws {
        try database.write { db in
            try Self.enqueue(db, recordType: recordType, recordName: recordName, changeType: changeType)
        }
    }

    /// Variante für Aufrufer, die bereits in einer eigenen `database.write`-Transaktion stecken
    /// (z. B. `TagStore`) — hält die fachliche Mutation und das Pending-Change-Markieren atomar.
    static func enqueue(_ db: Database, recordType: String, recordName: String, changeType: CloudSyncChangeType) throws {
        var change = CloudSyncPendingChangeRecord(
            id: recordName,
            recordType: recordType,
            changeType: changeType,
            queuedAt: Date()
        )
        try change.save(db)
    }

    func dequeue(recordName: String) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM cloud_sync_pending_changes WHERE id = ?", arguments: [recordName])
        }
    }

    func pendingChanges() throws -> [CloudSyncPendingChangeRecord] {
        try database.read { db in
            try CloudSyncPendingChangeRecord.fetchAll(db, sql: """
                SELECT * FROM cloud_sync_pending_changes ORDER BY queuedAt
                """)
        }
    }
}
