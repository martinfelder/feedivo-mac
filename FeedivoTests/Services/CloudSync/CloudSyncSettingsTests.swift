import Foundation
import Testing
@testable import Feedivo

struct CloudSyncSettingsTests {
    @Test func defaultsUndVerfuegbarkeit() {
        #expect(CloudSyncSettings.isEnabledKey == "cloudSync.isEnabled")
        #expect(CloudSyncSettings.defaultIsEnabled == false)
        #expect(CloudSyncSettings.cloudKitContainerIdentifier == "iCloud.ch.martin.Feedivo")
    }

    @Test func isEnabledLiestGespeichertenWert() throws {
        let defaults = try temporaryUserDefaults()

        #expect(CloudSyncSettings.isEnabled(in: defaults) == false)

        defaults.set(true, forKey: CloudSyncSettings.isEnabledKey)

        #expect(CloudSyncSettings.isEnabled(in: defaults) == true)
    }

    @Test func statusLocalizationKeyLiefertDatabaseErrorUnabhaengigVonAllemAnderen() {
        #expect(
            CloudSyncSettings.statusLocalizationKey(isEnabled: true, syncState: .idle, hasDatabaseError: true)
                == "settings.sync.status.databaseError"
        )
    }

    @Test func statusLocalizationKeyLiefertLocalWennDeaktiviert() {
        #expect(
            CloudSyncSettings.statusLocalizationKey(isEnabled: false, syncState: .idle, hasDatabaseError: false)
                == "settings.sync.status.local"
        )
    }

    @Test func statusLocalizationKeyLiefertActiveBeiIdleUndSyncing() {
        #expect(
            CloudSyncSettings.statusLocalizationKey(isEnabled: true, syncState: .idle, hasDatabaseError: false)
                == "settings.sync.status.active"
        )
        #expect(
            CloudSyncSettings.statusLocalizationKey(isEnabled: true, syncState: .syncing, hasDatabaseError: false)
                == "settings.sync.status.active"
        )
    }

    @Test func statusLocalizationKeyLiefertAccountUnavailable() {
        #expect(
            CloudSyncSettings.statusLocalizationKey(isEnabled: true, syncState: .accountUnavailable, hasDatabaseError: false)
                == "settings.sync.status.accountUnavailable"
        )
    }

    @Test func statusLocalizationKeyLiefertError() {
        #expect(
            CloudSyncSettings.statusLocalizationKey(isEnabled: true, syncState: .error("Netzwerkfehler"), hasDatabaseError: false)
                == "settings.sync.status.error"
        )
    }

    // Review-Fix (Task 14, Critical 2): pendingFirstActivationKey verhindert, dass
    // FeedivoApp.init() die Sync-Engine startet, solange eine Erst-Aktivierungs-Entscheidung
    // noch nicht getroffen wurde (z. B. App-Beenden während CloudSyncFirstActivationView noch
    // offen ist).
    @Test func hasPendingFirstActivationDefaultFalse() throws {
        let defaults = try temporaryUserDefaults()
        #expect(CloudSyncSettings.hasPendingFirstActivation(in: defaults) == false)
    }

    @Test func setPendingFirstActivationPersistiertUndLiestZurueck() throws {
        let defaults = try temporaryUserDefaults()

        CloudSyncSettings.setPendingFirstActivation(true, in: defaults)
        #expect(CloudSyncSettings.hasPendingFirstActivation(in: defaults) == true)

        CloudSyncSettings.setPendingFirstActivation(false, in: defaults)
        #expect(CloudSyncSettings.hasPendingFirstActivation(in: defaults) == false)
    }

    @Test func shouldAutoStartSyncEngineAtLaunchStartetNurWennEnabledUndKeineOffenePendingEntscheidung() {
        #expect(CloudSyncSettings.shouldAutoStartSyncEngineAtLaunch(isEnabled: true, hasPendingFirstActivation: false) == true)
        #expect(CloudSyncSettings.shouldAutoStartSyncEngineAtLaunch(isEnabled: true, hasPendingFirstActivation: true) == false)
        #expect(CloudSyncSettings.shouldAutoStartSyncEngineAtLaunch(isEnabled: false, hasPendingFirstActivation: false) == false)
        #expect(CloudSyncSettings.shouldAutoStartSyncEngineAtLaunch(isEnabled: false, hasPendingFirstActivation: true) == false)
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.CloudSyncSettings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
