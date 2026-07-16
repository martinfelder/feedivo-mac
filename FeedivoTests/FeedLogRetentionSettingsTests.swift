import Foundation
import Testing
@testable import Feedivo

struct FeedLogRetentionSettingsTests {
    @Test func retentionDaysLiefertDefaultBeiFehlendemKey() throws {
        let defaults = try temporaryUserDefaults()
        #expect(FeedLogRetentionSettings.retentionDays(in: defaults) == 30)
    }

    @Test func retentionDaysLiestGespeichertenWert() throws {
        let defaults = try temporaryUserDefaults()
        defaults.set(14, forKey: FeedLogRetentionSettings.retentionDaysKey)
        #expect(FeedLogRetentionSettings.retentionDays(in: defaults) == 14)
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.FeedLogRetention.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
