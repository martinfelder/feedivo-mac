import Foundation
import CloudKit
import GRDB
import OSLog

/// Mapping für `rule_conditions` — eigener CKRecord pro Bedingungszeile. `rule_conditions.ruleID`
/// hat `ON DELETE CASCADE` + `PRAGMA foreign_keys = ON` ist aktiv: trifft eine Bedingung lokal
/// ein, BEVOR ihre Regel existiert, schlägt der Insert mit einem Fremdschlüssel-Fehler fehl.
/// `CloudSyncEngine.sortedByDependencyOrder(_:)` mindert das (Eltern vor Kindern innerhalb
/// eines Batches) — dieser verbleibende Randfall wird geloggt und übersprungen statt die
/// gesamte Sync-Pipeline zu blockieren (bewusste, dokumentierte Phase-2a-Grenze, keine
/// Retry-/Warteschlangen-Infrastruktur).
enum CloudSyncRuleConditionMapping: CloudSyncRecordMapping {
    static let recordType = "RuleCondition"

    static func makeCKRecord(from condition: RuleConditionRecord, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: recordID(forLocalID: condition.id))
        record["ruleID"] = condition.ruleID as CKRecordValue
        record["field"] = condition.field as CKRecordValue
        record["conditionOperator"] = condition.conditionOperator as CKRecordValue
        record["value"] = condition.value as CKRecordValue
        record["sortOrder"] = condition.sortOrder as CKRecordValue
        record["groupIndex"] = condition.groupIndex as CKRecordValue
        return record
    }

    static func ruleConditionRecord(from ckRecord: CKRecord) -> RuleConditionRecord? {
        guard
            let ruleID = ckRecord["ruleID"] as? String,
            let field = ckRecord["field"] as? String,
            let conditionOperator = ckRecord["conditionOperator"] as? String,
            let value = ckRecord["value"] as? String,
            let sortOrder = ckRecord["sortOrder"] as? Int,
            let groupIndex = ckRecord["groupIndex"] as? Int
        else {
            return nil
        }

        return RuleConditionRecord(
            id: ckRecord.recordID.recordName,
            ruleID: ruleID,
            field: field,
            conditionOperator: conditionOperator,
            value: value,
            sortOrder: sortOrder,
            groupIndex: groupIndex,
            updatedAt: ckRecord.modificationDate ?? Date()
        )
    }

    // MARK: - CloudSyncRecordMapping

    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord? {
        let condition = try database.read { db in
            try RuleConditionRecord.fetchOne(db, sql: "SELECT * FROM rule_conditions WHERE id = ?", arguments: [id])
        }
        guard let condition else { return nil }
        return makeCKRecord(from: condition)
    }

    static func applyIncoming(_ record: CKRecord, database: FeedivoDatabase) throws {
        guard var incoming = ruleConditionRecord(from: record) else { return }
        do {
            try database.write { db in
                try incoming.save(db)
            }
        } catch {
            // Fremdschlüssel-Verletzung: die Elternregel ist auf diesem Gerät noch nicht
            // eingetroffen (siehe Dokumentation oben). Geloggt statt propagiert, damit die
            // restliche Sync-Pipeline unbeeinträchtigt weiterläuft — bekannte Phase-2a-Grenze.
            AppLogger.dataAccess.error("iCloud Sync: RuleCondition konnte nicht gespeichert werden (Elternregel evtl. noch nicht synct): \(error.localizedDescription, privacy: .public)")
        }
    }

    static func applyIncomingDeletion(recordID: CKRecord.ID, database: FeedivoDatabase) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM rule_conditions WHERE id = ?", arguments: [recordID.recordName])
        }
    }

    static func localUpdatedAt(forLocalID id: String, database: FeedivoDatabase) throws -> Date? {
        try database.read { db in
            try Date.fetchOne(db, sql: "SELECT updatedAt FROM rule_conditions WHERE id = ?", arguments: [id])
        }
    }
}
