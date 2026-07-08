import Foundation

enum SidebarSectionCollapseState {
    enum Section: CaseIterable, Hashable {
        case smartFilters
        case tags
        case folders
        case smartFolders
        case customSmartFolders

        var storageKey: String {
            switch self {
            case .smartFilters:
                "sidebar.section.smartFilters.isCollapsed"
            case .tags:
                "sidebar.section.tags.isCollapsed"
            case .folders:
                "sidebar.section.folders.isCollapsed"
            case .smartFolders:
                "sidebar.section.smartFolders.isCollapsed"
            case .customSmartFolders:
                "sidebar.section.customSmartFolders.isCollapsed"
            }
        }
    }

    static func toggle(_ section: Section, in collapsedSections: inout Set<Section>) {
        if collapsedSections.contains(section) {
            collapsedSections.remove(section)
        } else {
            collapsedSections.insert(section)
        }
    }
}
