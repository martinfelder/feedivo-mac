import Foundation
import Testing
@testable import Feedivo

struct CleanupScheduleSettingsTests {
    @Test func defaultsSindWieDokumentiert() {
        #expect(CleanupScheduleSettings.runOnAppStartKey == "cleanupSchedule.runOnAppStart")
        #expect(CleanupScheduleSettings.defaultRunOnAppStart == true)
        #expect(CleanupScheduleSettings.runOnWeekdayTimeKey == "cleanupSchedule.runOnWeekdayTime")
        #expect(CleanupScheduleSettings.defaultRunOnWeekdayTime == false)
        #expect(CleanupScheduleSettings.runOnQuitKey == "cleanupSchedule.runOnQuit")
        #expect(CleanupScheduleSettings.defaultRunOnQuit == false)
    }

    @Test func runOnAppStartLiefertDefaultBeiFehlendemKey() throws {
        let defaults = try temporaryUserDefaults()
        #expect(CleanupScheduleSettings.runOnAppStart(in: defaults) == true)
    }

    @Test func runOnAppStartLiestExplizitGespeichertesFalse() throws {
        let defaults = try temporaryUserDefaults()
        defaults.set(false, forKey: CleanupScheduleSettings.runOnAppStartKey)
        #expect(CleanupScheduleSettings.runOnAppStart(in: defaults) == false)
    }

    @Test func runOnWeekdayTimeLiefertDefaultBeiFehlendemKey() throws {
        let defaults = try temporaryUserDefaults()
        #expect(CleanupScheduleSettings.runOnWeekdayTime(in: defaults) == false)
    }

    @Test func runOnQuitLiefertDefaultBeiFehlendemKey() throws {
        let defaults = try temporaryUserDefaults()
        #expect(CleanupScheduleSettings.runOnQuit(in: defaults) == false)
    }

    @Test func isWeekdayTimeScheduleDueLiefertFalseWennSchalterAus() throws {
        let defaults = try temporaryUserDefaults()
        let now = Date(timeIntervalSince1970: 10_000_000)

        #expect(CleanupScheduleSettings.isWeekdayTimeScheduleDue(now: now, defaults: defaults) == false)
    }

    @Test func isWeekdayTimeScheduleDueLiefertTrueBeiNieGelaufenemZeitplan() throws {
        let defaults = try temporaryUserDefaults()
        defaults.set(true, forKey: CleanupScheduleSettings.runOnWeekdayTimeKey)
        let now = Date(timeIntervalSince1970: 10_000_000)

        #expect(CleanupScheduleSettings.isWeekdayTimeScheduleDue(now: now, defaults: defaults) == true)
    }

    @Test func isWeekdayTimeScheduleDueLiefertFalseWennGenauZurSollzeitBereitsGelaufen() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let defaults = try temporaryUserDefaults()
        defaults.set(true, forKey: CleanupScheduleSettings.runOnWeekdayTimeKey)

        let now = Date(timeIntervalSince1970: 10_000_000)
        let todayWeekday = calendar.component(.weekday, from: now)
        let todayStart = calendar.startOfDay(for: now)
        let scheduledTime = calendar.date(byAdding: .minute, value: 60, to: todayStart)!

        defaults.set("\(todayWeekday)", forKey: CleanupScheduleSettings.weekdaysKey)
        defaults.set(60, forKey: CleanupScheduleSettings.timeMinutesKey)
        defaults.set(scheduledTime, forKey: CleanupScheduleSettings.lastScheduleRunAtKey)

