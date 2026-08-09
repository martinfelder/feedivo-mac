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
    /// `FeedFolder`-Records ab. Schlägt ein Aufruf fehl (z. B. kein Netz), liefert diese Methode
    /// für den betroffenen Typ ein leeres Array statt den Fehler zu propagieren — Duplikat-
    /// Erkennung bleibt ein Komfort-Feature, kein Sync-Gate (siehe Design-Spec Abschnitt 8),
    /// `CloudSyncEngine.start()` läuft also auch bei einem Fehlschlag hier weiter. Damit der
    /// Nutzer einen fehlgeschlagenen Check aber nicht mit einem echten "keine Duplikate
    /// gefunden" verwechselt (der Dialog sah bei beidem bisher identisch aus), liefert
    /// `fetchFailed` zusätzlich zurück, ob mindestens eine der beiden Abfragen fehlgeschlagen ist
    /// — `CloudSyncFirstActivationView` zeigt in diesem Fall eine eigene Warnung statt der
    /// positiven "keine Duplikate"-Meldung. `missingQueryableIndex` unterscheidet zusätzlich den
    /// konkreten, per Live-Log verifizierten CloudKit-Schema-Fehlschlag (siehe
    /// `isMissingQueryableIndexError`) von jedem anderen echten Fehlschlag, damit der Dialog eine
    /// gezielte statt einer generischen Meldung zeigen kann.
    static func fetchExistingCloudRecords(container: CKContainer) async -> (tags: [CKRecord], folders: [CKRecord], fetchFailed: Bool, missingQueryableIndex: Bool) {
        let database = container.privateCloudDatabase
        let zoneID = CloudSyncTagMapping.zoneID()

        async let tagsResult = fetchAllRecords(recordType: CloudSyncTagMapping.recordType, database: database, zoneID: zoneID)
        async let foldersResult = fetchAllRecords(recordType: CloudSyncFeedFolderMapping.recordType, database: database, zoneID: zoneID)
        let tagsOutcome = await tagsResult
        let foldersOutcome = await foldersResult
        return (
            tagsOutcome.records,
            foldersOutcome.records,
            !tagsOutcome.succeeded || !foldersOutcome.succeeded,
            tagsOutcome.missingQueryableIndex || foldersOutcome.missingQueryableIndex
        )
    }

    private static func fetchAllRecords(recordType: String, database: CKDatabase, zoneID: CKRecordZone.ID) async -> (records: [CKRecord], succeeded: Bool, missingQueryableIndex: Bool) {
        do {
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            let (matchResults, _) = try await database.records(matching: query, inZoneWith: zoneID)
            return (matchResults.compactMap { _, result in try? result.get() }, true, false)
        } catch {
            if isMissingZoneError(error) {
                // Bugfix (Nutzer-Report 2026-08-08): kein echter Fehlschlag, siehe
                // isMissingZoneError-Doc-Kommentar — als Erfolg mit leerem Ergebnis behandeln,
                // damit der Dialog nicht fälschlich "Prüfung nicht möglich" zeigt.
                return ([], true, false)
            }
            AppLogger.dataAccess.error("iCloud Sync: Erst-Aktivierungs-Abfrage fuer \(recordType, privacy: .public) fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return ([], false, isMissingQueryableIndexError(error))
        }
    }

    /// Pure, isoliert testbare Klassifizierung: unterscheidet `CKError.zoneNotFound` von einem
    /// echten Abfragefehler. Die `FeedivoZone` wird erst in `CloudSyncEngine.start()` angelegt
    /// (siehe `CloudSyncEngine.swift`, `hasCreatedZoneKey`-Gate) — dieser Analyzer fragt aber
    /// bewusst VOR dem allerersten `start()`-Aufruf ab (siehe Design-Spec Abschnitt 6). Bei der
    /// allerersten iCloud-Sync-Aktivierung überhaupt existiert die Zone auf dem Server deshalb
    /// noch nicht, ein `CKQuery` dagegen scheitert reproduzierbar mit `.zoneNotFound` — das
    /// bedeutet trivial "keine Cloud-Daten vorhanden", nicht "Prüfung nicht möglich", und wurde
    /// vor diesem Fix fälschlich als echter Fehlschlag behandelt (Nutzer-Report 2026-08-08: der
    /// Dialog zeigte "Prüfung nicht möglich" trotz vorhandener Netzwerkverbindung).
    static func isMissingZoneError(_ error: Error) -> Bool {
        (error as? CKError)?.code == .zoneNotFound
    }

    /// Pure, isoliert testbare Klassifizierung des tatsächlichen Fehlers, der beim Nutzer-Report
    /// 2026-08-08 per Live-Log (`/usr/bin/log stream`) nachgewiesen wurde: "Field 'recordName' is
    /// not marked queryable" (`CKError.invalidArguments`) — der `zoneNotFound`-Fix allein löste
    /// das Symptom NICHT, weil die eigentliche Ursache eine andere ist. Im CloudKit-Schema
    /// (Development-Umgebung) für die Record-Types "Tag"/"FeedFolder" fehlt ein Queryable-Index
    /// auf dem Systemfeld `recordName` — eine einmalige, manuelle Konfigurationslücke im CloudKit
    /// Dashboard (Schema → Record Type → Indexes → "Record Name" als Queryable ergänzen, dann für
    /// den Live-Betrieb zusätzlich "Deploy Schema Changes" auf Production), KEIN Code-Bug und
    /// KEIN Netzwerkproblem. Anders als bei `isMissingZoneError` bewusst KEIN automatischer
    /// Erfolgs-Fallback: eine fehlende Abfragefähigkeit bedeutet nicht "keine Daten vorhanden",
    /// sondern "wir können nicht wissen, ob Daten vorhanden sind" — ein stiller Erfolgs-Fallback
    /// würde echte Duplikate systematisch verschlucken. Wird stattdessen für eine gezielte,
    /// actionable Meldung genutzt (siehe `CloudSyncFirstActivationView`).
    static func isMissingQueryableIndexError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        return ckError.localizedDescription.localizedCaseInsensitiveContains("not marked queryable")
    }
}
