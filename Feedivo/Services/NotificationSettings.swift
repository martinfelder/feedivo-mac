import Foundation
import AppKit

enum NotificationSettings {
    static let isMasterEnabledKey = "notifications.master.isEnabled"
    static let defaultIsMasterEnabled = true

    static let defaultEnabledForNewFeedsKey = "notifications.newFeeds.defaultEnabled"
    static let defaultEnabledForNewFeedsDefault = false

    static let appSpecificSystemSettingsURLString =
        "x-apple.systempreferences:com.apple.Notifications-Settings.extension?ch.martin.Feedivo"
    static let fallbackSystemSettingsURLString =
        "x-apple.systempreferences:com.apple.preference.notifications"

    /// Liest den Master-Schalter sicher aus `UserDefaults`. Ein naives
    /// `UserDefaults.bool(forKey:)` liefert bei fehlendem Key `false` statt des
    /// gewünschten Defaults `true` — Bestandsnutzer, die diese Einstellungsseite nie
    /// öffnen, würden sonst beim Update sämtliche Benachrichtigungen verlieren.
    static func isMasterEnabled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: isMasterEnabledKey) != nil else {
            return defaultIsMasterEnabled
        }
        return defaults.bool(forKey: isMasterEnabledKey)
    }

    /// Gleiche Absicherung wie oben, für den "Standard für neue Feeds"-Schalter.
    static func isEnabledForNewFeeds(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: defaultEnabledForNewFeedsKey) != nil else {
            return defaultEnabledForNewFeedsDefault
        }
        return defaults.bool(forKey: defaultEnabledForNewFeedsKey)
    }

    /// Springt zur App-eigenen Benachrichtigungsseite in den Systemeinstellungen.
    /// Bewusst ohne Laufzeit-Fallback auf `fallbackSystemSettingsURLString`:
    /// `NSWorkspace.open(_:)` liefert kein verlässliches Signal, ob die private
    /// URL tatsächlich auf der App-eigenen Seite statt nur der allgemeinen
    /// Übersicht gelandet ist. Welche der beiden Konstanten hier verwendet wird,
    /// ist stattdessen eine Code-Entscheidung nach manueller Live-Verifikation.
    static func openSystemNotificationSettings() {
        guard let url = URL(string: appSpecificSystemSettingsURLString) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
