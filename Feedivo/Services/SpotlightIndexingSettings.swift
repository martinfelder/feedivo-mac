import Foundation

/// Persistente Einstellungen für die Spotlight-Indexierung (Feature 9.3).
/// Gleiches Muster wie `NotificationSettings.swift`: sicherer
/// `object(forKey:) != nil`-Guard, damit ein fehlender Key den dokumentierten
/// Default liefert statt stillschweigend `false`.
enum SpotlightIndexingSettings {
    static let isEnabledKey = "spotlight.isEnabled"
    static let defaultIsEnabled = true

    /// Hält fest, ob der aktuelle Spotlight-Index bereits den vollständigen
    /// Artikel-Bestand widerspiegelt. Wird nach einem erfolgreichen Backfill
    /// auf `true` gesetzt und beim Ausschalten des Schalters (deindexAll)
    /// wieder auf `false` zurückgesetzt, damit ein erneutes Einschalten
    /// zuverlässig einen frischen Backfill auslöst.
    static let hasBackfilledKey = "spotlight.hasBackfilled"
    static let defaultHasBackfilled = false

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: isEnabledKey) != nil else {
            return defaultIsEnabled
        }
        return defaults.bool(forKey: isEnabledKey)
    }

    static func hasBackfilled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: hasBackfilledKey) != nil else {
            return defaultHasBackfilled
        }
        return defaults.bool(forKey: hasBackfilledKey)
    }

    static func setHasBackfilled(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: hasBackfilledKey)
    }
}
