import Testing
import Foundation
@testable import Feedivo

// `.serialized`: Swift Testing fuehrt Tests innerhalb einer Suite standardmaessig PARALLEL aus
// (unabhaengig von `-parallel-testing-enabled NO`, das nur XCTests Prozess-Parallelisierung
// betrifft). Der Notification-Test unten arbeitet auf den prozessweiten Singletons
// SQLiteDataInvalidation/SidebarBadgeInvalidation und setzt sie zu Beginn zurueck — parallel
// laufende Geschwistertests machen ihn dadurch zeitabhaengig und flaky.
@Suite("MCPWriteObserver", .serialized)
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
        // innerhalb desselben Runloop-Tick. Statt einer festen Wartezeit (die unter Last zu kurz
        // sein kann und den Test flaky macht) wird bis zu 2s in kurzen Schritten gepollt und
        // beim ersten Erfolg sofort abgebrochen — im Normalfall dadurch sogar schneller als die
        // vorherige feste Wartezeit.
        for _ in 0..<100 where SQLiteDataInvalidation.shared.statusVersion == 0
            || SidebarBadgeInvalidation.shared.directTagVersion == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(SQLiteDataInvalidation.shared.statusVersion > 0)
        #expect(SidebarBadgeInvalidation.shared.directTagVersion > 0)
    }

    @Test("Benachrichtigung der registrierten Sync-Engine ist ohne laufende Engine ein sicherer No-Op")
    @MainActor
    func benachrichtigungOhneRegistrierteEngineIstSicher() {
        // Der Observer ruft diese Methode bei JEDER Darwin-Notification auf — auch wenn iCloud
        // Sync gar nicht aktiv ist oder die App noch keine Engine registriert hat (in Tests ist
        // das der Normalfall, `register(_:)` wird ausschliesslich von FeedivoApp aufgerufen).
        // Sie muss in diesem Zustand still zurueckkehren statt zu crashen.
        CloudSyncEngine.notifyPendingChangesAvailableUsingRegisteredEngine()
    }
}
