import Foundation

enum SidebarSectionCollapseState {
    enum Section: CaseIterable, Hashable {
        case smartFilters
        case tags
        case rules
        case folders

        var storageKey: String {
            switch self {
            case .smartFilters:
                "sidebar.section.smartFilters.isCollapsed"
            case .tags:
                "sidebar.section.tags.isCollapsed"
            case .rules:
                "sidebar.section.rules.isCollapsed"
            case .folders:
                "sidebar.section.folders.isCollapsed"
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
