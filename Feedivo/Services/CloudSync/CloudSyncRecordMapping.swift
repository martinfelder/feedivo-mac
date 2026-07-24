import Foundation
import CloudKit

/// Kontrakt für die Übersetzung zwischen einer lokalen GRDB-Zeile und einem `CKRecord`.
/// Ein konformer Typ pro syncbarer Tabelle — analog zum bestehenden `CloudSyncTagMapping`
/// (Phase 1), aber generisch abrufbar über `CloudSyncEngine`s Registry statt hart verdrahtet.
/// Alle Methoden sind statisch (die Konformität liegt auf einem `enum`/leeren `struct` pro
/// Tabelle, keine Instanzen nötig) — dadurch als Existential `any CloudSyncRecordMapping.Type`
/// in einer `[String: any CloudSyncRecordMapping.Type]`-Registry ablegbar.
protocol CloudSyncRecordMapping {
    /// CKRecord-Typname, z. B. `"Tag"`, `"Feed"`, `"RuleCondition"`. Dient gleichzeitig als
    /// Schlüssel in `CloudSyncPendingChangeRecord.recordType` — beide müssen denselben
    /// String-Raum teilen (siehe Migration v22, Task 1).
    static var recordType: String { get }

    /// CKRecord-ID für eine gegebene lokale ID, immer in der gemeinsamen `"FeedivoZone"`.
    static func recordID(forLocalID id: String) -> CKRecord.ID

    /// Lädt die aktuelle lokale Zeile und mapped sie zu einem `CKRecord` (für den Upload).
    /// Liefert `nil`, falls die Zeile lokal nicht mehr existiert (z. B. zwischenzeitlich
    /// gelöscht, aber noch in der Pending-Changes-Warteschlange).
    static func makeCKRecord(fromLocalID id: String, database: FeedivoDatabase) throws -> CKRecord?

    /// Übernimmt ein eingehendes `CKRecord` in die lokale Datenbank (Upsert).
    static func applyIncoming(_ record: CKRecord, database: FeedivoDatabase) throws

    /// Löscht die lokale Zeile mit dieser `recordID`, falls sie in DIESER Tabelle existiert.
    /// No-Op (kein Fehler), falls keine passende Zeile existiert — `CloudSyncEngine` ruft dies
    /// für ALLE registrierten Mappings auf, da eine eingehende `CKRecord.ID`-Löschung den
    /// Tabellennamen nicht mitträgt (alle Typen teilen sich dieselbe Zone). Lokale IDs sind
    /// UUIDs, Kollisionen über Tabellen hinweg praktisch ausgeschlossen.
    static func applyIncomingDeletion(recordID: CKRecord.ID, database: FeedivoDatabase) throws

    /// Lokaler Änderungszeitpunkt für die Last-Write-Wins-Konfliktauflösung, `nil` falls die
    /// Zeile nicht mehr existiert.
    static func localUpdatedAt(forLocalID id: String, database: FeedivoDatabase) throws -> Date?

    /// Alle aktuell existierenden lokalen IDs dieser Tabelle — Grundlage für den Backfill
    /// bestehender Zeilen bei jedem `CloudSyncEngine.start()` (siehe Design-Spec
    /// `docs/superpowers/specs/2026-07-24-icloud-sync-phase2a-backfill-design.md`).
    static func allLocalIDs(database: FeedivoDatabase) throws -> [String]
}

extension CloudSyncRecordMapping {
    static func recordID(forLocalID id: String) -> CKRecord.ID {
        CKRecord.ID(recordName: id, zoneID: CKRecordZone.ID(zoneName: "FeedivoZone", ownerName: CKCurrentUserDefaultName))
    }
}
