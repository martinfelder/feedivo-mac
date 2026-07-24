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
struct CloudSyncPendingChangeRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "cloud_sync_pending_changes"

    var id: String
    var recordType: String
    var changeType: CloudSyncChangeType
    var queuedAt: Date
}
