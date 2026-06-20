import Foundation
import Testing
@testable import Feedivo

struct BackgroundRefreshSettingsTests {

    @Test func clampIntervalNutztNaechstesErlaubtesIntervall() {
        #expect(BackgroundRefreshSettings.clampedIntervalMinutes(5) == 15)
        #expect(BackgroundRefreshSettings.clampedIntervalMinutes(44) == 30)
        #expect(BackgroundRefreshSettings.clampedIntervalMinutes(300) == 120)
    }

    @Test func earliestBeginDateIstNilWennAutomatischerRefreshAusIst() {
        let now = Date(timeIntervalSince1970: 1_000)

        let earliestBeginDate = BackgroundRefreshSettings.earliestBeginDate(
            isEnabled: false,
            intervalMinutes: 30,
            now: now
        )

        #expect(earliestBeginDate == nil)
    }

    @Test func earliestBeginDateNutztGeklemmtesIntervallWennAktiv() throws {
        let now = Date(timeIntervalSince1970: 1_000)

        let earliestBeginDate = try #require(
            BackgroundRefreshSettings.earliestBeginDate(
                isEnabled: true,
                intervalMinutes: 44,
                now: now
            )
        )

        #expect(earliestBeginDate == now.addingTimeInterval(30 * 60))
    }
}
