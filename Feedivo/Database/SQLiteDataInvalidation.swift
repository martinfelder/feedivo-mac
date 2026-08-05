import Foundation

/// Ersetzt einen vormaligen `UserDefaults`/`@AppStorage`-Mechanismus durch
/// natives SwiftUI-`@Observable` (2026-08-05, Reader-Ladeverzögerung-
/// Folgearbeit — siehe docs/superpowers/specs/2026-08/
/// 2026-08-05-appstorage-observable-migration-design.md). Views lesen
/// `statusVersion` direkt in `body`/`.onChange(of:)`, kein Property-Wrapper
/// nötig. `@MainActor`-isoliert, da `@Observable`-Mutationen — anders als
/// `UserDefaults` — nicht thread-sicher sind.
@MainActor
@Observable
final class SQLiteDataInvalidation {
    static let shared = SQLiteDataInvalidation()
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
