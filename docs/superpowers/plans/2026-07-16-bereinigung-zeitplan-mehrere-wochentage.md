# Zeitplan — Mehrere Wochentage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Den Bereinigungs-Zeitplan von genau einem wählbaren Wochentag auf eine
Mehrfachauswahl mehrerer Wochentage umstellen (Nachtrag zu Feature 17.3a).

**Architecture:** `CleanupScheduleSettings.weekdayKey`/`defaultWeekday` (einzelner `Int`)
wird durch `weekdaysKey` (kommagetrennter String, geparst zu `Set<Int>`) ersetzt.
`isWeekdayTimeScheduleDue` berechnet den zuletzt fälligen Zeitpunkt für jeden gewählten
Wochentag (unveränderte private `mostRecentOccurrence`-Funktion) und nimmt das Maximum.
Die Settings-UI ersetzt den Einzel-Picker durch 7 native Checkbox-Zeilen mit
Mindestauswahl-Zwang (letzter verbleibender Haken lässt sich nicht abwählen).

**Tech Stack:** Swift, SwiftUI, Swift Testing.

## Global Constraints

- Kommentare im Code auf Deutsch (Projektkonvention).
- Direktes Committen auf `main` (kein Feature-Branch/Worktree, etablierte
  Nutzerpräferenz).
- `xcodebuild build` muss nach jedem Task grün sein; volle Testsuite nicht unscoped
  laufen lassen (hängt) — immer `-only-testing:FeedivoTests/<SuiteName>`.
- Feature 17.3a (inkl. dieser Zeitplan-Funktion) ist noch nicht gepusht — keine
  Abwärtskompatibilität/Migration für den alten `weekdayKey`-Wert nötig, er wird
  ersatzlos ersetzt.
- Mindestens ein Wochentag muss immer ausgewählt bleiben, solange der Zeitplan-Schalter
  aktiv ist.
- Standard-Auswahl beim ersten Aktivieren: Sonntag (`weekday == 1`).

---

### Task 1: Datenmodell — Mehrfachauswahl in `CleanupScheduleSettings`

**Files:**
- Modify: `Feedivo/Services/CleanupScheduleSettings.swift`
- Modify: `FeedivoTests/CleanupScheduleSettingsTests.swift`

**Interfaces:**
- Consumes: nichts Neues (reine `UserDefaults`+`Calendar`-Logik, wie zuvor).
- Produces: `CleanupScheduleSettings.weekdaysKey` (String, ersetzt `weekdayKey`),
  `CleanupScheduleSettings.defaultWeekdaysStored` (String, `"1"` — Rohwert für
  `@AppStorage`-Initialisierung in Task 2), `CleanupScheduleSettings.defaultWeekdays`
  (`Set<Int>`, `[1]`), `CleanupScheduleSettings.parseWeekdays(_ raw: String) -> Set<Int>`,
  `CleanupScheduleSettings.formatWeekdays(_ weekdays: Set<Int>) -> String`,
  `CleanupScheduleSettings.weekdays(in defaults: UserDefaults = .standard) -> Set<Int>`.
  `weekdayKey`/`defaultWeekday`/`weekday(in:)` entfallen ersatzlos. Task 2 konsumiert
  `parseWeekdays`/`formatWeekdays`/`defaultWeekdaysStored`/`weekdaysKey` direkt.

- [ ] **Step 1: Bestehende Tests, die `weekdayKey` nutzen, auf `weekdaysKey` umstellen**

In `FeedivoTests/CleanupScheduleSettingsTests.swift` die drei Tests
`isWeekdayTimeScheduleDueLiefertFalseWennGenauZurSollzeitBereitsGelaufen`,
`isWeekdayTimeScheduleDueLiefertTrueBeiNachholBedarfNachMehrerenWochen` und
`isWeekdayTimeScheduleDueBleibtFalseWennHeutigeZielzeitNochNichtErreichtWurde` jeweils so
ändern, dass die Zeile

```swift
defaults.set(todayWeekday, forKey: CleanupScheduleSettings.weekdayKey)
```

ersetzt wird durch

```swift
defaults.set("\(todayWeekday)", forKey: CleanupScheduleSettings.weekdaysKey)
```

(Sonst bleibt jeder der drei Tests unverändert — nur diese eine Zeile ändert sich pro
Test.)

- [ ] **Step 2: Run bestehende Tests, um zu bestätigen, dass sie jetzt fehlschlagen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CleanupScheduleSettingsTests`
Expected: FAIL — `weekdaysKey` existiert noch nicht in `CleanupScheduleSettings`
(Compile-Fehler "Type 'CleanupScheduleSettings' has no member 'weekdaysKey'").

- [ ] **Step 3: Neue Tests für `parseWeekdays`/`formatWeekdays` und Mehrfachauswahl-Fälligkeit schreiben**

Direkt nach `isWeekdayTimeScheduleDueBleibtFalseWennHeutigeZielzeitNochNichtErreichtWurde`
(vor der schließenden `}` des Structs) ergänzen:

```swift
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
```

- [ ] **Step 4: Run neue Tests, um zu bestätigen, dass sie fehlschlagen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CleanupScheduleSettingsTests`
Expected: FAIL — `parseWeekdays`/`formatWeekdays`/`weekdays(in:)` existieren noch nicht.

- [ ] **Step 5: `CleanupScheduleSettings.swift` auf Mehrfachauswahl umstellen**

Die gesamte Datei `Feedivo/Services/CleanupScheduleSettings.swift` durch folgenden Inhalt
ersetzen:

```swift
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
```

