import Foundation

enum SwiftDataBridgeSettings {
    /// Schaltet den produktiven Schreib-Übergang von SQLite zurück nach SwiftData.
    ///
    /// `false` ist der SQLite-only Standard. `true` darf nur noch für gezielte
    /// Legacy-Migrationstests gesetzt werden.
    static let isEnabledKey = "swiftDataBridge.isEnabled"
    static let defaultIsEnabled = false
}
