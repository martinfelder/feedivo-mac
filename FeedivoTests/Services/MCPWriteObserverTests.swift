import Testing
import Foundation
@testable import Feedivo

@Suite("MCPWriteObserver")
struct MCPWriteObserverTests {
    @Test("Bumpt statusVersion und directTagVersion nach Empfang der Darwin-Notification")
    @MainActor
    func bumptVersionenNachNotification() async throws {
        SQLiteDataInvalidation.shared.reset()
        SidebarBadgeInvalidation.shared.reset()
        MCPWriteObserver.startObserving()

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(MCPWriteNotificationName.darwin),
            nil,
            nil,
            true
        )

        // Darwin-Notifications werden über notifyd zugestellt — nicht garantiert synchron
        // innerhalb desselben Runloop-Tick, deshalb kurze Wartezeit statt sofortiger Assertion.
        try await Task.sleep(for: .milliseconds(300))

        #expect(SQLiteDataInvalidation.shared.statusVersion > 0)
        #expect(SidebarBadgeInvalidation.shared.directTagVersion > 0)
    }
}
