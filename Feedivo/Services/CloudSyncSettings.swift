import Foundation

enum CloudSyncSettings {
    static let isAvailable = false
    static let isEnabledKey = "cloudSync.isEnabled"
    static let defaultIsEnabled = false
    static let cloudKitContainerIdentifier = "iCloud.ch.martin.Feedivo"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        guard isAvailable else {
            return false
        }

        guard defaults.object(forKey: isEnabledKey) != nil else {
            return defaultIsEnabled
        }

        return defaults.bool(forKey: isEnabledKey)
    }

    static func statusText(
        isEnabledAtLaunch: Bool,
        currentIsEnabled: Bool,
        hasDatabaseError: Bool
    ) -> String {
        if hasDatabaseError {
            return "Datenbank konnte nicht geladen werden"
        }

        guard isAvailable else {
            return "iCloud Sync noch nicht verfügbar"
        }

        if isEnabledAtLaunch == currentIsEnabled {
            return isEnabledAtLaunch ? "iCloud Sync aktiv" : "Lokal gespeichert"
        }

        return currentIsEnabled
            ? "iCloud Sync nach Neustart aktiv"
            : "iCloud Sync nach Neustart deaktiviert"
    }

    static func statusLocalizationKey(
        isEnabledAtLaunch: Bool,
        currentIsEnabled: Bool,
        hasDatabaseError: Bool
    ) -> String {
        if hasDatabaseError {
            return "settings.sync.status.databaseError"
        }

        guard isAvailable else {
            return "settings.sync.status.unavailable"
        }

        if isEnabledAtLaunch == currentIsEnabled {
            return isEnabledAtLaunch
                ? "settings.sync.status.active"
                : "settings.sync.status.local"
        }

        return currentIsEnabled
            ? "settings.sync.status.restartEnable"
            : "settings.sync.status.restartDisable"
    }
}
