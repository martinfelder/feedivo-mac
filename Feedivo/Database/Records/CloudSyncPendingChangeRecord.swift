import Foundation
import GRDB

/// Art der ausstehenden Änderung an einem lokal-CloudKit-gemappten Datensatz.
enum CloudSyncChangeType: String, Codable, Sendable {
    case save
    case delete
}

/// Hält fest, welche lokalen Zeilen noch nicht zu CloudKit hochgeladen wurden. `id` entspricht
/// dem `CKRecord.ID.recordName` (für Tags: `TagRecord.id`). App-eigene, durable Warteschlange —
/// zusätzlich zu `CKSyncEngine`s eigener interner State-Serialisierung, damit ein App-Absturz
/// zwischen einer lokalen Mutation und dem nächsten `CKSyncEngine`-State-Update keine
/// ausstehende Änderung stillschweigend verliert (Muster aus Apples eigenem Sample-Code
/// `apple/sample-cloudkit-sync-engine`).
///
/// `changedFields` (seit Migration v27): JSON-codierte Liste der Feldnamen, die diese konkrete
/// Mutation geändert hat — Grundlage für die Feld-Ebene-Konfliktauflösung in
/// `CloudSyncEngine.handleFailedSave` (Phase 3). `nil` für Pending-Changes ohne bekannte
/// Feldgranularität (z. B. Löschungen, oder Altbestand von vor Phase 3) — diese fallen weiterhin
/// auf das bisherige Ganz-Record-Last-Write-Wins zurück.
struct CloudSyncPendingChangeRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "cloud_sync_pending_changes"

    var id: String
    var recordType: String
    var changeType: CloudSyncChangeType
    var queuedAt: Date
    private var changedFieldsJSON: String?

    var changedFields: [String]? {
        get {
            guard let changedFieldsJSON, let data = changedFieldsJSON.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([String].self, from: data)
        }
        set {
            guard let newValue else {
                changedFieldsJSON = nil
                return
            }
            changedFieldsJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, recordType, changeType, queuedAt
        case changedFieldsJSON = "changedFields"
    }

    init(id: String, recordType: String, changeType: CloudSyncChangeType, queuedAt: Date, changedFields: [String]? = nil) {
        self.id = id
        self.recordType = recordType
        self.changeType = changeType
        self.queuedAt = queuedAt
        self.changedFieldsJSON = nil
        self.changedFields = changedFields
    }
}
