import Foundation
import CloudKit
import GRDB

/// Mapping für `rules` — vollständiger Sync. `assignTagID` ist eine reine String-Referenz auf
/// `tags.id`, löst sich von selbst auf, sobald der referenzierte Tag lokal existiert (kein
/// Fremdschlüssel-Constraint auf `rules.assignTagID` selbst, siehe Migration: `onDelete: .setNull`
/// statt `.cascade` — im Gegensatz zu `rule_conditions.ruleID`, siehe `CloudSyncRuleConditionMapping`).
enum CloudSyncRuleMapping: CloudSyncRecordMapping {
    static let recordType = "Rule"

    static func makeCKRecord(from rule: RuleRecord, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: recordID(forLocalID: rule.id))
        record["name"] = rule.name as CKRecordValue
        record["isEnabled"] = rule.isEnabled as CKRecordValue
        record["matchMode"] = rule.matchMode as CKRecordValue
        record["action"] = rule.action as CKRecordValue
        record["assignTagID"] = rule.assignTagID as CKRecordValue?
        record["notificationTemplate"] = rule.notificationTemplate as CKRecordValue
        record["notificationPriority"] = rule.notificationPriority as CKRecordValue
        record["sortOrder"] = rule.sortOrder as CKRecordValue
        return record
    }

    static func ruleRecord(from ckRecord: CKRecord) -> RuleRecord? {
        guard
            let name = ckRecord["name"] as? String,
            let isEnabled = ckRecord["isEnabled"] as? Bool,
            let matchMode = ckRecord["matchMode"] as? String,
            let action = ckRecord["action"] as? String,
            let notificationTemplate = ckRecord["notificationTemplate"] as? String,
            let notificationPriority = ckRecord["notificationPriority"] as? String,
            let sortOrder = ckRecord["sortOrder"] as? Int
        else {
            return nil
        }

        return RuleRecord(
            id: ckRecord.recordID.recordName,
            name: name,
            isEnabled: isEnabled,
            matchMode: matchMode,
            action: action,
            assignTagID: ckRecord["assignTagID"] as? String,
            notificationTemplate: notificationTemplate,
            notificationPriority: notificationPriority,
            sortOrder: sortOrder,
            createdAt: ckRecord.creationDate ?? Date(),
            updatedAt: ckRecord.modificationDate ?? Date()
        )
    }

    // MARK: - CloudSyncRecordMapping

    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord? {
        guard let rule = try SQLiteRuleStore(database: database).rule(id: id) else { return nil }
        return makeCKRecord(from: rule)
    }

    static func applyIncoming(_ record: CKRecord, database: FeedivoDatabase) throws {
        guard var incoming = ruleRecord(from: record) else { return }
        try database.write { db in
            try incoming.save(db)
        }
    }

    static func applyIncomingDeletion(recordID: CKRecord.ID, database: FeedivoDatabase) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM rules WHERE id = ?", arguments: [recordID.recordName])
        }
    }

    static func localUpdatedAt(forLocalID id: String, database: FeedivoDatabase) throws -> Date? {
        try SQLiteRuleStore(database: database).rule(id: id)?.updatedAt
    }
}
