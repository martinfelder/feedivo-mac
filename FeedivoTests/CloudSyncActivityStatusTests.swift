import Foundation
import Testing
@testable import Feedivo

struct CloudSyncActivityStatusTests {
    @Test func nochNieGelaufenLiefertNilUeberall() throws {
        let defaults = try temporaryUserDefaults()

        #expect(CloudSyncActivityStatus.lastRunAt(userDefaults: defaults) == nil)
        #expect(CloudSyncActivityStatus.lastRunSucceeded(userDefaults: defaults) == nil)
        #expect(CloudSyncActivityStatus.lastErrorMessage(userDefaults: defaults) == nil)
    }

    @Test func recordSuccessSchreibtUndLiestZurueck() throws {
        let defaults = try temporaryUserDefaults()
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        CloudSyncActivityStatus.recordSuccess(at: date, userDefaults: defaults)

        #expect(CloudSyncActivityStatus.lastRunAt(userDefaults: defaults) == date)
        #expect(CloudSyncActivityStatus.lastRunSucceeded(userDefaults: defaults) == true)
        #expect(CloudSyncActivityStatus.lastErrorMessage(userDefaults: defaults) == nil)
    }

    @Test func recordFailureSchreibtUndLiestZurueck() throws {
        let defaults = try temporaryUserDefaults()
        let date = Date(timeIntervalSince1970: 1_700_000_100)

        CloudSyncActivityStatus.recordFailure("Netzwerkfehler", at: date, userDefaults: defaults)

        #expect(CloudSyncActivityStatus.lastRunAt(userDefaults: defaults) == date)
        #expect(CloudSyncActivityStatus.lastRunSucceeded(userDefaults: defaults) == false)
        #expect(CloudSyncActivityStatus.lastErrorMessage(userDefaults: defaults) == "Netzwerkfehler")
    }

    @Test func recordSuccessNachRecordFailureSetztFehlerZurueck() throws {
        let defaults = try temporaryUserDefaults()

        CloudSyncActivityStatus.recordFailure("Netzwerkfehler", userDefaults: defaults)
        CloudSyncActivityStatus.recordSuccess(userDefaults: defaults)

        #expect(CloudSyncActivityStatus.lastRunSucceeded(userDefaults: defaults) == true)
        #expect(CloudSyncActivityStatus.lastErrorMessage(userDefaults: defaults) == nil)
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.CloudSyncActivityStatus.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
