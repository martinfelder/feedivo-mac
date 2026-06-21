import Testing
@testable import Feedivo

struct SidebarStyleTests {

    @Test func lightSidebarActiveSelectionIsSubtle() {
        #expect(SidebarStyle.activeSelectionOpacity == 0.14)
        #expect(SidebarStyle.activeBorderOpacity == 0.12)
    }

    @Test func lightSidebarKeepsSmartFilterIconsVisible() {
        #expect(SidebarStyle.iconOpacity == 1.0)
        #expect(SidebarStyle.secondaryTextOpacity < SidebarStyle.primaryTextOpacity)
    }
}
