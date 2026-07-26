import Foundation
import CloudKit
import OSLog

/// Läuft einmalig VOR dem ersten Backfill, wenn iCloud Sync neu aktiviert wird (siehe Task 14).
/// Erkennt Namensduplikate zwischen bereits in der Cloud vorhandenen `Tag`/`FeedFolder`-Records
/// und den lokal vorhandenen Zeilen — löst das dokumentierte `materializeImplicitFolders()`-
/// Duplikat-Risiko aus dem Phase-2a-Whole-Branch-Review mit. Siehe Design-Spec
/// `docs/superpowers/specs/2026-07-26-icloud-sync-phase3-design.md`, Abschnitt 6.
enum CloudSyncFirstActivationAnalyzer {
    struct FirstActivationCollision {
        let recordType: String
        let name: String
        let localID: String
        let cloudRecordID: CKRecord.ID
    }

    /// Reine Vergleichsfunktion, kein Netzwerkzugriff — nimmt bereits abgefragte Cloud-`CKRecord`s
    /// entgegen (siehe `fetchExistingCloudRecords` für den echten `CKQuery`-Aufruf). Case-
    /// insensitiver Namensvergleich, exakt wie der bestehende Duplikat-Check in
    /// `FeedFolderStore.renameFolder`.
    ///
    /// **Selbst-Match-Ausschluss (Review-Fix, Task 14):** Da `CKRecord.ID.recordName` für Tags/
    /// FeedFolders identisch mit der lokalen `id` ist (siehe `CloudSyncTagMapping.recordID(forTagID:)`/
    /// `CloudSyncFeedFolderMapping.recordID(forLocalID:)`), matcht ein bereits synchronisierter
    /// Datensatz bei jeder erneuten Aktivierung (Aus→Ein-Toggle, nicht nur der allerersten
    /// überhaupt) sonst zwangsläufig SICH SELBST über den Namen — die Analyse läuft laut Design
    /// bewusst bei JEDEM Off→On-Übergang erneut, nicht nur beim ersten Mal. Ohne diesen
    /// Ausschluss würde ein solcher Selbst-Match als echte Kollision gemeldet, deren
    /// vorausgewählte Standardaktion „Zusammenführen" ist — ein Merge von `oldTagID == newTagID`
    /// lässt `remapTagReferences` jede Zuordnung fälschlich als „hat newTag schon" erkennen und
    /// löschen, dann den Tag selbst löschen: vollständiger, nicht wiederherstellbarer Datenverlust
    /// für genau den Tag, der eigentlich nur bestätigt schon synct. Ein Datensatz, dessen lokale
    /// `id` bereits dem `recordName` des matchenden Cloud-Records entspricht, ist deshalb NIE
    /// eine Kollision — er ist derselbe, bereits synchronisierte Datensatz.
    static func findCollisions(database: FeedivoDatabase, tagRecords: [CKRecord], folderRecords: [CKRecord]) throws -> [FirstActivationCollision] {
        var collisions: [FirstActivationCollision] = []

        let localTags = try TagStore(database: database).tags()
        for cloudRecord in tagRecords {
            guard let cloudName = cloudRecord["name"] as? String else { continue }
            if let match = localTags.first(where: {
                $0.name.caseInsensitiveCompare(cloudName) == .orderedSame && $0.id != cloudRecord.recordID.recordName
            }) {
                collisions.append(FirstActivationCollision(recordType: CloudSyncTagMapping.recordType, name: match.name, localID: match.id, cloudRecordID: cloudRecord.recordID))
            }
        }

        let localFolders = try FeedFolderStore(database: database).folders()
        for cloudRecord in folderRecords {
            guard let cloudName = cloudRecord["name"] as? String else { continue }
            if let match = localFolders.first(where: {
                $0.name.caseInsensitiveCompare(cloudName) == .orderedSame && $0.id != cloudRecord.recordID.recordName
            }) {
                collisions.append(FirstActivationCollision(recordType: CloudSyncFeedFolderMapping.recordType, name: match.name, localID: match.id, cloudRecordID: cloudRecord.recordID))
            }
        }

        return collisions
    }

    /// Echter `CKQuery`-Aufruf gegen `FeedivoZone` — fragt ALLE bestehenden `Tag`- und
    /// `FeedFolder`-Records ab. Schlägt der Aufruf fehl (z. B. kein Netz), liefert diese Methode
    /// leere Arrays statt den Fehler zu propagieren — Duplikat-Erkennung ist ein
    /// Komfort-Feature, kein Sync-Gate (siehe Design-Spec Abschnitt 8).
    static func fetchExistingCloudRecords(container: CKContainer) async -> (tags: [CKRecord], folders: [CKRecord]) {
        let database = container.privateCloudDatabase
        let zoneID = CloudSyncTagMapping.zoneID()

        async let tags = fetchAllRecords(recordType: CloudSyncTagMapping.recordType, database: database, zoneID: zoneID)
        async let folders = fetchAllRecords(recordType: CloudSyncFeedFolderMapping.recordType, database: database, zoneID: zoneID)
        return (await tags, await folders)
    }

    private static func fetchAllRecords(recordType: String, database: CKDatabase, zoneID: CKRecordZone.ID) async -> [CKRecord] {
        do {
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            let (matchResults, _) = try await database.records(matching: query, inZoneWith: zoneID)
            return matchResults.compactMap { _, result in try? result.get() }
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: Erst-Aktivierungs-Abfrage fuer \(recordType, privacy: .public) fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
