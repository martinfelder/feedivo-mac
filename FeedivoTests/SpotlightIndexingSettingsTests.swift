import Foundation
import Testing
@testable import Feedivo

struct SpotlightIndexingSettingsTests {
    @Test func defaultsSindWieDokumentiert() {
        #expect(SpotlightIndexingSettings.isEnabledKey == "spotlight.isEnabled")
        #expect(SpotlightIndexingSettings.defaultIsEnabled == true)
        #expect(SpotlightIndexingSettings.hasBackfilledKey == "spotlight.hasBackfilled")
        #expect(SpotlightIndexingSettings.defaultHasBackfilled == false)
    }

    @Test func isEnabledLiefertDefaultBeiFehlendemKey() throws {
        let defaults = try temporaryUserDefaults()

        #expect(SpotlightIndexingSettings.isEnabled(in: defaults) == true)
    }

    @Test func isEnabledLiestGespeichertenWert() throws {
        let defaults = try temporaryUserDefaults()
        defaults.set(false, forKey: SpotlightIndexingSettings.isEnabledKey)

        #expect(SpotlightIndexingSettings.isEnabled(in: defaults) == false)

        defaults.set(true, forKey: SpotlightIndexingSettings.isEnabledKey)

        #expect(SpotlightIndexingSettings.isEnabled(in: defaults) == true)
    }

    @Test func hasBackfilledLiefertDefaultBeiFehlendemKey() throws {
        let defaults = try temporaryUserDefaults()

        #expect(SpotlightIndexingSettings.hasBackfilled(in: defaults) == false)
    }

    @Test func setHasBackfilledSchreibtUndLiestWertZurueck() throws {
        let defaults = try temporaryUserDefaults()

        SpotlightIndexingSettings.setHasBackfilled(true, in: defaults)
        #expect(SpotlightIndexingSettings.hasBackfilled(in: defaults) == true)

        SpotlightIndexingSettings.setHasBackfilled(false, in: defaults)
        #expect(SpotlightIndexingSettings.hasBackfilled(in: defaults) == false)
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.SpotlightIndexingSettings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
