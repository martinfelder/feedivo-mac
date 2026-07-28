# Design: Zeitplan — Mehrere Wochentage statt nur einem (Nachtrag zu Feature 17.3a)

**Datum:** 2026-07-16
**Status:** Zur Review

## Kontext

Feature 17.3a ("Bereinigung — History, Zeitplan und Hinweis") ist bereits vollständig
implementiert, reviewed und lokal auf `main` committed (noch nicht gepusht). Der
Zeitplan-Auslöser "An einem bestimmten Wochentag" erlaubt aktuell nur **einen** Wochentag
(`CleanupScheduleSettings.weekdayKey`, einzelner `Int` 1...7) plus eine gemeinsame
Uhrzeit, dargestellt über einen einzelnen Menü-`Picker` in `CleanupSettingsView`.

Nutzerwunsch: Mehrere Wochentage gleichzeitig auswählbar machen (z. B. Montag UND
Donnerstag), weiterhin mit einer gemeinsamen Uhrzeit für alle gewählten Tage, dargestellt
als Checkbox-Zeilen statt eines Einzel-Pickers.

Da das gesamte Feature noch nicht gepusht ist, gibt es keine Altlasten/Migration zu
berücksichtigen — der bestehende `weekdayKey`/`defaultWeekday` wird direkt ersetzt, nicht
parallel weitergeführt.

## Ziele

1. Mehrfachauswahl von Wochentagen statt genau einem.
2. Mindestens ein Wochentag muss immer ausgewählt bleiben, solange der Zeitplan-Schalter
   aktiv ist — der letzte verbleibende Haken lässt sich nicht abwählen.
3. Standardauswahl beim ersten Aktivieren: Sonntag (unverändert gegenüber dem bisherigen
   Einzel-Default).
4. UI: 7 einzelne Checkbox-Zeilen (ein Haken pro Wochentag) statt eines Pickers,
   weiterhin gefolgt von der gemeinsamen Uhrzeit-Auswahl.
5. Nachhol-Prüfung erkennt eine Bereinigung als fällig, sobald **irgend ein** gewählter
   Wochentag+Uhrzeit-Kombination seit dem letzten Zeitplan-Lauf verstrichen ist — bei
   zwei gewählten Tagen läuft die Bereinigung entsprechend zweimal pro Woche.

## Nicht-Ziele

- Keine unterschiedlichen Uhrzeiten pro Wochentag — weiterhin eine gemeinsame Uhrzeit für
  alle gewählten Tage.
- Keine Migration von bestehenden `weekdayKey`-Werten — das Feature ist noch nicht
  gepusht, der alte Key wird ersatzlos durch den neuen ersetzt.

## Datenmodell

`Feedivo/Services/CleanupScheduleSettings.swift`: `weekdayKey`/`defaultWeekday` (Int)
entfällt, ersetzt durch:

```swift
static let weekdaysKey = "cleanupSchedule.weekdays"  // kommagetrennt, z. B. "1,3,5"; Calendar.weekday (1 = Sonntag)
static let defaultWeekdaysStored = "1"               // Rohwert für @AppStorage-Initialwert in der UI
static let defaultWeekdays: Set<Int> = [1]

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
```

Kommagetrennter String statt JSON-Blob oder Bitmaske — passt zum bestehenden Stil des
Projekts (einfache, für Menschen lesbare `UserDefaults`-Werte), keine zusätzliche
`Codable`-Infrastruktur für einen so kleinen Wert nötig.

## Nachhol-Prüfung (mehrere Tage, eine Uhrzeit)

`isWeekdayTimeScheduleDue` berechnet weiterhin pro Wochentag den zuletzt fälligen
Zeitpunkt über die unveränderte private `mostRecentOccurrence(weekday:timeMinutes:
atOrBefore:calendar:)`-Funktion, jetzt aber für **jeden** gewählten Wochentag, und nimmt
davon das Maximum:

```swift
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
```

`selectedWeekdays` ist durch die erzwungene Mindestauswahl (siehe UI-Abschnitt) nie leer,
der `?? .distantPast`-Fallback ist reine Verteidigung gegen einen theoretisch leeren Wert
(z. B. korrupte `UserDefaults`), nicht der Normalfall.

Da `recordScheduleRun` weiterhin einen einzelnen `lastScheduleRunAtKey`-Zeitstempel setzt
(unverändert aus der bestehenden Implementierung), braucht es keinen Zeitstempel pro
Wochentag: Läuft die Bereinigung am Montag, wird `lastScheduleRunAtKey` auf "jetzt"
gesetzt; am Donnerstag ist deren `mostRecentOccurrence` (diese Woche, Donnerstag) neuer
als der Montags-Zeitstempel, die Bereinigung läuft also erneut — das ergibt das
gewünschte "läuft an jedem gewählten Tag" ohne zusätzliche Zustandsverwaltung.

## UI

`Feedivo/Views/Settings/SettingsView.swift`, `CleanupSettingsView`: Der bisherige
`Picker`-Aufruf für `cleanupWeekday` wird ersetzt durch eine `@AppStorage`-Property auf
dem rohen String (`cleanupWeekdaysRaw`) plus 7 Checkbox-Zeilen:

```swift
@AppStorage(CleanupScheduleSettings.weekdaysKey)
private var cleanupWeekdaysRaw = CleanupScheduleSettings.defaultWeekdaysStored
```

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

Neue Hilfsfunktionen in `CleanupSettingsView`:

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

`.toggleStyle(.checkbox)` ist SwiftUI-macOS-nativ (rendert als echtes `NSButton`-Checkbox,
kein selbstgebautes Symbol) und passt zum "Checkmarks"-Wunsch des Nutzers.

## Tests

`FeedivoTests/CleanupScheduleSettingsTests.swift`: bestehende Tests, die `weekdayKey`
setzen, werden auf `weekdaysKey`/kommagetrennten String umgestellt (z. B.
`defaults.set("\(todayWeekday)", forKey: CleanupScheduleSettings.weekdaysKey)` statt
`defaults.set(todayWeekday, forKey: CleanupScheduleSettings.weekdayKey)`). Neue Tests:

- `parseWeekdaysLiestKommagetrennteWerte`: `"1,3,5"` → `[1, 3, 5]`.
- `parseWeekdaysLiefertDefaultBeiLeeremString`: `""` → `[1]`.
- `formatWeekdaysSortiertUndVerbindet`: `[5, 1, 3]` → `"1,3,5"`.
- `isWeekdayTimeScheduleDueLiefertTrueWennEinerVonMehrerenTagenFaelligIst`: zwei gewählte
  Wochentage, nur einer davon aktuell fällig — Ergebnis `true`.
- `isWeekdayTimeScheduleDueLiefertFalseWennKeinerDerMehrerenTageFaelligIst`: zwei gewählte
  Wochentage, `lastScheduleRunAt` liegt nach beiden zuletzt fälligen Zeitpunkten —
  Ergebnis `false`.

Kein UI-Test für die Checkbox-Zeilen nötig (dieses Projekt hat keine SwiftUI-View-Tests,
konsistent mit dem restlichen Feature 17.3a — nur die zugrundeliegende Logik wird
getestet).

## Risiken / offene Punkte

- Keine — reiner, in sich geschlossener Umbau eines noch nicht gepushten Features, keine
  Abwärtskompatibilität zu wahren.
