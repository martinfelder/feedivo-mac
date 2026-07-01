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

    @Test func nextScheduledRefreshDateNutztGeklemmtesIntervall() {
        let now = Date(timeIntervalSince1970: 1_000)

        let nextRefreshDate = BackgroundRefreshSettings.nextScheduledRefreshDate(
            intervalMinutes: 44,
            now: now
        )

        #expect(nextRefreshDate == now.addingTimeInterval(30 * 60))
    }

    @Test func statusTextBeschreibtGespeichertenStatus() {
        #expect(BackgroundRefreshSettings.statusText(for: BackgroundRefreshSettings.statusSuccess) == "Erfolgreich")
        #expect(BackgroundRefreshSettings.statusText(for: BackgroundRefreshSettings.statusFailed) == "Fehlgeschlagen")
        #expect(BackgroundRefreshSettings.statusText(for: nil) == "Noch nicht gelaufen")
        #expect(BackgroundRefreshSettings.statusText(for: "unbekannt") == "Noch nicht gelaufen")
    }

    @Test func refreshOnLaunchIstStandardmaessigAus() {
        #expect(BackgroundRefreshSettings.refreshOnLaunchIsEnabledKey == "backgroundRefresh.refreshOnLaunchIsEnabled")
        #expect(BackgroundRefreshSettings.defaultRefreshOnLaunchIsEnabled == false)
    }
}
