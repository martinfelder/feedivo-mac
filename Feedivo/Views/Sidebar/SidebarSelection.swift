import Foundation

// SidebarSelection trägt für Feeds die SQLite-Feed-ID (FeedRecord.id, ein
// UUID-String) statt einer SwiftData-PersistentIdentifier. Damit ist die
// Navigationsidentität vollständig SQLite-seitig; SwiftData `Feed` wird nur noch
// als Übergangs-Aktionsbackend per ID aufgelöst.
enum SidebarSelection: Hashable {
    case smartFilter(SmartFilter)
    case feed(String)
    case tag(String)
    case smartFolder(String)
}
