import Foundation
import SwiftData

struct BackgroundRefreshRequest {
    let identifier: String
    let intervalMinutes: Int
    let earliestBeginDate: Date?
}

protocol BackgroundRefreshScheduling {
    func submit(_ request: BackgroundRefreshRequest) throws
    func cancel(identifier: String)
}

extension BackgroundRefreshScheduling {
    func cancel(identifier: String) {}
}

@MainActor
final class SystemBackgroundActivityRefreshScheduler: BackgroundRefreshScheduling {
    private let modelContainer: ModelContainer
    private var scheduler: NSBackgroundActivityScheduler?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func submit(_ request: BackgroundRefreshRequest) throws {
        scheduler?.invalidate()

        let scheduler = NSBackgroundActivityScheduler(identifier: request.identifier)
        scheduler.repeats = true
        scheduler.interval = TimeInterval(request.intervalMinutes * 60)
        scheduler.tolerance = TimeInterval(max(60, request.intervalMinutes * 60 / 4))
        scheduler.schedule { [modelContainer] completionHandler in
            Task { @MainActor in
                await BackgroundRefreshService.refreshAllFeeds(modelContainer: modelContainer)
                completionHandler(.finished)
            }
        }

        self.scheduler = scheduler
    }

    func cancel(identifier: String) {
        guard scheduler != nil else {
            return
        }

        scheduler?.invalidate()
        scheduler = nil
    }
}

enum BackgroundRefreshService {
    static let taskIdentifier = "ch.martin.Feedivo.refresh"

    static func scheduleNextRefresh(
        isEnabled: Bool,
        intervalMinutes: Int,
        now: Date = Date(),
        scheduler: BackgroundRefreshScheduling
    ) throws {
        let clampedIntervalMinutes = BackgroundRefreshSettings.clampedIntervalMinutes(intervalMinutes)
        guard let earliestBeginDate = BackgroundRefreshSettings.earliestBeginDate(
            isEnabled: isEnabled,
            intervalMinutes: clampedIntervalMinutes,
            now: now
        ) else {
            scheduler.cancel(identifier: taskIdentifier)
            return
        }

        try scheduler.submit(
            BackgroundRefreshRequest(
                identifier: taskIdentifier,
                intervalMinutes: clampedIntervalMinutes,
                earliestBeginDate: earliestBeginDate
            )
        )
    }

    @MainActor
    static func scheduleFromStoredSettings(
        userDefaults: UserDefaults = .standard,
        scheduler: BackgroundRefreshScheduling
    ) {
        let isEnabled = userDefaults.bool(forKey: BackgroundRefreshSettings.isEnabledKey)
        let storedInterval = userDefaults.integer(forKey: BackgroundRefreshSettings.intervalMinutesKey)
        let intervalMinutes = storedInterval == 0
            ? BackgroundRefreshSettings.defaultIntervalMinutes
            : storedInterval

        try? scheduleNextRefresh(
            isEnabled: isEnabled,
            intervalMinutes: intervalMinutes,
            scheduler: scheduler
        )
    }

    @MainActor
    static func refreshAllFeeds(modelContainer: ModelContainer) async {
        let context = ModelContext(modelContainer)
        let feeds = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        let viewModel = FeedViewModel()

        await viewModel.refreshAllFeeds(feeds, context: context)
    }
}
