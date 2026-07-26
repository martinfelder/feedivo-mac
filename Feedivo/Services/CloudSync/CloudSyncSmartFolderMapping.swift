import Foundation
import CloudKit
import GRDB

/// Mapping für `smart_folders` — NUR benutzerdefinierte Ordner (`isDefault == false`).
/// Eingebaute Ordner (z. B. "Ungelesen") werden pro Gerät über einen stabilen `defaultKey`
/// lokal verwaltet (`SQLiteSmartFolderStore.restoreDefaultFolders()`) und syncen NIE — jedes
/// Gerät vergibt dafür eine eigene, zufällige `id`. `isDefault`/`defaultKey` werden deshalb
/// bewusst NICHT auf das CKRecord geschrieben (ein synctes SmartFolder ist per Definition immer
/// benutzerdefiniert); `applyIncoming` verwirft defensiv trotzdem jeden eingehenden Record mit
/// gesetztem `defaultKey`, falls ein zukünftiger Bug oder ein anderer Client das doch sendet.
enum CloudSyncSmartFolderMapping: CloudSyncRecordMapping {
    static let recordType = "SmartFolder"
    static let askFields: Set<String> = ["name"]
    static let autoFields: Set<String> = ["matchMode", "isShownInSidebar", "sortOrder", "iconName", "colorHex", "defaultShowsReadArticles"]

    static func makeCKRecord(from folder: SmartFolderRecord, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: recordType, recordID: recordID(forLocalID: folder.id))
        record["name"] = folder.name as CKRecordValue
        record["matchMode"] = folder.matchMode as CKRecordValue
        record["isShownInSidebar"] = folder.isShownInSidebar as CKRecordValue
        record["sortOrder"] = folder.sortOrder as CKRecordValue
        record["iconName"] = folder.iconName as CKRecordValue?
        record["colorHex"] = folder.colorHex as CKRecordValue?
        record["defaultShowsReadArticles"] = folder.defaultShowsReadArticles as CKRecordValue
        return record
    }

    static func smartFolderRecord(from ckRecord: CKRecord) -> SmartFolderRecord? {
        guard
            let name = ckRecord["name"] as? String,
            let matchMode = ckRecord["matchMode"] as? String,
            let isShownInSidebar = ckRecord["isShownInSidebar"] as? Bool,
            let sortOrder = ckRecord["sortOrder"] as? Int,
            let defaultShowsReadArticles = ckRecord["defaultShowsReadArticles"] as? Bool
        else {
            return nil
        }

        return SmartFolderRecord(
            id: ckRecord.recordID.recordName,
            name: name,
            matchMode: matchMode,
            isShownInSidebar: isShownInSidebar,
            isDefault: false,
            sortOrder: sortOrder,
            defaultKey: nil,
            iconName: ckRecord["iconName"] as? String,
            colorHex: ckRecord["colorHex"] as? String,
            defaultShowsReadArticles: defaultShowsReadArticles,
            createdAt: ckRecord.creationDate ?? Date(),
            updatedAt: ckRecord.modificationDate ?? Date()
        )
    }

    // MARK: - CloudSyncRecordMapping

    static func makeCKRecord(fromLocalID id: String, existing: CKRecord?, database: FeedivoDatabase) throws -> CKRecord? {
        guard let folder = try SQLiteSmartFolderStore(database: database).folder(id: id), !folder.isDefault else { return nil }
        return makeCKRecord(from: folder, existing: existing)
    }

    static func applyIncoming(_ record: CKRecord, database: FeedivoDatabase) throws {
        // Schutzklausel: ein Record mit gesetztem, nicht-leerem defaultKey darf nie ankommen
        // (siehe Dokumentation oben) — defensiv verwerfen statt einen zweiten, ID-fremden
        // Default-Ordner lokal anzulegen.
        if let defaultKey = record["defaultKey"] as? String, !defaultKey.isEmpty {
            return
        }
        guard var incoming = smartFolderRecord(from: record) else { return }
        try database.write { db in
            try incoming.save(db)
        }
    }

    static func applyIncomingDeletion(recordID: CKRecord.ID, database: FeedivoDatabase) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM smart_folders WHERE id = ? AND isDefault = 0", arguments: [recordID.recordName])
        }
    }

    static func localUpdatedAt(forLocalID id: String, database: FeedivoDatabase) throws -> Date? {
        try SQLiteSmartFolderStore(database: database).folder(id: id)?.updatedAt
    }

    static func allLocalIDs(database: FeedivoDatabase) throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM smart_folders WHERE isDefault = 0")
        }
    }
}
