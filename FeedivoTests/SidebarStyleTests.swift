import Testing
@testable import Feedivo

struct SidebarStyleTests {

    @Test func darkSidebarActiveSelectionIsSubtle() {
        #expect(SidebarStyle.darkActiveSelectionOpacity == 0.11)
        #expect(SidebarStyle.darkActiveBorderOpacity == 0.07)
    }

    @Test func darkSidebarKeepsSmartFilterIconsVisible() {
        #expect(SidebarStyle.darkIconOpacity == 1.0)
        #expect(SidebarStyle.darkSecondaryTextOpacity < SidebarStyle.darkPrimaryTextOpacity)
    }
}
