import Foundation

// Aufbewahrungsdauer für feed_logs-Einträge (reine technische Diagnose-
// Historie pro Feed). Läuft unabhängig von ArticleRetentionSettings — siehe
// ArticleRetentionCleanupService.runAutomaticCleanup, das diese Einstellung
// bei jedem automatischen Bereinigungslauf konsultiert, unabhängig davon, ob
// die Artikel-Aufbewahrung selbst aktiviert ist.
enum FeedLogRetentionSettings {
    static let retentionDaysKey = "feedLogRetention.retentionDays"
    static let defaultRetentionDays = 30
    static let allowedRetentionDays = [7, 14, 30, 60, 90]

    static func retentionDays(in defaults: UserDefaults = .standard) -> Int {
        guard defaults.object(forKey: retentionDaysKey) != nil else {
            return defaultRetentionDays
        }
        return defaults.integer(forKey: retentionDaysKey)
    }
}
