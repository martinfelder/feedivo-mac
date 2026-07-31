import Foundation

/// AppStorage-Keys für den Update-Check, analog BackgroundRefreshSettings/
/// SpotlightIndexingSettings.
enum UpdateCheckSettings {
    static let isAutomaticCheckEnabledKey = "updateCheckIsAutomaticCheckEnabled"
    static let defaultIsAutomaticCheckEnabled = true

    /// Wird von einem stillen Start-Check auf true gesetzt, sobald eine
    /// neuere Version gefunden wurde - zeigt einen dezenten Punkt am
    /// Menüpunkt "Nach Updates suchen". Jeder manuelle Check (Menü ODER
    /// Settings-Tab) setzt das sofort wieder auf false zurück, sobald der
    /// Nutzer selbst hinschaut.
    static let hasUnseenUpdateKey = "updateCheckHasUnseenUpdate"
    static let defaultHasUnseenUpdate = false
}
