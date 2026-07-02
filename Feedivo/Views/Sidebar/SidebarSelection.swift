import SwiftData

enum SidebarSelection: Hashable {
    case smartFilter(SmartFilter)
    case feed(PersistentIdentifier)
    case tag(String)
    case smartFolder(PersistentIdentifier)
}
