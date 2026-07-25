import Foundation
import CloudKit
import CryptoKit
import GRDB

/// Mapping für die syncbare TEILMENGE der `article_statuses`-Tabelle — NUR `isRead`/
/// `isStarred` (inkl. `readAt`/`starredAt`) syncen. `isArchived`/`isHidden` bleiben bewusst
/// rein lokal (siehe Design-Spec
/// `docs/superpowers/specs/2026-07-25-icloud-sync-phase2b-design.md`, Abschnitt 1).
///
/// **Sparse Sync:** Anders als alle bisherigen Mappings umfasst `allLocalIDs` NICHT jede
/// Zeile der Tabelle, sondern nur die, deren `statusSyncUpdatedAt` gesetzt ist (der Nutzer
/// hat den Status je bewusst verändert) — siehe Abschnitt 3 der Design-Spec.
///
/// **Stabile Identität:** Die `CKRecord.ID` basiert auf `ArticleStatusRecord.syncStableID`
/// (ein aus `feedID`+`sourceID`/`link`/`titleHash` abgeleiteter Hash), NICHT auf der lokalen
/// `articleID` — Artikel selbst werden nie synct, jedes Gerät vergibt beim eigenen
/// Feed-Refresh eine eigene, zufällige `articles.id`-UUID für denselben logischen Artikel.
/// Siehe `stableRecordName` unten für die Herleitung.
enum CloudSyncArticleStatusMapping: CloudSyncRecordMapping {
    static let recordType = "ArticleStatus"

