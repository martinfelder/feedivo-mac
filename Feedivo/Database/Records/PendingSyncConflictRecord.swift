import Foundation
import GRDB

/// Ein einzelner, noch nicht vom Nutzer aufgelöster Feld-Ebene-Konflikt aus
/// `CloudSyncEngine.handleFailedSave` — entsteht, wenn zwei Geräte dasselbe „Fragen"-Feld
/// (siehe `CloudSyncRecordMapping.askFields`) unterschiedlich geändert haben. Rein lokal,
/// wird selbst nicht synchronisiert. Siehe Design-Spec
/// `docs/superpowers/specs/2026-07-26-icloud-sync-phase3-design.md`, Abschnitt 5.
struct PendingSyncConflictRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "pending_sync_conflicts"

    var id: Int64?
    var recordType: String
    var recordName: String
    var fieldName: String
    var localValue: String
    var serverValue: String
    var detectedAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
