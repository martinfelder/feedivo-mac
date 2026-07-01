import Foundation

enum CloudSyncSettings {
    static let isEnabledKey = "cloudSync.isEnabled"
    static let defaultIsEnabled = false
    static let cloudKitContainerIdentifier = "iCloud.ch.martin.Feedivo"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
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

        if isEnabledAtLaunch == currentIsEnabled {
            return isEnabledAtLaunch ? "iCloud Sync aktiv" : "Lokal gespeichert"
        }

        return currentIsEnabled
            ? "iCloud Sync nach Neustart aktiv"
            : "iCloud Sync nach Neustart deaktiviert"
    }
}
