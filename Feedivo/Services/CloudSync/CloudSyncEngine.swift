import Foundation
import CloudKit
import GRDB
import OSLog

/// Wrapper um Apples `CKSyncEngine` für die private CloudKit-Datenbank. Läuft komplett auf dem
/// MainActor (Projektkonvention, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). `start()`/`stop()`
/// sind bewusst so gebaut, dass sie ohne App-Neustart aufgerufen werden können (Toggle in den
/// Einstellungen wirkt sofort).
@MainActor
final class CloudSyncEngine: NSObject {
    static let stateSerializationKey = "cloudSync.stateSerialization"
    static let hasCreatedZoneKey = "cloudSync.hasCreatedZone"

    private let database: FeedivoDatabase
    private let pendingChangeStore: CloudSyncPendingChangeStore

    /// Kurzlebiger Zwischenspeicher für Server-Records aus aufgelösten Konflikten — wird von
    /// `handleFailedSave` beim "lokal gewinnt"-Pfad befüllt und von `record(forPendingChange:)`
    /// konsultiert, damit der nächste Sendeversuch die korrekten Server-Systemfelder
    /// (Change-Tag) wiederverwendet, statt erneut ein jungfräuliches CKRecord zu bauen (das
    /// sonst garantiert wieder mit `.serverRecordChanged` scheitern würde). Rein In-Memory,
    /// bewusst nicht persistiert — überlebt einen Konflikt-Retry innerhalb derselben Sync-
    /// Session; nach einem App-Neustart liefert der nächste Sendeversuch ohnehin erneut den
    /// aktuellen Server-Stand über einen neuen `.serverRecordChanged`-Fehler. Siehe Design-Spec
    /// `docs/superpowers/specs/2026-07-24-icloud-sync-konfliktaufloesung-fix-design.md`.
    private var knownServerRecordsByID: [CKRecord.ID: CKRecord] = [:]
    let status = CloudSyncStatus()

    private var syncEngine: CKSyncEngine?
    private var startTask: Task<Void, Never>?

    /// Prozessweite Referenz auf die aktuell laufende Engine-Instanz, einmalig von
    /// `FeedivoApp` beim Start gesetzt (siehe `register(_:)`). Ermöglicht `TagStore` (und
    /// künftig weiteren Stores), die laufende Engine sofort über eine neue ausstehende
    /// Änderung zu informieren, statt nur die App-eigene Warteschlange zu befüllen — ohne
    /// Dependency Injection durch alle TagStore-Aufrufstellen im gesamten Projekt
    /// durchzureichen.
    private static var current: CloudSyncEngine?

    /// Registry aller syncbaren Tabellen, Schlüssel = `CloudSyncRecordMapping.recordType`.
    /// Erweitert in den Folge-Tasks um Feed/FeedFolder/Rule/RuleCondition/SmartFolder/
    /// SmartFolderCondition. `nonisolated`, da rein statischer, unveränderlicher Inhalt (keine
    /// Instanz-/Actor-Zustandsabhängigkeit) — ermöglicht synchronen Zugriff aus Tests heraus,
    /// ohne dass diese selbst `@MainActor`/`async` sein müssen (analog zum bestehenden
    /// `AppIconBadgeService`-Muster, siehe Gotcha zu `SWIFT_DEFAULT_ACTOR_ISOLATION` in
    /// CLAUDE.md).
    private nonisolated static let registry: [String: any CloudSyncRecordMapping.Type] = [
        CloudSyncTagMapping.recordType: CloudSyncTagMapping.self,
        CloudSyncFeedMapping.recordType: CloudSyncFeedMapping.self,
        CloudSyncFeedFolderMapping.recordType: CloudSyncFeedFolderMapping.self,
        CloudSyncRuleMapping.recordType: CloudSyncRuleMapping.self,
        CloudSyncRuleConditionMapping.recordType: CloudSyncRuleConditionMapping.self,
        CloudSyncSmartFolderMapping.recordType: CloudSyncSmartFolderMapping.self,
        CloudSyncSmartFolderConditionMapping.recordType: CloudSyncSmartFolderConditionMapping.self,
        CloudSyncArticleStatusMapping.recordType: CloudSyncArticleStatusMapping.self
    ]

    nonisolated static func mapping(forRecordType recordType: String) -> (any CloudSyncRecordMapping.Type)? {
        registry[recordType]
    }

