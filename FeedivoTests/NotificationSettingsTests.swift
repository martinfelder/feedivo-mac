import Foundation
import Testing
@testable import Feedivo

struct NotificationSettingsTests {
    @Test func defaultsSindWieDokumentiert() {
        #expect(NotificationSettings.isMasterEnabledKey == "notifications.master.isEnabled")
        #expect(NotificationSettings.defaultIsMasterEnabled == true)
        #expect(NotificationSettings.defaultEnabledForNewFeedsKey == "notifications.newFeeds.defaultEnabled")
        #expect(NotificationSettings.defaultEnabledForNewFeedsDefault == false)
    }

    @Test func isMasterEnabledLiefertDefaultBeiFehlendemKey() throws {
        let defaults = try temporaryUserDefaults()

        #expect(NotificationSettings.isMasterEnabled(in: defaults) == true)
    }

    @Test func isMasterEnabledLiestGespeichertenWert() throws {
        let defaults = try temporaryUserDefaults()
        defaults.set(false, forKey: NotificationSettings.isMasterEnabledKey)

        #expect(NotificationSettings.isMasterEnabled(in: defaults) == false)

        defaults.set(true, forKey: NotificationSettings.isMasterEnabledKey)

        #expect(NotificationSettings.isMasterEnabled(in: defaults) == true)
    }

    @Test func isEnabledForNewFeedsLiefertDefaultBeiFehlendemKey() throws {
        let defaults = try temporaryUserDefaults()

        #expect(NotificationSettings.isEnabledForNewFeeds(in: defaults) == false)
    }

    @Test func isEnabledForNewFeedsLiestGespeichertenWert() throws {
        let defaults = try temporaryUserDefaults()
        defaults.set(true, forKey: NotificationSettings.defaultEnabledForNewFeedsKey)

        #expect(NotificationSettings.isEnabledForNewFeeds(in: defaults) == true)
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.NotificationSettings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
