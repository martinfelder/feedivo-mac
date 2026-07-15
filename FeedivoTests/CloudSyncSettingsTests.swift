import Foundation
import Testing
@testable import Feedivo

struct CloudSyncSettingsTests {
    @Test func defaultsSindBewusstAus() {
        #expect(CloudSyncSettings.isEnabledKey == "cloudSync.isEnabled")
        #expect(CloudSyncSettings.defaultIsEnabled == false)
        #expect(CloudSyncSettings.isAvailable == false)
        #expect(CloudSyncSettings.cloudKitContainerIdentifier == "iCloud.ch.martin.Feedivo")
    }

    @Test func isEnabledLiestGespeichertenWert() throws {
        let defaults = try temporaryUserDefaults()

        #expect(CloudSyncSettings.isEnabled(in: defaults) == false)

        defaults.set(true, forKey: CloudSyncSettings.isEnabledKey)

        #expect(CloudSyncSettings.isEnabled(in: defaults) == false)
    }

    @Test func statusTextBeschreibtLaunchZustand() {
        #expect(
            CloudSyncSettings.statusText(
                isEnabledAtLaunch: false,
                currentIsEnabled: false,
                hasDatabaseError: false
            ) == "iCloud Sync noch nicht verfügbar"
        )
        #expect(
            CloudSyncSettings.statusText(
                isEnabledAtLaunch: false,
                currentIsEnabled: true,
                hasDatabaseError: false
            ) == "iCloud Sync noch nicht verfügbar"
        )
        #expect(
            CloudSyncSettings.statusText(
                isEnabledAtLaunch: true,
                currentIsEnabled: true,
                hasDatabaseError: false
            ) == "iCloud Sync noch nicht verfügbar"
        )
        #expect(
            CloudSyncSettings.statusText(
                isEnabledAtLaunch: true,
                currentIsEnabled: true,
                hasDatabaseError: true
            ) == "Datenbank konnte nicht geladen werden"
        )
        #expect(
            CloudSyncSettings.statusText(
                isEnabledAtLaunch: true,
                currentIsEnabled: false,
                hasDatabaseError: false
            ) == "iCloud Sync noch nicht verfügbar"
        )
    }

    @Test func statusLocalizationKeyLiefertDatabaseErrorKey() {
        #expect(
            CloudSyncSettings.statusLocalizationKey(
                isEnabledAtLaunch: true,
                currentIsEnabled: true,
                hasDatabaseError: true
            ) == "settings.sync.status.databaseError"
        )
    }

    @Test func statusLocalizationKeyLiefertUnavailableKey() {
        #expect(
            CloudSyncSettings.statusLocalizationKey(
                isEnabledAtLaunch: true,
                currentIsEnabled: true,
                hasDatabaseError: false
            ) == "settings.sync.status.unavailable"
        )
    }

    @Test func statusLocalizationKeyLiefertLocalKey() {
        #expect(
            CloudSyncSettings.statusLocalizationKey(
                isEnabledAtLaunch: false,
                currentIsEnabled: false,
                hasDatabaseError: false
            ) == "settings.sync.status.unavailable"
        )
    }

    @Test func statusLocalizationKeyLiefertRestartEnableKey() {
        #expect(
            CloudSyncSettings.statusLocalizationKey(
                isEnabledAtLaunch: false,
                currentIsEnabled: true,
                hasDatabaseError: false
            ) == "settings.sync.status.unavailable"
        )
    }

    @Test func statusLocalizationKeyLiefertRestartDisableKey() {
        #expect(
            CloudSyncSettings.statusLocalizationKey(
                isEnabledAtLaunch: true,
                currentIsEnabled: false,
                hasDatabaseError: false
            ) == "settings.sync.status.unavailable"
        )
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.CloudSyncSettings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
