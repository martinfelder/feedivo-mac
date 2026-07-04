import Foundation

enum SwiftDataBridgeSettings {
    /// Schaltet den produktiven Schreib-Übergang von SQLite zurück nach SwiftData.
    ///
    /// `true` entspricht dem aktuellen Übergangszustand (Bridge aktiv),
    /// `false` schaltet den Übergang ab.
    static let isEnabledKey = "swiftDataBridge.isEnabled"
    static let defaultIsEnabled = true
}
