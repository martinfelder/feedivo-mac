import Foundation
import Testing
@testable import Feedivo

struct CloudSyncSettingsTests {
    @Test func defaultsUndVerfuegbarkeit() {
        #expect(CloudSyncSettings.isEnabledKey == "cloudSync.isEnabled")
        #expect(CloudSyncSettings.defaultIsEnabled == false)
        #expect(CloudSyncSettings.isAvailable == true)
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
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.CloudSyncSettings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