    /// Sortiert eingehende Records so, dass "Eltern"-Typen (die von keiner anderen Tabelle per
    /// Fremdschlüssel referenziert werden) vor ihren "Kind"-Typen stehen — `rule_conditions`/
    /// `smart_folder_conditions` haben einen `ON DELETE CASCADE`-Fremdschlüssel auf ihre
    /// Elterntabelle UND `PRAGMA foreign_keys = ON` ist aktiv (`FeedivoDatabase.swift`). Träfe
    /// eine Bedingungszeile lokal ein, BEVOR ihre Regel/ihr Intelligenter Ordner existiert,
    /// würde der Insert mit einem Fremdschlüssel-Fehler scheitern. `CKSyncEngine` garantiert
    /// innerhalb eines Batches keine Reihenfolge — dieses Sortieren deckt den Normalfall ab
    /// (Eltern + Kinder werden zusammen bearbeitet und kommen im selben Batch an).
    private nonisolated static let childRecordTypes: Set<String> = ["RuleCondition", "SmartFolderCondition"]

    nonisolated static func sortedByDependencyOrder(_ records: [CKRecord]) -> [CKRecord] {
        records.sorted { lhs, rhs in
            let lhsIsChild = childRecordTypes.contains(lhs.recordType)
            let rhsIsChild = childRecordTypes.contains(rhs.recordType)
            if lhsIsChild == rhsIsChild { return false }
            return !lhsIsChild
        }
    }

    init(database: FeedivoDatabase) {
        self.database = database
        self.pendingChangeStore = CloudSyncPendingChangeStore(database: database)
        super.init()
    }