    /// Geräteübergreifend deterministische Identität für einen Artikel-Status — exakt
    /// dieselbe Prioritätsreihenfolge (`sourceID` vor `link` vor `titleHash`) wie die
    /// bestehende `ArticleStore.findExistingArticleID`/`findIdentityHistory`-Identitätslogik.
    /// `feedID` ist bereits geräteübergreifend stabil, da Feeds per CloudKit-Sync-ID
    /// übernommen werden (Phase 2a), nicht unabhängig neu erzeugt.
    static func stableRecordName(feedID: String, sourceID: String?, link: String?, titleHash: String) -> String {
        let identityComponent = sourceID ?? link ?? titleHash
        let digest = SHA256.hash(data: Data("\(feedID)|\(identityComponent)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Baut ein `CKRecord` aus einem `ArticleStatusRecord`. Setzt voraus, dass
    /// `status.syncStableID` bereits gesetzt ist — gilt für jede Zeile, die über
    /// `allLocalIDs`/`makeCKRecord(fromLocalID:)` erreicht wird, da diese Zeilen zwingend
    /// bereits eine berechnete `syncStableID` besitzen (jede `article_statuses`-Zeile bekommt
    /// sie beim Insert in `ArticleStore.upsert`, unabhängig vom Sync-Berührt-Status).
    static func makeCKRecord(from status: ArticleStatusRecord, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: recordID(forLocalID: status.syncStableID!))
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

    /// `id` ist hier eine `syncStableID`, keine lokale `articleID`.
    static func makeCKRecord(fromLocalID id: String, existing: CKRecord?, database: FeedivoDatabase) throws -> CKRecord? {
        guard let status = try ArticleStatusStore(database: database).status(syncStableID: id) else { return nil }
        return makeCKRecord(from: status, existing: existing)
    }

    /// `record.recordID.recordName` ist die `syncStableID` des Absenders. Unterscheidet
    /// zwei Fälle: existiert lokal bereits eine `article_statuses`-Zeile mit dieser
    /// `syncStableID` (der Artikel wurde hier ebenfalls schon per Feed-Refresh entdeckt),
    /// wird sie direkt aktualisiert. Existiert noch keine (Feed auf diesem Gerät noch nicht
    /// aktualisiert), landet der Status in `orphaned_article_status_updates`, keyed über
    /// dieselbe `syncStableID` — wird erst angewendet, sobald der Artikel per
    /// `ArticleStore.upsert()` lokal ankommt und dabei dieselbe `syncStableID` berechnet
    /// (Task 11).
    static func applyIncoming(_ record: CKRecord, database: FeedivoDatabase) throws {
        guard let incoming = incomingStatus(from: record) else { return }
        let stableID = record.recordID.recordName
        let modificationDate = record.modificationDate ?? Date()

        try database.write { db in
            let localExists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM article_statuses WHERE syncStableID = ?)", arguments: [stableID]) ?? false

            if localExists {
                try db.execute(
                    sql: """
                        UPDATE article_statuses
                        SET isRead = ?, isStarred = ?, readAt = ?, starredAt = ?, statusSyncUpdatedAt = ?
                        WHERE syncStableID = ?
                        """,
                    arguments: [incoming.isRead, incoming.isStarred, incoming.readAt, incoming.starredAt, modificationDate, stableID]
                )
            } else {
                var orphan = OrphanedArticleStatusUpdateRecord(
                    articleID: stableID,
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

    /// Setzt den lokalen Status auf Defaults zurück, statt die Zeile zu löschen — falls der
    /// Artikel lokal noch existiert, würde ein echtes `DELETE` die `article_statuses`-Zeile
    /// entfernen, obwohl `articles` die Zeile noch hat; jede Artikellisten-Abfrage nutzt
    /// aber einen INNER JOIN auf `article_statuses`, wodurch der Artikel unsichtbar würde,
    /// obwohl der Nutzer den Feed weiterhin abonniert hat (gefunden im Whole-Branch-Review
    /// von Phase 2b). `syncStableID` bleibt dabei BEWUSST erhalten (nicht NULL) — sie wird
    /// nirgends sonst automatisch neu berechnet, ein Zurücksetzen würde die Zeile dauerhaft
    /// aus jeder künftigen Sync-Betrachtung ausschließen, selbst wenn der Nutzer den Artikel
    /// später erneut liest/mit Stern markiert (gefunden im Task-12-Re-Review). Existiert
    /// lokal keine Zeile mit dieser `syncStableID`, ist das UPDATE ein No-Op — zusätzlich
    /// wird ein ggf. wartender Orphan-Eintrag entfernt.
    static func applyIncomingDeletion(recordID: CKRecord.ID, database: FeedivoDatabase) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE article_statuses
                    SET isRead = 0, isStarred = 0, readAt = NULL, starredAt = NULL, statusSyncUpdatedAt = NULL
                    WHERE syncStableID = ?
                    """,
                arguments: [recordID.recordName]
            )
            try db.execute(sql: "DELETE FROM orphaned_article_status_updates WHERE articleID = ?", arguments: [recordID.recordName])
        }
    }

    static func localUpdatedAt(forLocalID id: String, database: FeedivoDatabase) throws -> Date? {
        try ArticleStatusStore(database: database).status(syncStableID: id)?.statusSyncUpdatedAt
    }

    static func allLocalIDs(database: FeedivoDatabase) throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: """
                SELECT syncStableID FROM article_statuses
                WHERE statusSyncUpdatedAt IS NOT NULL AND syncStableID IS NOT NULL
                ORDER BY syncStableID
                """)
        }
    }

    /// Enqueued `.delete` für die `syncStableID` jeder `articleID` aus `articleIDs`, deren
    /// Status je synchronisiert wurde (`statusSyncUpdatedAt IS NOT NULL`) — No-Op für nie
    /// synchronisierte Zeilen und wenn iCloud Sync gerade deaktiviert ist. Aufrufer
    /// (Löschpropagierung, Tasks 7/8/9 der ursprünglichen Phase-2b-Implementierung)
    /// arbeiten mit lokalen `articleID`s (das ist, was sie beim Löschen kennen) — diese
    /// Methode übersetzt intern auf die für CloudKit relevante `syncStableID`.
    static func enqueueDeletionIfSynced(articleIDs: [String], db: Database) throws {
        guard CloudSyncSettings.isEnabled(), !articleIDs.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: articleIDs.count).joined(separator: ", ")
        let syncedStableIDs = try String.fetchAll(
            db,
            sql: """
                SELECT syncStableID FROM article_statuses
                WHERE statusSyncUpdatedAt IS NOT NULL AND syncStableID IS NOT NULL AND articleID IN (\(placeholders))
                """,
            arguments: StatementArguments(articleIDs)
        )
        for stableID in syncedStableIDs {
            try CloudSyncPendingChangeStore.enqueue(db, recordType: recordType, recordName: stableID, changeType: .delete)
        }
    }
}
