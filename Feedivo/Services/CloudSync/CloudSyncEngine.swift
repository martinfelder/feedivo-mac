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
                let pending = try pendingChangeStore.pendingChanges()
                if !pending.isEmpty {
                    let changes: [CKSyncEngine.PendingRecordZoneChange] = pending.map { change in
                        let recordID = CloudSyncTagMapping.recordID(forTagID: change.id)
                        switch change.changeType {
                        case .save:
                            return .saveRecord(recordID)
                        case .delete:
                            return .deleteRecord(recordID)
                        }
                    }
                    engine.state.add(pendingRecordZoneChanges: changes)
                }
            } catch {
                AppLogger.dataAccess.error("iCloud Sync: Ausstehende Aenderungen konnten nicht geladen werden: \(error.localizedDescription, privacy: .public)")
            }

            status.state = .idle
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        syncEngine = nil
        status.state = .idle
    }

    private static func loadStateSerialization() -> CKSyncEngine.State.Serialization? {
        guard let data = UserDefaults.standard.data(forKey: stateSerializationKey) else {
            return nil
        }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private static func persist(_ serialization: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(serialization) else { return }
        UserDefaults.standard.set(data, forKey: stateSerializationKey)
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
        guard let tag = (try? TagStore(database: database).tags())?.first(where: { $0.id == recordID.recordName }) else {
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

        let localTag = (try? TagStore(database: database).tags())?.first { $0.id == failedSave.record.recordID.recordName }
        let serverIsNewer = (serverRecord.modificationDate ?? .distantPast) > (localTag?.updatedAt ?? .distantPast)

        if serverIsNewer {
            await applyIncomingRecord(serverRecord)
        } else {
            do {
                try pendingChangeStore.enqueue(recordType: "tag", recordName: failedSave.record.recordID.recordName, changeType: .save)
            } catch {
                AppLogger.dataAccess.error("iCloud Sync: Erneuter Sync-Versuch nach Konflikt konnte nicht eingeplant werden: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
