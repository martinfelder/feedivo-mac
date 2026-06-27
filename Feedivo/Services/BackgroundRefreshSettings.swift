import Foundation

enum BackgroundRefreshSettings {
    static let isEnabledKey = "backgroundRefresh.isEnabled"
    static let intervalMinutesKey = "backgroundRefresh.intervalMinutes"
    static let lastAutomaticRefreshDateKey = "backgroundRefresh.lastAutomaticRefreshDate"
    static let lastAutomaticRefreshStatusKey = "backgroundRefresh.lastAutomaticRefreshStatus"
    static let lastAutomaticRefreshErrorKey = "backgroundRefresh.lastAutomaticRefreshError"
    static let nextAutomaticRefreshDateKey = "backgroundRefresh.nextAutomaticRefreshDate"
    static let defaultIsEnabled = false
    static let defaultIntervalMinutes = 60
    static let allowedIntervalMinutes = [15, 30, 60, 120]
    static let statusSuccess = "success"
    static let statusFailed = "failed"
    static let statusPartial = "partial"

    static func clampedIntervalMinutes(_ intervalMinutes: Int) -> Int {
        allowedIntervalMinutes.min { first, second in
            abs(first - intervalMinutes) < abs(second - intervalMinutes)
        } ?? defaultIntervalMinutes
    }

    static func earliestBeginDate(
        isEnabled: Bool,
        intervalMinutes: Int,
        now: Date = Date()
    ) -> Date? {
        guard isEnabled else {
            return nil
        }

        return nextScheduledRefreshDate(intervalMinutes: intervalMinutes, now: now)
    }

    static func nextScheduledRefreshDate(intervalMinutes: Int, now: Date = Date()) -> Date {
        now.addingTimeInterval(TimeInterval(clampedIntervalMinutes(intervalMinutes) * 60))
    }

    static func statusText(for status: String?) -> String {
        switch status {
        case statusSuccess:
            "Erfolgreich"
        case statusFailed:
            "Fehlgeschlagen"
        default:
            "Noch nicht gelaufen"
        }
    }
}
