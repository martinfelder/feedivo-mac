import Testing
@testable import Feedivo

@MainActor
struct SidebarBadgeInvalidationSignalTests {
    @Test func bumpDirectTagVersionErhoehtDenZaehler() {
        SidebarBadgeInvalidation.shared.reset()
        let initial = SidebarBadgeInvalidation.shared.directTagVersion

        SidebarBadgeInvalidation.shared.bumpDirectTagVersion()

        #expect(SidebarBadgeInvalidation.shared.directTagVersion == initial + 1)
    }

    @Test func resetSetztAufNullZurueck() {
        SidebarBadgeInvalidation.shared.bumpDirectTagVersion()

        SidebarBadgeInvalidation.shared.reset()

        #expect(SidebarBadgeInvalidation.shared.directTagVersion == 0)
    }
}
