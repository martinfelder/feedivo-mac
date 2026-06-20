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
        let now = Date(timeIntervalSince1970: 1_000)

        try BackgroundRefreshService.scheduleNextRefresh(
            isEnabled: true,
            intervalMinutes: 44,
            now: now,
            scheduler: scheduler
        )

        let request = try #require(scheduler.submittedRequests.first)
        #expect(request.identifier == BackgroundRefreshService.taskIdentifier)
        #expect(request.intervalMinutes == 30)
        #expect(request.earliestBeginDate == now.addingTimeInterval(30 * 60))
    }
}

private final class RecordingBackgroundTaskScheduler: BackgroundRefreshScheduling {
    private(set) var submittedRequests: [BackgroundRefreshRequest] = []
    private(set) var cancelledIdentifiers: [String] = []

    func submit(_ request: BackgroundRefreshRequest) throws {
        submittedRequests.append(request)
    }

    func cancel(identifier: String) {
        cancelledIdentifiers.append(identifier)
    }
}
