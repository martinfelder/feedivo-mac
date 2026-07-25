import Foundation

/// Persistenter (UserDefaults-backed) Status des letzten tatsächlichen iCloud-Sync-Versuchs —
/// im Gegensatz zu `CloudSyncStatus` (rein In-Memory, geht bei jedem App-Neustart verloren)
/// überlebt dieser Stand einen Neustart. Nach dem Muster von `ArticleRetentionSettings`s
/// `lastAutomaticCleanup*`-Keys aufgebaut (siehe `ArticleRetentionCleanupService.
/// recordAutomaticCleanupSuccess/-Failure`). Siehe Design-Spec
/// `docs/superpowers/specs/2026-07-24-icloud-sync-status-uebersicht-design.md`.
enum CloudSyncActivityStatus {
    static let lastRunDateKey = "cloudSync.activity.lastRunDate"
    static let statusKey = "cloudSync.activity.status"
    static let lastErrorMessageKey = "cloudSync.activity.lastErrorMessage"

    static let statusSuccess = "success"
    static let statusFailed = "failed"

    static func lastRunAt(userDefaults: UserDefaults = .standard) -> Date? {
        let timestamp = userDefaults.double(forKey: lastRunDateKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    static func lastRunSucceeded(userDefaults: UserDefaults = .standard) -> Bool? {
        switch userDefaults.string(forKey: statusKey) {
        case statusSuccess: true
        case statusFailed: false
        default: nil
        }
    }

    static func lastErrorMessage(userDefaults: UserDefaults = .standard) -> String? {
        userDefaults.string(forKey: lastErrorMessageKey)
    }

    static func recordSuccess(at date: Date = Date(), userDefaults: UserDefaults = .standard) {
        userDefaults.set(date.timeIntervalSince1970, forKey: lastRunDateKey)
        userDefaults.set(statusSuccess, forKey: statusKey)
        userDefaults.removeObject(forKey: lastErrorMessageKey)
    }

    static func recordFailure(_ message: String, at date: Date = Date(), userDefaults: UserDefaults = .standard) {
        userDefaults.set(date.timeIntervalSince1970, forKey: lastRunDateKey)
        userDefaults.set(statusFailed, forKey: statusKey)
        userDefaults.set(message, forKey: lastErrorMessageKey)
    }

    /// Setzt den persistierten Sync-Aktivitätsstatus vollständig zurück — genutzt vom
    /// iCloud-Sync-Reset (`CloudSyncEngine.resetLocalState`), damit die Statusanzeige in den
    /// Einstellungen danach wieder "Noch nie synchronisiert" statt eines veralteten Standes
    /// zeigt.
    static func reset(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: lastRunDateKey)
        userDefaults.removeObject(forKey: statusKey)
        userDefaults.removeObject(forKey: lastErrorMessageKey)
    }
}