        #expect(CleanupScheduleSettings.isWeekdayTimeScheduleDue(now: now, calendar: calendar, defaults: defaults) == false)
    }

    @Test func isWeekdayTimeScheduleDueLiefertTrueBeiNachholBedarfNachMehrerenWochen() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let defaults = try temporaryUserDefaults()
        defaults.set(true, forKey: CleanupScheduleSettings.runOnWeekdayTimeKey)

        let now = Date(timeIntervalSince1970: 10_000_000)
        let todayWeekday = calendar.component(.weekday, from: now)
        defaults.set("\(todayWeekday)", forKey: CleanupScheduleSettings.weekdaysKey)
        defaults.set(60, forKey: CleanupScheduleSettings.timeMinutesKey)

        // Letzter Lauf liegt 3 Wochen zurück — mehrere fällige Termine wurden verpasst
        // (App war nicht offen), muss trotzdem als fällig erkannt werden (Nachholen).
        let lastRunAt = now.addingTimeInterval(-21 * 24 * 60 * 60)
        defaults.set(lastRunAt, forKey: CleanupScheduleSettings.lastScheduleRunAtKey)

        #expect(CleanupScheduleSettings.isWeekdayTimeScheduleDue(now: now, calendar: calendar, defaults: defaults) == true)
    }

    @Test func isWeekdayTimeScheduleDueBleibtFalseWennHeutigeZielzeitNochNichtErreichtWurde() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let defaults = try temporaryUserDefaults()
        defaults.set(true, forKey: CleanupScheduleSettings.runOnWeekdayTimeKey)

        // now liegt bei diesem Referenz-Timestamp bei ca. 17:46 UTC.
        let now = Date(timeIntervalSince1970: 10_000_000)
        let todayWeekday = calendar.component(.weekday, from: now)
        let todayStart = calendar.startOfDay(for: now)
        let futureTimeMinutesToday = 23 * 60 // 23:00 Uhr, noch nicht erreicht

        defaults.set("\(todayWeekday)", forKey: CleanupScheduleSettings.weekdaysKey)
        defaults.set(futureTimeMinutesToday, forKey: CleanupScheduleSettings.timeMinutesKey)

        // Letzter Lauf: exakt vor 7 Tagen zur selben (damals bereits erreichten) Zielzeit.
        let scheduledTimeToday = calendar.date(byAdding: .minute, value: futureTimeMinutesToday, to: todayStart)!
        let lastRunAt = calendar.date(byAdding: .day, value: -7, to: scheduledTimeToday)!
        defaults.set(lastRunAt, forKey: CleanupScheduleSettings.lastScheduleRunAtKey)

        #expect(CleanupScheduleSettings.isWeekdayTimeScheduleDue(now: now, calendar: calendar, defaults: defaults) == false)
    }

    @Test func parseWeekdaysLiestKommagetrennteWerte() {
        #expect(CleanupScheduleSettings.parseWeekdays("1,3,5") == [1, 3, 5])
    }

    @Test func parseWeekdaysLiefertDefaultBeiLeeremString() {
        #expect(CleanupScheduleSettings.parseWeekdays("") == [1])
    }

    @Test func formatWeekdaysSortiertUndVerbindet() {
        #expect(CleanupScheduleSettings.formatWeekdays([5, 1, 3]) == "1,3,5")
    }

    @Test func weekdaysLiefertDefaultBeiFehlendemKey() throws {
        let defaults = try temporaryUserDefaults()
        #expect(CleanupScheduleSettings.weekdays(in: defaults) == [1])
    }

    @Test func weekdaysLiestGespeicherteMehrfachauswahl() throws {
        let defaults = try temporaryUserDefaults()
        defaults.set("2,4", forKey: CleanupScheduleSettings.weekdaysKey)
        #expect(CleanupScheduleSettings.weekdays(in: defaults) == [2, 4])
    }

    @Test func isWeekdayTimeScheduleDueLiefertTrueWennEinerVonMehrerenTagenFaelligIst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let defaults = try temporaryUserDefaults()
        defaults.set(true, forKey: CleanupScheduleSettings.runOnWeekdayTimeKey)

        let now = Date(timeIntervalSince1970: 10_000_000)
        let todayWeekday = calendar.component(.weekday, from: now)
        // Ein weiterer, "unbeteiligter" Wochentag (nicht heute) wird mit ausgewählt —
        // heute soll trotzdem als fällig erkannt werden, weil MINDESTENS einer der
        // gewählten Tage fällig ist.
        let otherWeekday = (todayWeekday % 7) + 1
        defaults.set("\(todayWeekday),\(otherWeekday)", forKey: CleanupScheduleSettings.weekdaysKey)
        defaults.set(60, forKey: CleanupScheduleSettings.timeMinutesKey) // 01:00 Uhr, heute bereits erreicht

        #expect(CleanupScheduleSettings.isWeekdayTimeScheduleDue(now: now, calendar: calendar, defaults: defaults) == true)
    }

    @Test func isWeekdayTimeScheduleDueLiefertFalseWennKeinerDerMehrerenTageFaelligIst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let defaults = try temporaryUserDefaults()
        defaults.set(true, forKey: CleanupScheduleSettings.runOnWeekdayTimeKey)

        let now = Date(timeIntervalSince1970: 10_000_000)
        let todayWeekday = calendar.component(.weekday, from: now)
        let otherWeekday = (todayWeekday % 7) + 1
        defaults.set("\(todayWeekday),\(otherWeekday)", forKey: CleanupScheduleSettings.weekdaysKey)
        defaults.set(60, forKey: CleanupScheduleSettings.timeMinutesKey) // 01:00 Uhr

        // lastRunAt liegt NACH der heutigen 01:00-Uhr-Sollzeit UND nach der Sollzeit des
        // anderen gewählten Tages in dieser Woche — für beide Tage ist die aktuelle
        // Woche also bereits "erledigt", keiner ist fällig.
        let todayStart = calendar.startOfDay(for: now)
        let todayScheduledTime = calendar.date(byAdding: .minute, value: 60, to: todayStart)!
        let lastRunAt = todayScheduledTime.addingTimeInterval(6 * 24 * 60 * 60) // fast eine Woche später

        defaults.set(lastRunAt, forKey: CleanupScheduleSettings.lastScheduleRunAtKey)

        #expect(CleanupScheduleSettings.isWeekdayTimeScheduleDue(now: lastRunAt.addingTimeInterval(60), calendar: calendar, defaults: defaults) == false)
    }
}

private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "FeedivoTests.CleanupSchedule.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
