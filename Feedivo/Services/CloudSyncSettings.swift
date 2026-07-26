import Foundation

/// Persistente Einstellung für iCloud Sync (Phase 1: nur Tags, siehe
/// docs/superpowers/specs/2026-07-24-icloud-sync-phase1-design.md). Der Toggle wirkt sofort,
/// kein Neustart nötig — anders als der ursprüngliche, überholte SwiftData-Plan
/// (docs/superpowers/specs/2026-07-01-icloud-sync-beta-design.md).
enum CloudSyncSettings {
    static let isEnabledKey = "cloudSync.isEnabled"
    static let defaultIsEnabled = false
    static let cloudKitContainerIdentifier = "iCloud.ch.martin.Feedivo"

    /// Review-Fix (Task 14, Critical 2): `isEnabledKey` selbst flippt sofort beim Umlegen des
    /// Schalters (UI-Responsivität), lange bevor `CloudSyncFirstActivationView`s „Weiter"-Button
    /// den eigentlichen Erst-Aktivierungs-Ablauf abschließt. Dieser zweite, unabhängige Schlüssel
    /// hält fest, ob für die AKTUELLE Aktivierung noch eine offene Erst-Aktivierungs-Entscheidung
    /// ausstehend ist — wird beim Umlegen auf „an" zusammen mit dem Anzeigen des Dialogs auf
    /// `true` gesetzt, und erst dann auf `false` zurückgesetzt, wenn der Dialog tatsächlich per
    /// „Weiter" abgeschlossen wurde (siehe `CloudSyncFirstActivationView.applyDecisions()`/
    /// `SyncSettingsView`). Ohne diesen zweiten Schlüssel würde ein App-Beenden BEVOR der Dialog
    /// abgeschlossen ist dazu führen, dass der nächste App-Start `CloudSyncEngine.start()`
    /// blind aufruft (da `isEnabledKey` schon persistent `true` ist) — genau der Lauf, den der
    /// Erst-Aktivierungs-Dialog verhindern soll, würde dadurch komplett übersprungen.
    static let pendingFirstActivationKey = "cloudSync.pendingFirstActivation"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: isEnabledKey) != nil else {
            return defaultIsEnabled
        }
        return defaults.bool(forKey: isEnabledKey)
    }

    static func hasPendingFirstActivation(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: pendingFirstActivationKey)
    }

    static func setPendingFirstActivation(_ isPending: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(isPending, forKey: pendingFirstActivationKey)
    }

    /// Reine, isoliert testbare Invariante für den Start-Zeitpunkt (App-Launch UND jeder
    /// spätere manuelle Aufruf): die Sync-Engine darf NIEMALS starten, solange für die aktuelle
    /// Aktivierung noch eine Erst-Aktivierungs-Entscheidung ausstehend ist — unabhängig davon,
    /// ob der Nutzer den Schalter bereits eingeschaltet hat.
    static func shouldAutoStartSyncEngineAtLaunch(isEnabled: Bool, hasPendingFirstActivation: Bool) -> Bool {
        isEnabled && !hasPendingFirstActivation
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