- [ ] **Step 6: Run alle Tests, um zu bestätigen, dass sie jetzt bestehen**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CleanupScheduleSettingsTests`
Expected: PASS — alle Tests grün (bestehende + 7 neue).

- [ ] **Step 7: Build verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: Schlägt zunächst FEHL — `Feedivo/Views/Settings/SettingsView.swift` referenziert
noch `CleanupScheduleSettings.weekdayKey`/`defaultWeekday`, die in diesem Task entfernt
wurden. Das ist erwartet: Task 2 stellt `SettingsView.swift` auf die neue API um. Für
dieses Task genügt der grüne Testlauf aus Step 6; der App-Build ist erst nach Task 2
wieder durchgängig grün. Nicht versuchen, `SettingsView.swift` in diesem Task zu
reparieren — das ist Task 2s Aufgabe.

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Services/CleanupScheduleSettings.swift FeedivoTests/CleanupScheduleSettingsTests.swift
git commit -m "Feature: CleanupScheduleSettings unterstützt Mehrfachauswahl von Wochentagen"
```

---

### Task 2: Einstellungen-UI — Checkbox-Mehrfachauswahl statt Einzel-Picker

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (`CleanupSettingsView`)

**Interfaces:**
- Consumes: `CleanupScheduleSettings.weekdaysKey`, `defaultWeekdaysStored`,
  `parseWeekdays(_:)`, `formatWeekdays(_:)` (Task 1).

- [ ] **Step 1: `@AppStorage`-Property für den Einzel-Wochentag ersetzen**

In `Feedivo/Views/Settings/SettingsView.swift`, die bestehenden Zeilen

```swift
    @AppStorage(CleanupScheduleSettings.weekdayKey)
    private var cleanupWeekday = CleanupScheduleSettings.defaultWeekday
```

ersetzen durch

```swift
    @AppStorage(CleanupScheduleSettings.weekdaysKey)
    private var cleanupWeekdaysRaw = CleanupScheduleSettings.defaultWeekdaysStored
```

- [ ] **Step 2: Picker durch 7 Checkbox-Zeilen ersetzen**

Den bestehenden Block

```swift
                if cleanupRunOnWeekdayTime {
                    HStack(spacing: 12) {
                        Spacer(minLength: 202)

                        Picker("", selection: $cleanupWeekday) {
                            ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                                Text(symbol).tag(index + 1)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 130)

                        DatePicker("", selection: cleanupScheduleTimeBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.stepperField)

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
```

ersetzen durch

```swift
                if cleanupRunOnWeekdayTime {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                            let weekdayNumber = index + 1
                            HStack(spacing: 12) {
                                Spacer(minLength: 202)
                                Toggle(symbol, isOn: Binding(
                                    get: { selectedWeekdays.contains(weekdayNumber) },
                                    set: { _ in toggleWeekday(weekdayNumber) }
                                ))
                                .toggleStyle(.checkbox)
                                Spacer(minLength: 0)
                            }
                        }

                        HStack(spacing: 12) {
                            Spacer(minLength: 202)
                            DatePicker("", selection: cleanupScheduleTimeBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .datePickerStyle(.stepperField)
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
```

- [ ] **Step 3: Hilfsfunktionen `selectedWeekdays`/`toggleWeekday(_:)` ergänzen**

Direkt vor der bestehenden `private var cleanupScheduleTimeBinding: Binding<Date>`-Property
ergänzen:

```swift
    private var selectedWeekdays: Set<Int> {
        CleanupScheduleSettings.parseWeekdays(cleanupWeekdaysRaw)
    }

    private func toggleWeekday(_ weekday: Int) {
        var current = selectedWeekdays
        if current.contains(weekday) {
            guard current.count > 1 else {
                return // Mindestens ein Tag muss ausgewählt bleiben.
            }
            current.remove(weekday)
        } else {
            current.insert(weekday)
        }
        cleanupWeekdaysRaw = CleanupScheduleSettings.formatWeekdays(current)
    }

```

- [ ] **Step 4: Build verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED` — keine Referenz auf `cleanupWeekday`/`weekdayKey`/
`defaultWeekday` mehr im Projekt.

- [ ] **Step 5: Repo-weite Grep-Prüfung, dass keine alte Referenz übrig bleibt**

Run: `grep -rn "CleanupScheduleSettings.weekdayKey\|CleanupScheduleSettings.defaultWeekday\b\|cleanupWeekday\b" Feedivo FeedivoTests`
Expected: Keine Treffer (leere Ausgabe). `defaultWeekdaysStored`/`defaultWeekdays` (mit
Suffix) sind KEINE Treffer für dieses Muster und bleiben bestehen — das Muster zielt
gezielt auf den alten Einzel-Wochentag-Namen ohne Suffix.

- [ ] **Step 6: Gezielte Tests erneut laufen lassen (Regressionscheck)**

Run: `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CleanupScheduleSettingsTests`
Expected: PASS (unverändert gegenüber Task 1, reine Bestätigung nach dem UI-Umbau).

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Views/Settings/SettingsView.swift
git commit -m "Feature: Zeitplan-Einstellungen erlauben Mehrfachauswahl von Wochentagen (Checkboxen)"
```

---

## Abschließende manuelle Live-Verifikation (nicht automatisierbar)

Nach Abschluss beider Tasks:

1. Einstellungen → Alte Artikel → "An einem bestimmten Wochentag" aktivieren — Sonntag
   ist als einziger Haken vorausgewählt.
2. Montag zusätzlich anhaken — beide Häkchen (Sonntag + Montag) bleiben sichtbar
   gesetzt, Uhrzeit bleibt unverändert für beide.
3. Sonntag wieder abwählen, dann versuchen, auch Montag (den letzten verbleibenden
   Haken) abzuwählen — der letzte Haken lässt sich nicht entfernen.
4. Einstellungen schließen und wieder öffnen — die Mehrfachauswahl bleibt erhalten.
