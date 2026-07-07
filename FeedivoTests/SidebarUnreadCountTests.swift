import Testing
@testable import Feedivo

struct SidebarUnreadCountTests {
    @Test func badgeTextIstNurFuerPositiveZaehlerSichtbar() {
        #expect(SidebarUnreadCount.badgeText(for: 0) == nil)
        #expect(SidebarUnreadCount.badgeText(for: 7) == "7")
    }
}
