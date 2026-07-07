import Foundation

// SidebarSelection trägt für Feeds die SQLite-Feed-ID (FeedRecord.id, ein
// UUID-String). Die Navigationsidentität ist vollständig SQLite-seitig.
enum SidebarSelection: Hashable {
    case smartFilter(SmartFilter)
    case feed(String)
    case tag(String)
    case smartFolder(String)
}
