import Foundation
import CloudKit
import GRDB
import OSLog

/// Mapping für `smart_folder_conditions` — analog zu `CloudSyncRuleConditionMapping`, inkl.
/// derselben Fremdschlüssel-Randfall-Behandlung (Eltern-Ordner evtl. noch nicht synct).
/// Bedingungen zu EINGEBAUTEN Ordnern werden nie gesynct — das wird bereits dadurch
/// sichergestellt, dass `SQLiteSmartFolderStore` für `isDefault`-Ordner gar nie enqueued, nicht
/// durch eine zusätzliche Prüfung hier.
enum CloudSyncSmartFolderConditionMapping: CloudSyncRecordMapping {
    static let recordType = "SmartFolderCondition"

    static func makeCKRecord(from condition: SmartFolderConditionRecord, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: recordID(forLocalID: condition.id))
        record["smartFolderID"] = condition.smartFolderID as CKRecordValue
        record["field"] = condition.field as CKRecordValue
        record["conditionOperator"] = condition.conditionOperator as CKRecordValue
        record["value"] = condition.value as CKRecordValue
        record["sortOrder"] = condition.sortOrder as CKRecordValue
        return record
    }

    static func smartFolderConditionRecord(from ckRecord: CKRecord) -> SmartFolderConditionRecord? {
        guard
            let smartFolderID = ckRecord["smartFolderID"] as? String,
            let field = ckRecord["field"] as? String,
            let conditionOperator = ckRecord["conditionOperator"] as? String,
            let value = ckRecord["value"] as? String,
            let sortOrder = ckRecord["sortOrder"] as? Int
        else {
            return nil
        }

        return SmartFolderConditionRecord(
            id: ckRecord.recordID.recordName,
            smartFolderID: smartFolderID,
            field: field,
            conditionOperator: conditionOperator,
            value: value,
            sortOrder: sortOrder,
            updatedAt: ckRecord.modificationDate ?? Date()
        )
    }

    // MARK: - CloudSyncRecordMapping

    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord? {
        let condition = try database.read { db in
            try SmartFolderConditionRecord.fetchOne(db, sql: "SELECT * FROM smart_folder_conditions WHERE id = ?", arguments: [id])
        }
        guard let condition else { return nil }
        return makeCKRecord(from: condition)
    }

    static func applyIncoming(_ record: CKRecord, database: FeedivoDatabase) throws {
        guard var incoming = smartFolderConditionRecord(from: record) else { return }
        do {
            try database.write { db in
                try incoming.save(db)
            }
        } catch {
            // Fremdschlüssel-Verletzung: der Elternordner ist auf diesem Gerät noch nicht
            // eingetroffen (siehe Dokumentation oben). Geloggt statt propagiert, damit die
            // restliche Sync-Pipeline unbeeinträchtigt weiterläuft — bekannte Phase-2a-Grenze.
            AppLogger.dataAccess.error("iCloud Sync: SmartFolderCondition konnte nicht gespeichert werden (Elternordner evtl. noch nicht synct): \(error.localizedDescription, privacy: .public)")
        }
    }

    static func applyIncomingDeletion(recordID: CKRecord.ID, database: FeedivoDatabase) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM smart_folder_conditions WHERE id = ?", arguments: [recordID.recordName])
        }
    }

    static func localUpdatedAt(forLocalID id: String, database: FeedivoDatabase) throws -> Date? {
        try database.read { db in
            try Date.fetchOne(db, sql: "SELECT updatedAt FROM smart_folder_conditions WHERE id = ?", arguments: [id])
        }
    }
}
