import Foundation

/// UserDefaults-basierte Version — bleibt bis Task 8 als Kompatibilitäts-
/// Fundament für noch nicht migrierte Aufrufer bestehen.
enum SQLiteDataInvalidation {
    static let statusVersionKey = "sqliteData.statusVersion"

    static func bumpStatusVersion(defaults: UserDefaults = .standard) {
        defaults.set(
            defaults.integer(forKey: statusVersionKey) + 1,
            forKey: statusVersionKey
        )
    }
}

/// Ersetzt `SQLiteDataInvalidation`s `UserDefaults`/`@AppStorage`-Mechanismus
/// durch natives SwiftUI-`@Observable` (2026-08-05, Reader-Ladeverzögerung-
/// Folgearbeit — siehe docs/superpowers/specs/2026-08/
/// 2026-08-05-appstorage-observable-migration-design.md). Views lesen
/// `statusVersion` direkt in `body`/`.onChange(of:)`, kein Property-Wrapper
/// nötig. `@MainActor`-isoliert, da `@Observable`-Mutationen — anders als
/// `UserDefaults` — nicht thread-sicher sind; Aufrufer außerhalb des
/// MainActor-Kontexts müssen explizit hoppen (siehe betroffene Tasks).
@MainActor
@Observable
final class SQLiteDataInvalidationSignal {
    static let shared = SQLiteDataInvalidationSignal()
    private init() {}

    private(set) var statusVersion = 0

    func bumpStatusVersion() {
        statusVersion += 1
    }

    /// Nur für Tests: isoliert aufeinanderfolgende Testfälle voneinander,
    /// analog zum bereits bestehenden `-parallel-testing-enabled NO`-
    /// Workaround für `UserDefaults.standard`-Races in diesem Projekt.
    func reset() {
        statusVersion = 0
    }
}
