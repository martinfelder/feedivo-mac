import Foundation
import CloudKit
import GRDB

/// Mapping für die syncbare TEILMENGE der `article_statuses`-Tabelle — NUR `isRead`/
/// `isStarred` (inkl. `readAt`/`starredAt`) syncen. `isArchived`/`isHidden` bleiben bewusst
/// rein lokal (siehe Design-Spec
/// `docs/superpowers/specs/2026-07-25-icloud-sync-phase2b-design.md`, Abschnitt 1).
///
/// **Sparse Sync:** Anders als alle bisherigen Mappings umfasst `allLocalIDs` NICHT jede
/// Zeile der Tabelle, sondern nur die, deren `statusSyncUpdatedAt` gesetzt ist (der Nutzer
/// hat den Status je bewusst verändert) — siehe Abschnitt 3 der Design-Spec.
enum CloudSyncArticleStatusMapping: CloudSyncRecordMapping {
    static let recordType = "ArticleStatus"

    static func makeCKRecord(from status: ArticleStatusRecord, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: recordID(forLocalID: status.articleID))
        record["isRead"] = status.isRead as CKRecordValue
        record["isStarred"] = status.isStarred as CKRecordValue
        record["readAt"] = status.readAt as CKRecordValue?
        record["starredAt"] = status.starredAt as CKRecordValue?
        return record
    }

    struct IncomingStatus {
        let isRead: Bool
        let isStarred: Bool
        let readAt: Date?
        let starredAt: Date?
    }

    static func incomingStatus(from ckRecord: CKRecord) -> IncomingStatus? {
        guard
            let isRead = ckRecord["isRead"] as? Bool,
            let isStarred = ckRecord["isStarred"] as? Bool
        else {
            return nil
        }
        return IncomingStatus(
            isRead: isRead,
            isStarred: isStarred,
            readAt: ckRecord["readAt"] as? Date,
            starredAt: ckRecord["starredAt"] as? Date
        )
    }

    // MARK: - CloudSyncRecordMapping

    static func makeCKRecord(fromLocalID id: String, existing: CKRecord?, database: FeedivoDatabase) throws -> CKRecord? {
        guard let status = try ArticleStatusStore(database: database).status(articleID: id) else { return nil }
        return makeCKRecord(from: status, existing: existing)
    }

    /// Unterscheidet zwei Fälle: existiert der Artikel lokal bereits, wird `article_statuses`
    /// direkt aktualisiert. Existiert er noch nicht (Feed auf diesem Gerät noch nicht
    /// aktualisiert, Fremdschlüssel würde einen direkten Insert verhindern), landet der
    /// Status stattdessen in `orphaned_article_status_updates` und wird erst angewendet,
    /// sobald der Artikel per `ArticleStore.upsert()` lokal ankommt (Task 5).
    static func applyIncoming(_ record: CKRecord, database: FeedivoDatabase) throws {
        guard let incoming = incomingStatus(from: record) else { return }
        let articleID = record.recordID.recordName
        let modificationDate = record.modificationDate ?? Date()

        try database.write { db in
            let articleExists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM articles WHERE id = ?)", arguments: [articleID]) ?? false

            if articleExists {
                try db.execute(
                    sql: """
                        UPDATE article_statuses
                        SET isRead = ?, isStarred = ?, readAt = ?, starredAt = ?, statusSyncUpdatedAt = ?
                        WHERE articleID = ?
                        """,
                    arguments: [incoming.isRead, incoming.isStarred, incoming.readAt, incoming.starredAt, modificationDate, articleID]
                )
            } else {
                var orphan = OrphanedArticleStatusUpdateRecord(
                    articleID: articleID,
                    isRead: incoming.isRead,
                    isStarred: incoming.isStarred,
                    readAt: incoming.readAt,
                    starredAt: incoming.starredAt,
                    receivedAt: Date()
                )
                try orphan.save(db)
            }
        }
    }

    static func applyIncomingDeletion(recordID: CKRecord.ID, database: FeedivoDatabase) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM article_statuses WHERE articleID = ?", arguments: [recordID.recordName])
            try db.execute(sql: "DELETE FROM orphaned_article_status_updates WHERE articleID = ?", arguments: [recordID.recordName])
        }
    }

    static func localUpdatedAt(forLocalID id: String, database: FeedivoDatabase) throws -> Date? {
        try ArticleStatusStore(database: database).status(articleID: id)?.statusSyncUpdatedAt
    }

    static func allLocalIDs(database: FeedivoDatabase) throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: "SELECT articleID FROM article_statuses WHERE statusSyncUpdatedAt IS NOT NULL ORDER BY articleID")
        }
    }

    /// Enqueued `.delete` für alle `articleIDs`, deren Status je synchronisiert wurde
    /// (`statusSyncUpdatedAt IS NOT NULL`) — No-Op für nie synchronisierte Zeilen (nie ein
    /// passender `CKRecord` existierte) und wenn iCloud Sync gerade deaktiviert ist.
    /// Gemeinsamer Helfer für alle drei Löschpropagierungs-Stellen (Retention-Cleanup,
    /// Einzel-Löschung, Feed-Löschung-Kaskade, siehe Design-Spec Abschnitt 5) — muss VOR dem
    /// eigentlichen `DELETE` aufgerufen werden, in derselben `database.write`-Transaktion.
    static func enqueueDeletionIfSynced(articleIDs: [String], db: Database) throws {
        guard CloudSyncSettings.isEnabled(), !articleIDs.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: articleIDs.count).joined(separator: ", ")
        let syncedIDs = try String.fetchAll(
            db,
            sql: "SELECT articleID FROM article_statuses WHERE statusSyncUpdatedAt IS NOT NULL AND articleID IN (\(placeholders))",
            arguments: StatementArguments(articleIDs)
        )
        for articleID in syncedIDs {
            try CloudSyncPendingChangeStore.enqueue(db, recordType: recordType, recordName: articleID, changeType: .delete)
        }
    }
}
