import Foundation

// Drei unabhängig schaltbare automatische Auslöser für die Artikel-Bereinigung.
// Ersetzt den bisherigen unbedingten Trigger bei jedem Hintergrund-Refresh-Zyklus
// (Feature 17.3a).
enum CleanupScheduleSettings {
    static let runOnAppStartKey = "cleanupSchedule.runOnAppStart"
    static let defaultRunOnAppStart = true

    static let runOnWeekdayTimeKey = "cleanupSchedule.runOnWeekdayTime"
    static let defaultRunOnWeekdayTime = false

    // Kommagetrennt, z. B. "1,3,5" — Calendar.weekday-Konvention (1 = Sonntag).
    static let weekdaysKey = "cleanupSchedule.weekdays"
    static let defaultWeekdaysStored = "1"
    static let defaultWeekdays: Set<Int> = [1]

    static let timeMinutesKey = "cleanupSchedule.timeMinutes"  // Minuten seit Mitternacht, 0...1439
    static let defaultTimeMinutes = 180                        // 03:00 Uhr

    static let runOnQuitKey = "cleanupSchedule.runOnQuit"
    static let defaultRunOnQuit = false

    static let lastScheduleRunAtKey = "cleanupSchedule.lastScheduleRunAt"

    static func runOnAppStart(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: runOnAppStartKey) != nil else {
            return defaultRunOnAppStart
        }
        return defaults.bool(forKey: runOnAppStartKey)
    }

    static func runOnWeekdayTime(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: runOnWeekdayTimeKey) != nil else {
            return defaultRunOnWeekdayTime
        }
        return defaults.bool(forKey: runOnWeekdayTimeKey)
    }

    static func runOnQuit(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: runOnQuitKey) != nil else {
            return defaultRunOnQuit
        }
        return defaults.bool(forKey: runOnQuitKey)
    }

    /// Parst den kommagetrennten Rohwert zu einer Menge von Wochentagen. Liefert bei
    /// leerem oder komplett unparsbarem Input den Default (Sonntag) statt einer leeren
    /// Menge — eine leere Auswahl würde die Zeitplan-Prüfung sonst nie fällig werden
    /// lassen, ohne dass das für den Nutzer sichtbar wäre.
    static func parseWeekdays(_ raw: String) -> Set<Int> {
        let parsed = Set(raw.split(separator: ",").compactMap { Int($0) })
        return parsed.isEmpty ? defaultWeekdays : parsed
    }

    static func formatWeekdays(_ weekdays: Set<Int>) -> String {
        weekdays.sorted().map(String.init).joined(separator: ",")
    }

    static func weekdays(in defaults: UserDefaults = .standard) -> Set<Int> {
        guard let stored = defaults.string(forKey: weekdaysKey) else {
            return defaultWeekdays
        }
        return parseWeekdays(stored)
    }

    static func timeMinutes(in defaults: UserDefaults = .standard) -> Int {
        guard defaults.object(forKey: timeMinutesKey) != nil else {
            return defaultTimeMinutes
        }
        return defaults.integer(forKey: timeMinutesKey)
    }

    static func recordScheduleRun(now: Date, in defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: lastScheduleRunAtKey)
    }

    /// Nachhol-Prüfung: liefert true, wenn für MINDESTENS EINEN der konfigurierten
    /// Wochentage die Sollzeit seit dem letzten geloggten Zeitplan-Lauf bereits
    /// erreicht/verstrichen ist. Feedivo läuft nicht durchgehend — ein verpasster
    /// Zeitpunkt wird beim nächsten Kontakt (App-Start, Hintergrund-Refresh-Tick)
    /// nachgeholt, statt komplett auszufallen. Bei mehreren gewählten Wochentagen läuft
    /// die Bereinigung entsprechend mehrfach pro Woche.
    static func isWeekdayTimeScheduleDue(
        now: Date,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard runOnWeekdayTime(in: defaults) else {
            return false
        }

        let selectedWeekdays = weekdays(in: defaults)
        let configuredTimeMinutes = timeMinutes(in: defaults)
        let mostRecentDue = selectedWeekdays
            .map { weekday in
                mostRecentOccurrence(
                    weekday: weekday,
                    timeMinutes: configuredTimeMinutes,
                    atOrBefore: now,
                    calendar: calendar
                )
            }
            .max() ?? .distantPast

        guard let lastRunAt = defaults.object(forKey: lastScheduleRunAtKey) as? Date else {
            return true
        }

        return mostRecentDue > lastRunAt
    }

    /// Letzter Zeitpunkt in der Vergangenheit (oder jetzt), an dem weekday+timeMinutes
    /// zugetroffen hätte. Ist heute bereits der Zielwochentag, die Zielzeit aber noch
    /// nicht erreicht, zählt das heutige Vorkommen noch nicht — es wird eine Woche
    /// zurückgerechnet.
    private static func mostRecentOccurrence(
        weekday: Int,
        timeMinutes: Int,
        atOrBefore now: Date,
        calendar: Calendar
    ) -> Date {
        let currentWeekday = calendar.component(.weekday, from: now)
        let daysBack = (currentWeekday - weekday + 7) % 7

        func candidate(daysBack: Int) -> Date {
            let todayStart = calendar.startOfDay(for: now)
            let dayStart = calendar.date(byAdding: .day, value: -daysBack, to: todayStart) ?? todayStart
            return calendar.date(byAdding: .minute, value: timeMinutes, to: dayStart) ?? dayStart
        }

        let result = candidate(daysBack: daysBack)
        if result > now {
            return candidate(daysBack: daysBack + 7)
        }
        return result
    }
}
