import Foundation
import Testing
@testable import Feedivo

struct BackgroundRefreshServiceTests {

    @Test func scheduleNextRefreshPlantNichtsWennDeaktiviert() throws {
        let scheduler = RecordingBackgroundTaskScheduler()

        try BackgroundRefreshService.scheduleNextRefresh(
            isEnabled: false,
            intervalMinutes: 30,
            now: Date(timeIntervalSince1970: 1_000),
            scheduler: scheduler
        )

        #expect(scheduler.submittedRequests.isEmpty)
        #expect(scheduler.cancelledIdentifiers == [BackgroundRefreshService.taskIdentifier])
    }

    @Test func scheduleNextRefreshPlantTaskMitGeklemmtemStartdatum() throws {
        let scheduler = RecordingBackgroundTaskScheduler()
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 1_000)

        try BackgroundRefreshService.scheduleNextRefresh(
            isEnabled: true,
            intervalMinutes: 44,
            now: now,
            scheduler: scheduler,
            userDefaults: defaults
        )

        let request = try #require(scheduler.submittedRequests.first)
        #expect(request.identifier == BackgroundRefreshService.taskIdentifier)
        #expect(request.intervalMinutes == 30)
        #expect(request.earliestBeginDate == now.addingTimeInterval(30 * 60))
        #expect(defaults.double(forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey) == now.addingTimeInterval(30 * 60).timeIntervalSince1970)
    }

    @Test func scheduleNextRefreshEntferntNaechstenZeitpunktWennDeaktiviert() throws {
        let scheduler = RecordingBackgroundTaskScheduler()
        let defaults = try temporaryUserDefaults()
        defaults.set(2_000.0, forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey)

        try BackgroundRefreshService.scheduleNextRefresh(
            isEnabled: false,
            intervalMinutes: 30,
            now: Date(timeIntervalSince1970: 1_000),
            scheduler: scheduler,
            userDefaults: defaults
        )

        #expect(defaults.object(forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey) == nil)
    }

    @Test func scheduleNextRefreshSpeichertPlanungsfehlerOhneNaechstenZeitpunkt() throws {
        let scheduler = RecordingBackgroundTaskScheduler(errorToThrow: TestBackgroundRefreshError())
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 1_000)

        do {
            try BackgroundRefreshService.scheduleNextRefresh(
                isEnabled: true,
                intervalMinutes: 30,
                now: now,
                scheduler: scheduler,
                userDefaults: defaults
            )
            Issue.record("Planung sollte fehlschlagen")
        } catch {
            #expect(defaults.object(forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey) == nil)
            #expect(defaults.double(forKey: BackgroundRefreshSettings.lastAutomaticRefreshDateKey) == now.timeIntervalSince1970)
            #expect(defaults.string(forKey: BackgroundRefreshSettings.lastAutomaticRefreshStatusKey) == BackgroundRefreshSettings.statusFailed)
            #expect(defaults.string(forKey: BackgroundRefreshSettings.lastAutomaticRefreshErrorKey) == "Planung fehlgeschlagen")
        }
    }

    @Test func recordRefreshSuccessSpeichertStatusUndNaechstenZeitpunkt() throws {
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 1_000)

        BackgroundRefreshService.recordRefreshSuccess(
            now: now,
            intervalMinutes: 44,
            userDefaults: defaults
        )

        #expect(defaults.double(forKey: BackgroundRefreshSettings.lastAutomaticRefreshDateKey) == now.timeIntervalSince1970)
        #expect(defaults.string(forKey: BackgroundRefreshSettings.lastAutomaticRefreshStatusKey) == BackgroundRefreshSettings.statusSuccess)
        #expect(defaults.string(forKey: BackgroundRefreshSettings.lastAutomaticRefreshErrorKey) == nil)
        #expect(defaults.double(forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey) == now.addingTimeInterval(30 * 60).timeIntervalSince1970)
    }

    @Test func recordRefreshFailureSpeichertStatusUndFehlermeldung() throws {
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 1_000)

        BackgroundRefreshService.recordRefreshFailure(
            "Netzwerkfehler",
            now: now,
            intervalMinutes: 30,
            userDefaults: defaults
        )

        #expect(defaults.double(forKey: BackgroundRefreshSettings.lastAutomaticRefreshDateKey) == now.timeIntervalSince1970)
        #expect(defaults.string(forKey: BackgroundRefreshSettings.lastAutomaticRefreshStatusKey) == BackgroundRefreshSettings.statusFailed)
        #expect(defaults.string(forKey: BackgroundRefreshSettings.lastAutomaticRefreshErrorKey) == "Netzwerkfehler")
        #expect(defaults.double(forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey) == now.addingTimeInterval(30 * 60).timeIntervalSince1970)
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.BackgroundRefresh.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private final class RecordingBackgroundTaskScheduler: BackgroundRefreshScheduling {
    let errorToThrow: Error?
    private(set) var submittedRequests: [BackgroundRefreshRequest] = []
    private(set) var cancelledIdentifiers: [String] = []

    init(errorToThrow: Error? = nil) {
        self.errorToThrow = errorToThrow
    }

    func submit(_ request: BackgroundRefreshRequest) throws {
        if let errorToThrow {
            throw errorToThrow
        }

        submittedRequests.append(request)
    }

    func cancel(identifier: String) {
        cancelledIdentifiers.append(identifier)
    }
}

private struct TestBackgroundRefreshError: LocalizedError {
    var errorDescription: String? {
        "Planung fehlgeschlagen"
    }
}
