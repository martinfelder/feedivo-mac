import Testing
@testable import Feedivo

struct SidebarSectionCollapseStateTests {
    @MainActor
    @Test func appStorageKeysBleibenStabil() {
        #expect(SidebarSectionCollapseState.Section.smartFilters.storageKey == "sidebar.section.smartFilters.isCollapsed")
        #expect(SidebarSectionCollapseState.Section.tags.storageKey == "sidebar.section.tags.isCollapsed")
        #expect(SidebarSectionCollapseState.Section.folders.storageKey == "sidebar.section.folders.isCollapsed")
        #expect(SidebarSectionCollapseState.Section.smartFolders.storageKey == "sidebar.section.smartFolders.isCollapsed")
        #expect(SidebarSectionCollapseState.Section.customSmartFolders.storageKey == "sidebar.section.customSmartFolders.isCollapsed")
    }
}
