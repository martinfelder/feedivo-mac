import Foundation

// Bump-Counter-Signal nach dem Muster von SQLiteDataInvalidation — GRDB bietet keinen
// @Query/Observation-Mechanismus, Views beobachten stattdessen einen hochzählenden
// UserDefaults-Wert per @AppStorage + .onChange.
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
