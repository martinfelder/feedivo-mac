import Foundation

/// Verhindert zu häufiges Refreshen desselben Feeds beim Refresh-All
/// (NetNewsWire-Vergleich, 2026-07-27) — analog NetNewsWires eigenem
/// `minimumTimeBetweenChecks` in `LocalAccountRefresher.swift`. Reine,
/// isoliert testbare Entscheidungsfunktion, analog
/// `BackgroundRefreshService.isPrematureTick`.
enum FeedRefreshThrottle {
    static func shouldSkip(
        lastAttemptAt: Date?,
        now: Date,
        minimumInterval: TimeInterval = 9 * 60
    ) -> Bool {
        guard let lastAttemptAt else {
            return false
        }
        return now.timeIntervalSince(lastAttemptAt) < minimumInterval
    }
}
