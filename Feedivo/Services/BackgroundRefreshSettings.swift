import Foundation

enum BackgroundRefreshSettings {
    static let isEnabledKey = "backgroundRefresh.isEnabled"
    static let intervalMinutesKey = "backgroundRefresh.intervalMinutes"
    static let defaultIsEnabled = false
    static let defaultIntervalMinutes = 60
    static let allowedIntervalMinutes = [15, 30, 60, 120]

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

        return now.addingTimeInterval(TimeInterval(clampedIntervalMinutes(intervalMinutes) * 60))
    }
}
