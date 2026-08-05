import Testing
@testable import Feedivo

@MainActor
struct SidebarBadgeInvalidationSignalTests {
    @Test func bumpDirectTagVersionErhoehtDenZaehler() {
        SidebarBadgeInvalidationSignal.shared.reset()
        let initial = SidebarBadgeInvalidationSignal.shared.directTagVersion

        SidebarBadgeInvalidationSignal.shared.bumpDirectTagVersion()

        #expect(SidebarBadgeInvalidationSignal.shared.directTagVersion == initial + 1)
    }

    @Test func resetSetztAufNullZurueck() {
        SidebarBadgeInvalidationSignal.shared.bumpDirectTagVersion()

        SidebarBadgeInvalidationSignal.shared.reset()

        #expect(SidebarBadgeInvalidationSignal.shared.directTagVersion == 0)
    }
}
