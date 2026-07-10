import Foundation
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
    private let feedivoDatabase: FeedivoDatabase
    private let feedViewModel: FeedViewModel
    private var scheduler: NSBackgroundActivityScheduler?

    init(feedivoDatabase: FeedivoDatabase, feedViewModel: FeedViewModel) {
        self.feedivoDatabase = feedivoDatabase
        self.feedViewModel = feedViewModel
    }

    func submit(_ request: BackgroundRefreshRequest) throws {
        scheduler?.invalidate()

        let scheduler = NSBackgroundActivityScheduler(identifier: request.identifier)
        scheduler.repeats = true
        scheduler.interval = TimeInterval(request.intervalMinutes * 60)
        scheduler.tolerance = TimeInterval(max(60, request.intervalMinutes * 60 / 4))
        scheduler.schedule { [feedivoDatabase, feedViewModel] completionHandler in
            Task { @MainActor in
                await BackgroundRefreshService.refreshAllFeeds(
                    database: feedivoDatabase,
                    intervalMinutes: request.intervalMinutes,
                    feedViewModel: feedViewModel
                )
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
        scheduler: BackgroundRefreshScheduling,
        userDefaults: UserDefaults = .standard
    ) throws {
        let clampedIntervalMinutes = BackgroundRefreshSettings.clampedIntervalMinutes(intervalMinutes)
        guard let earliestBeginDate = BackgroundRefreshSettings.earliestBeginDate(
            isEnabled: isEnabled,
            intervalMinutes: clampedIntervalMinutes,
            now: now
        ) else {
            scheduler.cancel(identifier: taskIdentifier)
            userDefaults.removeObject(forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey)
            return
        }

        do {
            try scheduler.submit(
                BackgroundRefreshRequest(
                    identifier: taskIdentifier,
                    intervalMinutes: clampedIntervalMinutes,
                    earliestBeginDate: earliestBeginDate
                )
            )
            userDefaults.set(
                earliestBeginDate.timeIntervalSince1970,
                forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey
            )
        } catch {
            userDefaults.removeObject(forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey)
            userDefaults.set(now.timeIntervalSince1970, forKey: BackgroundRefreshSettings.lastAutomaticRefreshDateKey)
            userDefaults.set(BackgroundRefreshSettings.statusFailed, forKey: BackgroundRefreshSettings.lastAutomaticRefreshStatusKey)
            userDefaults.set(error.localizedDescription, forKey: BackgroundRefreshSettings.lastAutomaticRefreshErrorKey)
            throw error
        }
    }

    @MainActor
    static func refreshAllFeeds(
        database: FeedivoDatabase,
        intervalMinutes: Int = 60,
        userDefaults: UserDefaults = .standard,
        feedViewModel: FeedViewModel
    ) async {
        await feedViewModel.refreshAllFeeds(sqliteDatabase: database)

        recordRefreshOutcome(
            from: feedViewModel,
            intervalMinutes: intervalMinutes,
            userDefaults: userDefaults
        )
    }

    static func recordRefreshOutcome(
        from viewModel: FeedViewModel,
        intervalMinutes: Int,
        userDefaults: UserDefaults = .standard
    ) {
        // Unterscheidung zwischen Erfolg / Teilfehler / totaler Misserfolg statt
        // zuvor pauschal „errorMessage != nil → failed". Ein Teilfehler (ein paar
        // Feeds nicht erreichbar, der Rest aktualisiert) ist kein Gesamtversagen.
        switch viewModel.lastRefreshOutcome {
        case .failure:
            recordRefreshFailure(
                viewModel.errorMessage ?? "",
                intervalMinutes: intervalMinutes,
                userDefaults: userDefaults
            )
        case .partial(let failedCount):
            recordRefreshPartial(
                viewModel.errorMessage ?? "",
                failedCount: failedCount,
                intervalMinutes: intervalMinutes,
                userDefaults: userDefaults
            )
        case .success, nil:
            recordRefreshSuccess(
                intervalMinutes: intervalMinutes,
                userDefaults: userDefaults
            )
        }
    }

    static func recordRefreshSuccess(
        now: Date = Date(),
        intervalMinutes: Int,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(now.timeIntervalSince1970, forKey: BackgroundRefreshSettings.lastAutomaticRefreshDateKey)
        userDefaults.set(BackgroundRefreshSettings.statusSuccess, forKey: BackgroundRefreshSettings.lastAutomaticRefreshStatusKey)
        userDefaults.removeObject(forKey: BackgroundRefreshSettings.lastAutomaticRefreshErrorKey)
        userDefaults.set(
            BackgroundRefreshSettings.nextScheduledRefreshDate(intervalMinutes: intervalMinutes, now: now).timeIntervalSince1970,
            forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey
        )
    }

    static func recordRefreshFailure(
        _ message: String,
        now: Date = Date(),
        intervalMinutes: Int,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(now.timeIntervalSince1970, forKey: BackgroundRefreshSettings.lastAutomaticRefreshDateKey)
        userDefaults.set(BackgroundRefreshSettings.statusFailed, forKey: BackgroundRefreshSettings.lastAutomaticRefreshStatusKey)
        userDefaults.set(message, forKey: BackgroundRefreshSettings.lastAutomaticRefreshErrorKey)
        userDefaults.set(
            BackgroundRefreshSettings.nextScheduledRefreshDate(intervalMinutes: intervalMinutes, now: now).timeIntervalSince1970,
            forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey
        )
    }

    /// Teilfehler: der Refresh ist gelaufen, einige Feeds konnten aber nicht
    /// aktualisiert werden. Status „partial" statt „failed" — die meisten Feeds
    /// wurden erfolgreich aktualisiert, nur eine Teilmenge ist fehlgeschlagen.
    static func recordRefreshPartial(
        _ message: String,
        failedCount: Int,
        now: Date = Date(),
        intervalMinutes: Int,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(now.timeIntervalSince1970, forKey: BackgroundRefreshSettings.lastAutomaticRefreshDateKey)
        userDefaults.set(BackgroundRefreshSettings.statusPartial, forKey: BackgroundRefreshSettings.lastAutomaticRefreshStatusKey)
        userDefaults.set(message, forKey: BackgroundRefreshSettings.lastAutomaticRefreshErrorKey)
        userDefaults.set(
            BackgroundRefreshSettings.nextScheduledRefreshDate(intervalMinutes: intervalMinutes, now: now).timeIntervalSince1970,
            forKey: BackgroundRefreshSettings.nextAutomaticRefreshDateKey
        )
    }
}
