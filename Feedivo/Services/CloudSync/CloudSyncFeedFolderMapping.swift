import Foundation
import CloudKit
import GRDB

/// Mapping für `feed_folders` — vollständiger Sync (keine lokal-only Felder, anders als Feeds,
/// siehe `CloudSyncFeedMapping`-Dokumentation für den Kontrast). `updatedAt` ist deshalb hier
/// direkt das korrekte Last-Write-Wins-Feld, keine separate `configUpdatedAt`-Spalte nötig.
enum CloudSyncFeedFolderMapping: CloudSyncRecordMapping {
    static let recordType = "FeedFolder"
    static let askFields: Set<String> = ["name"]
    static let autoFields: Set<String> = ["sortIndex"]

    static func makeCKRecord(from folder: FeedFolderRecord, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: recordID(forLocalID: folder.id))
        record["name"] = folder.name as CKRecordValue
        record["sortIndex"] = folder.sortIndex as CKRecordValue
        return record
    }

    static func feedFolderRecord(from ckRecord: CKRecord) -> FeedFolderRecord? {
        guard
            let name = ckRecord["name"] as? String,
            let sortIndex = ckRecord["sortIndex"] as? Int
        else {
            return nil
        }

        return FeedFolderRecord(
            id: ckRecord.recordID.recordName,
            name: name,
            sortIndex: sortIndex,
            createdAt: ckRecord.creationDate ?? Date(),
            updatedAt: ckRecord.modificationDate ?? Date()
        )
    }

    // MARK: - CloudSyncRecordMapping

    static func makeCKRecord(fromLocalID id: String, existing: CKRecord?, database: FeedivoDatabase) throws -> CKRecord? {
        let folders = try FeedFolderStore(database: database).folders()
        guard let folder = folders.first(where: { $0.id == id }) else { return nil }
        return makeCKRecord(from: folder, existing: existing)
    }

    static func applyIncoming(_ record: CKRecord, database: FeedivoDatabase) throws {
        guard var incoming = feedFolderRecord(from: record) else { return }
        try database.write { db in
            try incoming.save(db)
        }
    }

    static func applyIncomingDeletion(recordID: CKRecord.ID, database: FeedivoDatabase) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM feed_folders WHERE id = ?", arguments: [recordID.recordName])
        }
    }

    static func localUpdatedAt(forLocalID id: String, database: FeedivoDatabase) throws -> Date? {
        try FeedFolderStore(database: database).folders().first(where: { $0.id == id })?.updatedAt
    }

    static func allLocalIDs(database: FeedivoDatabase) throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM feed_folders")
        }
    }
}