    func start() {
        guard syncEngine == nil, startTask == nil else { return }

        startTask = Task {
            let container = CKContainer(identifier: CloudSyncSettings.cloudKitContainerIdentifier)

            let accountStatus: CKAccountStatus
            do {
                accountStatus = try await container.accountStatus()
            } catch {
                AppLogger.dataAccess.error("iCloud Sync: Konto-Status konnte nicht ermittelt werden: \(error.localizedDescription, privacy: .public)")
                accountStatus = .couldNotDetermine
            }

            guard !Task.isCancelled else { return }

            guard accountStatus == .available else {
                status.state = .accountUnavailable
                return
            }

            let storedSerialization = Self.loadStateSerialization()
            var configuration = CKSyncEngine.Configuration(
                database: container.privateCloudDatabase,
                stateSerialization: storedSerialization,
                delegate: self
            )
            configuration.automaticallySync = true

            let engine = CKSyncEngine(configuration)

            guard !Task.isCancelled else { return }
            self.syncEngine = engine

            if !UserDefaults.standard.bool(forKey: Self.hasCreatedZoneKey) {
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudSyncTagMapping.zoneID()))])
                UserDefaults.standard.set(true, forKey: Self.hasCreatedZoneKey)
            }

            do {
                try Self.backfillAllExistingRecords(database: database)
            } catch {
                AppLogger.dataAccess.error("iCloud Sync: Backfill bestehender Eintraege fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }

            Self.notifyPendingChangesAvailable(database: database)

            status.state = .idle
        }
    }

    func stop() {
        // Muss auf JEDEM Teardown-Pfad geleert werden (normales Ausschalten, Soft Reset, Hard
        // Reset — beide Resets rufen intern stop() auf): ein Hard Reset löscht die komplette
        // CloudKit-Zone, ein hier noch zwischengespeicherter Server-Record mit einem
        // Change-Tag für einen jetzt gelöschten Datensatz würde sonst beim nächsten Sendeversuch
        // dauerhaft scheitern — genau die Fehlerklasse, die dieses Reset-Feature eigentlich
        // beheben soll.
        knownServerRecordsByID.removeAll()
        startTask?.cancel()
        startTask = nil
        syncEngine = nil
        status.state = .idle
    }

    /// Setzt den kompletten lokalen Sync-Zustand zurück: laufende Engine anhalten, gespeicherten
    /// CKSyncEngine-Zustand + Zone-Erzeugt-Flag löschen, lokale Pending-Warteschlange und
    /// verwaiste Artikelstatus-Einträge leeren, persistenten Aktivitätsstatus zurücksetzen. Ist
    /// iCloud Sync aktiviert, wird die Engine anschließend neu gestartet — das löst automatisch
    /// einen vollständigen Backfill aus (`start()` ruft `backfillAllExistingRecords` bei jedem
    /// Start auf, kein einmaliges Flag), der alle lokalen Daten erneut als "zu senden" einreiht.
    /// Die CloudKit-Zone selbst bleibt dabei unangetastet — siehe
    /// `resetCloudZoneAndLocalState` für die zerstörerische Variante. Siehe Design-Spec
    /// docs/superpowers/specs/2026-07-25-icloud-sync-reset-design.md.
    func resetLocalState(database: FeedivoDatabase, userDefaults: UserDefaults = .standard) {
        stop()
        userDefaults.removeObject(forKey: Self.stateSerializationKey)
        userDefaults.removeObject(forKey: Self.hasCreatedZoneKey)

        do {
            try CloudSyncPendingChangeStore(database: database).deleteAll()
        } catch {
            AppLogger.dataAccess.error("iCloud Sync Reset: Pending-Warteschlange konnte nicht geleert werden: \(error.localizedDescription, privacy: .public)")
        }
        do {
            try OrphanedArticleStatusUpdateStore(database: database).deleteAll()
        } catch {
            AppLogger.dataAccess.error("iCloud Sync Reset: Verwaiste Artikelstatus-Einträge konnten nicht geleert werden: \(error.localizedDescription, privacy: .public)")
        }
        CloudSyncActivityStatus.reset(userDefaults: userDefaults)

        if CloudSyncSettings.isEnabled(in: userDefaults) {
            start()
        }
    }

    /// Löscht zusätzlich zum lokalen Zustand (siehe `resetLocalState`) die komplette
    /// `FeedivoZone` in CloudKit und lässt sie beim nächsten `start()` komplett neu aus dem
    /// lokalen Stand aufbauen. Betrifft ALLE Geräte des Nutzers — jedes andere Gerät hat danach
    /// einen `stateSerialization`-Stand gegenüber einer nicht mehr existierenden Zone und muss
    /// sich beim nächsten eigenen Sync-Versuch eigenständig neu einrichten (siehe Design-Spec,
    /// Abschnitt "Hard Reset"). Schlägt der Netzwerkaufruf fehl (außer `.zoneNotFound`, das
    /// bereits eine gelöschte Zone bedeutet und deshalb kein Fehler ist), bleibt der lokale
    /// Zustand komplett unangetastet und die Engine wird wieder in ihren vorherigen Zustand
    /// versetzt, damit der Nutzer es erneut versuchen kann.
    func resetCloudZoneAndLocalState(database: FeedivoDatabase) async throws {
        // `startTask != nil` zählt bewusst mit: ein noch laufender start()-Task hat `syncEngine`
        // evtl. noch nicht gesetzt, ist aber konzeptionell bereits "läuft/startet gerade" — ohne
        // diese zweite Bedingung würde ein fehlgeschlagenes Zone-Löschen die Engine in diesem
        // schmalen Zeitfenster faelschlich NICHT neu starten.
        let wasRunning = syncEngine != nil || startTask != nil
        stop()

        let container = CKContainer(identifier: CloudSyncSettings.cloudKitContainerIdentifier)
        do {
            _ = try await container.privateCloudDatabase.deleteRecordZone(withID: CloudSyncTagMapping.zoneID())
        } catch let error as CKError where error.code == .zoneNotFound {
            // Zone existiert bereits nicht mehr (z. B. vorheriger Hard Reset ohne Neustart) —
            // aus Nutzersicht kein Fehler, einfach mit dem lokalen Reset fortfahren.
        } catch {
            if wasRunning {
                start()
            }
            throw error
        }

        resetLocalState(database: database)
    }

    /// Registriert die eine, prozessweite `CloudSyncEngine`-Instanz. Wird einmalig von
    /// `FeedivoApp.init()` aufgerufen.
    static func register(_ engine: CloudSyncEngine) {
        current = engine
    }

    /// Informiert die laufende Engine über alle aktuell in der App-eigenen Warteschlange
    /// stehenden Änderungen. Aufrufer (z. B. `TagStore`-Mutationen) rufen dies nach einer
    /// erfolgreichen Transaktion auf, damit neue Änderungen sofort gesendet werden, statt
    /// erst beim nächsten `start()` (App-Neustart oder Sync-Toggle aus/an) nachgeholt zu
    /// werden. Läuft Sync gerade nicht (Toggle aus, oder App noch beim Start), ist dieser
    /// Aufruf ein No-Op — die Änderung bleibt in der Warteschlange stehen und wird beim
    /// nächsten `start()` ohnehin rehydriert.
    static func notifyPendingChangesAvailable(database: FeedivoDatabase) {
        guard let syncEngine = current?.syncEngine else { return }
        guard let pending = try? CloudSyncPendingChangeStore(database: database).pendingChanges(), !pending.isEmpty else {
            return
        }
        let changes: [CKSyncEngine.PendingRecordZoneChange] = pending.compactMap { change in
            guard let mapping = Self.mapping(forRecordType: change.recordType) else { return nil }
            let recordID = mapping.recordID(forLocalID: change.id)
            switch change.changeType {
            case .save:
                return .saveRecord(recordID)
            case .delete:
                return .deleteRecord(recordID)
            }
        }
        syncEngine.state.add(pendingRecordZoneChanges: changes)

        // `automaticallySync` verlässt sich auf Apples System-Task-Scheduler und sendet nicht
        // sofort (siehe WWDC23 "Sync to iCloud with CKSyncEngine": der Scheduler konsultiert
        // erst Systembedingungen wie Akku/Netzwerk, bevor er tatsächlich sendet — das kann
        // beliebig lange dauern). Für eine interaktive App, bei der der Nutzer nach einer
        // Änderung eine zeitnahe Sync-Bestätigung erwartet, reicht automatisches Planen allein
        // nicht — deshalb hier zusätzlich explizit `sendChanges()` anstoßen (Apples dokumentierte
        // "manual override" für genau diesen Fall), statt uns nur auf automatische Planung zu
        // verlassen.
        //
        // **Bewusst `Task.detached`, nicht `Task { ... }`:** Diese Methode wird auch aus
        // `handleFailedSave` heraus aufgerufen (Konfliktauflösungspfad), der selbst innerhalb
        // von `CKSyncEngineDelegate.handleEvent` läuft. `sendChanges()` ruft intern wieder in
        // den Delegate zurück (`nextRecordZoneChangeBatch`) — ein normaler, nicht-detachter
        // `Task {}` erbt den Actor-/Ausführungskontext des aufrufenden Delegate-Callbacks und
        // wird von CKSyncEngine deshalb weiterhin als "innerhalb des Callbacks" betrachtet, was
        // zu einem Fatal Error führt ("BUG IN CLIENT OF CLOUDKIT: Cannot await a call into
        // CKSyncEngine from within a delegate callback ... Try performing this in a detached
        // Task", live reproduziert 2026-07-24 beim wiederholten Testen der Sync-Status-
        // Übersicht, sobald ein echter Server-Konflikt auftrat). `Task.detached` verlässt den
        // Actor-Kontext vollständig und ist an allen drei Aufrufstellen dieser Methode sicher
        // (auch an den beiden unkritischen: `start()` und Store-Mutationen außerhalb jedes
        // Delegate-Callbacks).
        Task.detached {
            do {
                try await syncEngine.sendChanges()
            } catch {
                AppLogger.dataAccess.error("iCloud Sync: Sofortiges Senden fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Reiht alle aktuell existierenden lokalen Zeilen aller registrierten Tabellen erneut als
    /// `.save` in die Pending-Sync-Queue ein — läuft bei JEDEM `start()`, kein einmaliges Flag
    /// (siehe Design-Spec `docs/superpowers/specs/2026-07-24-icloud-sync-phase2a-backfill-design.md`).
    /// Deckt sowohl echte Altbestände (vor Sync-Aktivierung angelegt) als auch Bearbeitungen ab,
    /// die passierten, während Sync ausgeschaltet war — `TagStore`/`FeedStore`/etc. markieren
    /// Mutationen nur dann als pending, wenn `CloudSyncSettings.isEnabled()` zum
    /// Mutationszeitpunkt bereits `true` war. Ein erneutes `.save` für eine bereits
    /// unveränderte, längst synchronisierte Zeile ist harmlos (CloudKit behandelt es als
    /// inhaltlich identisches Update). Löschungen, die während Sync-aus passierten, werden
    /// bewusst NICHT nachträglich gemeldet — das kennt nur den aktuellen lokalen Stand.
    ///
    /// `nonisolated`, analog zu `mapping(forRecordType:)`/`sortedByDependencyOrder` oben —
    /// ermöglicht synchronen Zugriff aus Tests heraus, ohne dass diese selbst `@MainActor`/
    /// `async` sein müssen. Sichtbarkeit bewusst `internal` (nicht `private`), damit Tests die
    /// Methode direkt aufrufen können.
    ///
    /// **Lese- und Schreibphase sind bewusst strikt voneinander getrennt:**
    /// `mapping.allLocalIDs(database:)` nutzt intern `database.read`. GRDBs `DatabaseQueue` ist
    /// laut eigenem Quellcode (`SerializedDatabase.sync`:
    /// `GRDBPrecondition(!watchdog.allows(db), "Database methods are not reentrant.")`)
    /// NICHT reentrant — ein `database.read`-Aufruf von INNERHALB eines bereits laufenden
    /// `database.write`-Blocks auf DERSELBEN `DatabaseQueue` würde deshalb hart per Precondition
    /// abstürzen, nicht nur ein Deadlock-Risiko sein. Alle lokalen IDs werden deshalb zuerst
    /// vollständig über mehrere unabhängige `read`-Zugriffe eingesammelt, bevor überhaupt ein
    /// einziger `database.write`-Block geöffnet wird, der dann nur noch reine INSERT/REPLACE-
    /// Statements gegen `cloud_sync_pending_changes` ausführt.
    nonisolated static func backfillAllExistingRecords(database: FeedivoDatabase) throws {
        var idsByMapping: [(mapping: any CloudSyncRecordMapping.Type, ids: [String])] = []
        for mapping in Self.registry.values {
            do {
                let ids = try mapping.allLocalIDs(database: database)
                idsByMapping.append((mapping, ids))
            } catch {
                AppLogger.dataAccess.error("iCloud Sync: Backfill-Lesen fuer \(mapping.recordType, privacy: .public) fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }

        try database.write { db in
            for (mapping, ids) in idsByMapping {
                do {
                    for id in ids {
                        try CloudSyncPendingChangeStore.enqueue(db, recordType: mapping.recordType, recordName: id, changeType: .save)
                    }
                } catch {
                    AppLogger.dataAccess.error("iCloud Sync: Backfill-Einreihen fuer \(mapping.recordType, privacy: .public) fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        // Ohne diesen Bump bleibt die Ausstehend-Anzeige in den Einstellungen (die auf
        // `SQLiteDataInvalidation.statusVersionKey` per .onChange reagiert) während des
        // kompletten Reset-Backfills bei "0 ausstehend" hängen, obwohl gerade tausende
        // Änderungen frisch eingereiht wurden — sie würde erst beim nächsten, unabhängigen
        // Trigger (z. B. dem nächsten regulären Sync-Fortschritt) aktualisiert.
        SQLiteDataInvalidation.bumpStatusVersion()
    }

    private static func loadStateSerialization() -> CKSyncEngine.State.Serialization? {
        guard let data = UserDefaults.standard.data(forKey: stateSerializationKey) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: Gespeicherter Sync-Status konnte nicht gelesen werden: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func persist(_ serialization: CKSyncEngine.State.Serialization) {
        do {
            let data = try JSONEncoder().encode(serialization)
            UserDefaults.standard.set(data, forKey: stateSerializationKey)
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: Sync-Status konnte nicht gespeichert werden: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension CloudSyncEngine: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let stateUpdate):
            Self.persist(stateUpdate.stateSerialization)

        case .accountChange(let change):
            switch change.changeType {
            case .signIn, .switchAccounts:
                status.state = .idle
            case .signOut:
                status.state = .accountUnavailable
            @unknown default:
                break
            }

        case .fetchedRecordZoneChanges(let changes):
            for modification in Self.sortedByDependencyOrder(changes.modifications.map(\.record)) {
                await applyIncomingRecord(modification)
            }
            for deletion in changes.deletions {
                await applyIncomingDeletion(deletion.recordID)
            }
            CloudSyncActivityStatus.recordSuccess()

        case .sentRecordZoneChanges(let changes):
            for saved in changes.savedRecords {
                dequeuePendingChange(recordName: saved.recordID.recordName)
            }
            for deletedID in changes.deletedRecordIDs {
                dequeuePendingChange(recordName: deletedID.recordName)
            }
            var needsResend = false
            for failedSave in changes.failedRecordSaves {
                if await handleFailedSave(failedSave) {
                    needsResend = true
                }
            }
            if needsResend {
                Self.notifyPendingChangesAvailable(database: database)
            }
            recordSyncActivityOutcome(failedRecordSaves: changes.failedRecordSaves)

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !changes.isEmpty else { return nil }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await self.record(forPendingChange: recordID)
        }
    }

    private func record(forPendingChange recordID: CKRecord.ID) async -> CKRecord? {
        guard
            let pendingChange = try? pendingChangeStore.pendingChange(recordName: recordID.recordName),
            let mapping = Self.mapping(forRecordType: pendingChange.recordType)
        else {
            return nil
        }
        do {
            let existing = knownServerRecordsByID[recordID]
            let record = try mapping.makeCKRecord(fromLocalID: recordID.recordName, existing: existing, database: database)
            knownServerRecordsByID.removeValue(forKey: recordID)
            return record
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: CKRecord fuer ausstehende Aenderung konnte nicht gebaut werden: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func applyIncomingRecord(_ record: CKRecord) async -> Bool {
        guard let mapping = Self.mapping(forRecordType: record.recordType) else { return false }
        do {
            try mapping.applyIncoming(record, database: database)
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: Eingehender \(record.recordType, privacy: .public)-Record konnte nicht gespeichert werden: \(error.localizedDescription, privacy: .public)")
            return false
        }
        SQLiteDataInvalidation.bumpStatusVersion()
        return true
    }

    private func applyIncomingDeletion(_ recordID: CKRecord.ID) async {
        for mapping in Self.registry.values {
            do {
                try mapping.applyIncomingDeletion(recordID: recordID, database: database)
            } catch {
                AppLogger.dataAccess.error("iCloud Sync: Eingehende Loeschung (\(mapping.recordType, privacy: .public)) fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }
        SQLiteDataInvalidation.bumpStatusVersion()
    }

    private func dequeuePendingChange(recordName: String) {
        do {
            try pendingChangeStore.dequeue(recordName: recordName)
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: Pending-Change konnte nicht entfernt werden: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Last-Write-Wins: bei einem Server-Konflikt (`.serverRecordChanged`) gewinnt die Seite mit
    /// dem neueren Zeitstempel (`CKRecord.modificationDate` vs. dem lokalen `updatedAt`).
    /// Liefert `true`, wenn dieses Element einen erneuten Sendeversuch braucht (der Aufrufer in
    /// `handleEvent` bündelt daraus höchstens EINEN `notifyPendingChangesAvailable`-Aufruf pro
    /// Batch, statt einem pro Konflikt — siehe Design-Spec
    /// `docs/superpowers/specs/2026-07-24-icloud-sync-konfliktaufloesung-fix-design.md`).
    private func handleFailedSave(_ failedSave: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave) async -> Bool {
        guard failedSave.error.code == .serverRecordChanged else {
            status.state = .error(failedSave.error.localizedDescription)
            AppLogger.dataAccess.error("iCloud Sync: Record-Save fehlgeschlagen: \(failedSave.error.localizedDescription, privacy: .public)")
            return false
        }

        guard let serverRecord = failedSave.error.serverRecord,
              let mapping = Self.mapping(forRecordType: failedSave.record.recordType)
        else { return false }

        let localUpdatedAt: Date?
        do {
            localUpdatedAt = try mapping.localUpdatedAt(forLocalID: failedSave.record.recordID.recordName, database: database)
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: Lokaler Stand fuer Konfliktaufloesung konnte nicht geladen werden: \(error.localizedDescription, privacy: .public)")
            return false
        }

        let serverIsNewer = (serverRecord.modificationDate ?? .distantPast) > (localUpdatedAt ?? .distantPast)

        if serverIsNewer {
            let applied = await applyIncomingRecord(serverRecord)
            if applied {
                dequeuePendingChange(recordName: failedSave.record.recordID.recordName)
            }
            return false
        } else {
            knownServerRecordsByID[failedSave.record.recordID] = serverRecord
            do {
                try pendingChangeStore.enqueue(recordType: mapping.recordType, recordName: failedSave.record.recordID.recordName, changeType: .save)
                return true
            } catch {
                AppLogger.dataAccess.error("iCloud Sync: Erneuter Sync-Versuch nach Konflikt konnte nicht eingeplant werden: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
    }

    /// Aktualisiert den persistenten Sync-Aktivitätsstatus nach einem abgeschlossenen
    /// Sende-Batch. `.serverRecordChanged`-Konflikte zählen NICHT als Fehler — die werden
    /// bereits automatisch aufgelöst (siehe `handleFailedSave` oben), das ist normaler
    /// Multi-Geräte-Betrieb. Siehe Design-Spec
    /// `docs/superpowers/specs/2026-07-24-icloud-sync-status-uebersicht-design.md`.
    private func recordSyncActivityOutcome(failedRecordSaves: [CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave]) {
        let realFailureMessages = failedRecordSaves
            .filter { $0.error.code != .serverRecordChanged }
            .map(\.error.localizedDescription)
        if let firstFailureMessage = realFailureMessages.first {
            CloudSyncActivityStatus.recordFailure(firstFailureMessage)
        } else {
            CloudSyncActivityStatus.recordSuccess()
        }
    }
}
