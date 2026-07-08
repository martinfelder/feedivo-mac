import Foundation

/// Trennt die (bereits nach Sichtbarkeit gefilterten) Intelligenten-Ordner-Snapshots
/// der Sidebar in Standard-Ordner (mitgeliefert, `defaultKey != nil`) und
/// benutzerdefinierte Ordner (`defaultKey == nil`, inklusive Duplikate von
/// Standard-Ordnern — siehe `SQLiteSmartFolderStore.duplicate`, das immer
/// `defaultKey: nil` setzt). Reiner Filter ohne Neusortierung, damit die
/// bestehende Reihenfolge innerhalb jeder Gruppe erhalten bleibt.
enum SmartFolderSidebarGrouping {
    static func defaultFolders(from snapshots: [SQLiteSmartFolderSnapshot]) -> [SQLiteSmartFolderSnapshot] {
        snapshots.filter { $0.defaultKey != nil }
    }

    static func customFolders(from snapshots: [SQLiteSmartFolderSnapshot]) -> [SQLiteSmartFolderSnapshot] {
        snapshots.filter { $0.defaultKey == nil }
    }
}
