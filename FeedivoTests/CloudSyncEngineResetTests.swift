import Foundation
import GRDB
import Testing
@testable import Feedivo

/// Tests für `CloudSyncEngine.resetLocalState`/`resetCloudZoneAndLocalState` (iCloud Sync
/// Reset-Feature, siehe docs/superpowers/specs/2026-07-25-icloud-sync-reset-design.md).
/// `resetCloudZoneAndLocalState` selbst ist hier bewusst NICHT automatisiert getestet — der
/// echte `CKContainer`-Netzwerkaufruf ist analog zu `CloudSyncEngine.start()` nicht sinnvoll
/// unit-testbar, siehe Global Constraints im Implementierungsplan.
@MainActor
struct CloudSyncEngineResetTests {
    @Test func resetLocalStateLoeschtLokalenZustandUndLaesstEngineAusWennSyncDeaktiviertIst() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let defaults = try temporaryUserDefaults()
        defaults.set(true, forKey: CloudSyncEngine.hasCreatedZoneKey)
        defaults.set(Data([0x01, 0x02]), forKey: CloudSyncEngine.stateSerializationKey)
        defaults.set(false, forKey: CloudSyncSettings.isEnabledKey)

        try CloudSyncPendingChangeStore(database: database).enqueue(recordType: "Tag", recordName: "tag-1", changeType: .save)
        try database.write { db in
            var eintrag = OrphanedArticleStatusUpdateRecord(
                articleID: "artikel-1",
                isRead: true,
                isStarred: false,
                readAt: Date(),
                starredAt: nil,
                receivedAt: Date()
            )
            try eintrag.insert(db)
        }
        CloudSyncActivityStatus.recordFailure("Alter Fehler", userDefaults: defaults)

        let engine = CloudSyncEngine(database: database)
        engine.resetLocalState(database: database, userDefaults: defaults)

        #expect(defaults.object(forKey: CloudSyncEngine.hasCreatedZoneKey) == nil)
        #expect(defaults.data(forKey: CloudSyncEngine.stateSerializationKey) == nil)
        #expect(try CloudSyncPendingChangeStore(database: database).pendingChanges().isEmpty)
        let remainingOrphans = try database.read { db in try OrphanedArticleStatusUpdateRecord.fetchAll(db) }
        #expect(remainingOrphans.isEmpty)
        #expect(CloudSyncActivityStatus.lastRunSucceeded(userDefaults: defaults) == nil)
        #expect(CloudSyncActivityStatus.lastErrorMessage(userDefaults: defaults) == nil)
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.CloudSyncEngineReset.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
