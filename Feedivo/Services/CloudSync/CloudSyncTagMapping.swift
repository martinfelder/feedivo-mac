import Foundation
import CloudKit

/// Reine, CloudKit-Netzwerk-freie Mapping-Funktionen zwischen `TagRecord` (GRDB) und `CKRecord`
/// (CloudKit). `CKRecord`-Konstruktion selbst löst keinen Netzwerkzugriff aus — direkt
/// unit-testbar ohne echtes CloudKit-Konto.
enum CloudSyncTagMapping {
    static let recordType = "Tag"
    static let zoneName = "FeedivoZone"

    static func zoneID() -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    static func recordID(forTagID tagID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: tagID, zoneID: zoneID())
    }

    /// Baut ein `CKRecord` aus einem `TagRecord`. Wird `existing` übergeben (ein von
    /// `CKSyncEngine` geliefertes Record, z. B. beim erneuten Versuch nach einem
    /// Server-Konflikt), wird DIESES Objekt mutiert statt ein neues zu erzeugen — nötig, damit
    /// CloudKits interne Change-Tag-/Server-Record-Verwaltung für die `.ifServerRecordUnchanged`-
    /// Speicherpolicy erhalten bleibt.
    static func makeCKRecord(from tag: TagRecord, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: recordID(forTagID: tag.id))
        record["name"] = tag.name as CKRecordValue
        record["colorHex"] = tag.colorHex as CKRecordValue
        record["sortIndex"] = tag.sortIndex as CKRecordValue
        return record
    }

    static func tagRecord(from ckRecord: CKRecord) -> TagRecord? {
        guard
            let name = ckRecord["name"] as? String,
            let colorHex = ckRecord["colorHex"] as? String,
            let sortIndex = ckRecord["sortIndex"] as? Int
        else {
            return nil
        }

        return TagRecord(
            id: ckRecord.recordID.recordName,
            name: name,
            colorHex: colorHex,
            sortIndex: sortIndex,
            createdAt: ckRecord.creationDate ?? Date(),
            updatedAt: ckRecord.modificationDate ?? Date()
        )
    }
}
