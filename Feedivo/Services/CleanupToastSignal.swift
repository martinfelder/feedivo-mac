import Foundation

// Bump-Counter-Signal, bewusst weiterhin UserDefaults/@AppStorage-basiert (GRDB bietet
// keinen @Query/Observation-Mechanismus, Views beobachten deshalb einen hochzählenden
// UserDefaults-Wert per @AppStorage + .onChange) — für einen Bereinigungs-Toast ist keine
// niedrige Latenz nötig, anders als bei SQLiteDataInvalidation/SidebarBadgeInvalidation,
// die seit 2026-08-05 aus genau diesem Latenzgrund auf @Observable umgestellt wurden.
// Diese Nicht-Migration ist bewusst (außerhalb des Scopes der @Observable-Migration),
// keine Regression.
enum CleanupToastSignal {
    static let versionKey = "cleanupToast.version"
    static let deletedCountKey = "cleanupToast.deletedCount"

    static func notify(deletedCount: Int, in defaults: UserDefaults = .standard) {
        // Payload zuerst schreiben, dann den Trigger (versionKey) zuletzt umschalten —
        // so liest die UI beim Beobachten von versionKey immer schon den aktuellen Wert.
        defaults.set(deletedCount, forKey: deletedCountKey)
        defaults.set(defaults.integer(forKey: versionKey) + 1, forKey: versionKey)
    }
}
