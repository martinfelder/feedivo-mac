import SwiftData

enum SidebarSelection: Hashable {
    case smartFilter(SmartFilter)
    case feed(PersistentIdentifier)
    case tag(PersistentIdentifier)
}
