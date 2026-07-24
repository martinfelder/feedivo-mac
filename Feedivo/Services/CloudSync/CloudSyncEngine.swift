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
    private static let stateSerializationKey = "cloudSync.stateSerialization"
    private static let hasCreatedZoneKey = "cloudSync.hasCreatedZone"

    private let database: FeedivoDatabase
    private let pendingChangeStore: CloudSyncPendingChangeStore
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

            Self.notifyPendingChangesAvailable(database: database)

            status.state = .idle
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        syncEngine = nil
        status.state = .idle
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
        let changes: [CKSyncEngine.PendingRecordZoneChange] = pending.map { change in
            let recordID = CloudSyncTagMapping.recordID(forTagID: change.id)
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
        Task {
            do {
                try await syncEngine.sendChanges()
            } catch {
                AppLogger.dataAccess.error("iCloud Sync: Sofortiges Senden fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }
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
            for modification in changes.modifications {
                await applyIncomingRecord(modification.record)
            }
            for deletion in changes.deletions {
                await applyIncomingDeletion(deletion.recordID)
            }

        case .sentRecordZoneChanges(let changes):
            for saved in changes.savedRecords {
                dequeuePendingChange(recordName: saved.recordID.recordName)
            }
            for deletedID in changes.deletedRecordIDs {
                dequeuePendingChange(recordName: deletedID.recordName)
            }
            for failedSave in changes.failedRecordSaves {
                await handleFailedSave(failedSave)
            }

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
        let tags: [TagRecord]
        do {
            tags = try TagStore(database: database).tags()
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: Tags fuer ausstehende Aenderung konnten nicht geladen werden: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard let tag = tags.first(where: { $0.id == recordID.recordName }) else {
            return nil
        }
        return CloudSyncTagMapping.makeCKRecord(from: tag)
    }

    private func applyIncomingRecord(_ record: CKRecord) async {
        guard var incoming = CloudSyncTagMapping.tagRecord(from: record) else { return }
        do {
            try database.write { db in
                try incoming.save(db)
            }
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: Eingehender Tag konnte nicht gespeichert werden: \(error.localizedDescription, privacy: .public)")
            return
        }
        SQLiteDataInvalidation.bumpStatusVersion()
    }

    private func applyIncomingDeletion(_ recordID: CKRecord.ID) async {
        do {
            try database.write { db in
                try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [recordID.recordName])
            }
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: Eingehende Tag-Loeschung fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return
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
    /// dem neueren Zeitstempel (`CKRecord.modificationDate` vs. `TagRecord.updatedAt`).
    private func handleFailedSave(_ failedSave: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave) async {
        guard failedSave.error.code == .serverRecordChanged else {
            status.state = .error(failedSave.error.localizedDescription)
            AppLogger.dataAccess.error("iCloud Sync: Record-Save fehlgeschlagen: \(failedSave.error.localizedDescription, privacy: .public)")
            return
        }

        guard let serverRecord = failedSave.error.serverRecord else { return }

        let tags: [TagRecord]
        do {
            tags = try TagStore(database: database).tags()
        } catch {
            AppLogger.dataAccess.error("iCloud Sync: Lokaler Tag-Bestand fuer Konfliktaufloesung konnte nicht geladen werden: \(error.localizedDescription, privacy: .public)")
            return
        }

        let localTag = tags.first { $0.id == failedSave.record.recordID.recordName }
        let serverIsNewer = (serverRecord.modificationDate ?? .distantPast) > (localTag?.updatedAt ?? .distantPast)

        if serverIsNewer {
            await applyIncomingRecord(serverRecord)
        } else {
            do {
                try pendingChangeStore.enqueue(recordType: "tag", recordName: failedSave.record.recordID.recordName, changeType: .save)
                Self.notifyPendingChangesAvailable(database: database)
            } catch {
                AppLogger.dataAccess.error("iCloud Sync: Erneuter Sync-Versuch nach Konflikt konnte nicht eingeplant werden: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
