import Foundation
import GRDB

struct PendingSyncConflictStore {
    private let database: FeedivoDatabase

    init(database: FeedivoDatabase) {
        self.database = database
    }

    /// Vermerkt einen neuen Feld-Ebene-Konflikt — dedupliziert bewusst auf `(recordType,
    /// recordName, fieldName)` (Review-Fund C3): Ein Konflikt, der noch nicht vom Nutzer
    /// aufgelöst wurde, bleibt in der Pending-Change-Warteschlange stehen und wird bei jedem
    /// weiteren, unabhängigen Sendeversuch erneut denselben `.serverRecordChanged`-Fehler
    /// auslösen — ohne diese Dedupe-Prüfung würde `handleFailedSave` bei jedem dieser
    /// Wiederholungsversuche eine weitere, inhaltlich identische Zeile in
    /// `pending_sync_conflicts` anlegen, bis der Nutzer irgendwann eine lange Liste
    /// duplizierter Konflikte für dasselbe Feld sähe.
    func record(recordType: String, recordName: String, fieldName: String, localValue: String, serverValue: String) throws {
        try database.write { db in
            let alreadyPending = try Bool.fetchOne(
                db,
                sql: """
                    SELECT EXISTS(
                        SELECT 1 FROM pending_sync_conflicts
                        WHERE recordType = ? AND recordName = ? AND fieldName = ?
                    )
                    """,
                arguments: [recordType, recordName, fieldName]
            ) ?? false
            guard !alreadyPending else { return }

            var conflict = PendingSyncConflictRecord(
                id: nil,
                recordType: recordType,
                recordName: recordName,
                fieldName: fieldName,
                localValue: localValue,
                serverValue: serverValue,
                detectedAt: Date()
            )
            try conflict.insert(db)
        }
    }

    func conflicts() throws -> [PendingSyncConflictRecord] {
        try database.read { db in
            try PendingSyncConflictRecord.fetchAll(db, sql: "SELECT * FROM pending_sync_conflicts ORDER BY detectedAt")
        }
    }

    func conflicts(recordType: String, recordName: String) throws -> [PendingSyncConflictRecord] {
        try database.read { db in
            try PendingSyncConflictRecord.fetchAll(
                db,
                sql: "SELECT * FROM pending_sync_conflicts WHERE recordType = ? AND recordName = ?",
                arguments: [recordType, recordName]
            )
        }
    }

    func resolve(id: Int64) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM pending_sync_conflicts WHERE id = ?", arguments: [id])
        }
    }

    func count() throws -> Int {
        try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pending_sync_conflicts") ?? 0
        }
    }
}
