import Foundation

/// Persistente Einstellung für iCloud Sync (Phase 1: nur Tags, siehe
/// docs/superpowers/specs/2026-07-24-icloud-sync-phase1-design.md). Der Toggle wirkt sofort,
/// kein Neustart nötig — anders als der ursprüngliche, überholte SwiftData-Plan
/// (docs/superpowers/specs/2026-07-01-icloud-sync-beta-design.md).
enum CloudSyncSettings {
    static let isAvailable = true
    static let isEnabledKey = "cloudSync.isEnabled"
    static let defaultIsEnabled = false
    static let cloudKitContainerIdentifier = "iCloud.ch.martin.Feedivo"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: isEnabledKey) != nil else {
            return defaultIsEnabled
        }
        return defaults.bool(forKey: isEnabledKey)
    }

    static func statusLocalizationKey(
        isEnabled: Bool,
        syncState: CloudSyncStatus.State,
        hasDatabaseError: Bool
    ) -> String {
        if hasDatabaseError {
            return "settings.sync.status.databaseError"
        }

        guard isEnabled else {
            return "settings.sync.status.local"
        }

        switch syncState {
        case .idle, .syncing:
            return "settings.sync.status.active"
        case .accountUnavailable:
            return "settings.sync.status.accountUnavailable"
        case .error:
            return "settings.sync.status.error"
        }
    }
}
