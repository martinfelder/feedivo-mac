# Design: Zeitplan-Dropdown + eigenes Verlaufsfenster (2. Nachtrag zu Feature 17.3a)

**Datum:** 2026-07-16
**Status:** Zur Review

## Kontext

Weiterer Nachtrag zu Feature 17.3a, nach dem bereits umgesetzten Mehrfach-Wochentag-
Nachtrag. Aktuell (`CleanupSettingsView` in `Feedivo/Views/Settings/SettingsView.swift`):
drei unabhängige Toggle-`SettingRow`s ("Bei App-Start", "An einem bestimmten Wochentag",
"Beim Beenden der App") im "Zeitplan"-Block, plus eine eingebettete History-Liste als
eigener `SettingsBlock` darunter.

Nutzerwunsch: Die drei Toggle-Zeilen zu einem Dropdown-Menü zusammenfassen (Mehrfach-
auswahl bleibt erhalten); die History-Liste durch einen Button ersetzen, der ein eigenes
Fenster öffnet.

## Ziele

1. Ein einzelner `Menu`-Button ersetzt die drei Toggle-`SettingRow`s. Geöffnet zeigt er
   die drei Optionen mit Häkchen, bleibt beim Anklicken offen (Mehrfachauswahl bleibt
   möglich — keine Verhaltensänderung, nur Darstellung). Geschlossen zeigt der Button die
   ausgeschriebenen Namen der aktiven Auslöser, kommagetrennt.
2. Ist "Wochentage" darin angehakt, erscheinen die bestehenden 7 Checkbox-Zeilen +
   Uhrzeit-Picker unverändert darunter.
3. Die eingebettete History-Liste entfällt aus den Settings, ersetzt durch einen Button
   ("Bereinigungsverlauf anzeigen"), der ein neues, eigenständiges Fenster öffnet — 1:1
   dieselbe Darstellung wie bisher (letzte 10 Einträge, gleiche Zeilendarstellung).

## Nicht-Ziele

- Keine Änderung an `CleanupScheduleSettings` (Datenschicht bleibt unverändert — reiner
  UI-Umbau).
- Keine Erweiterung der History über 10 Einträge hinaus.
- Keine Änderung an der Mehrfachauswahl-*Logik* der drei Auslöser — nur an der
  Darstellung.

## Zeitplan-Dropdown

UI-Ersatz für die drei bisherigen `SettingRow`-Toggle-Zeilen:

```swift
SettingRow(
    title: L10n.settingsCleanupScheduleTitle, // neuer Key: "Auslöser" / "Triggers" / "Déclencheurs" / "Trigger"
    description: L10n.settingsCleanupScheduleDescription // neuer Key, zusammenfassender Hinweistext
) {
    Menu {
        Toggle(L10n.settingsCleanupScheduleAppStartTitle, isOn: $cleanupRunOnAppStart)
        Toggle(L10n.settingsCleanupScheduleWeekdayTimeTitle, isOn: $cleanupRunOnWeekdayTime)
        Toggle(L10n.settingsCleanupScheduleOnQuitTitle, isOn: $cleanupRunOnQuit)
    } label: {
        Text(cleanupScheduleSummaryText)
    }
    .menuActionDismissBehavior(.disabled) // Menü bleibt für Mehrfachauswahl offen (macOS 14+)
}
```

Da sich `LocalizedStringKey`-Werte nicht sauber zur Laufzeit verketten lassen, wird die
Zusammenfassung als reiner `String` gebaut — über `String(localized:)` auf die bereits
vorhandenen xcstrings-Rohwerte der drei Titel-Keys (Task 6 des Basis-Features, unverändert
bestehend, nur jetzt zusätzlich als Menü-Item-Label statt Zeilentitel genutzt):

```swift
private var cleanupScheduleSummaryText: String {
    var parts: [String] = []
    if cleanupRunOnAppStart {
        parts.append(String(localized: "settings.cleanupSchedule.appStart.title"))
    }
    if cleanupRunOnWeekdayTime {
        parts.append(String(localized: "settings.cleanupSchedule.weekdayTime.title"))
    }
    if cleanupRunOnQuit {
        parts.append(String(localized: "settings.cleanupSchedule.onQuit.title"))
    }
    guard !parts.isEmpty else {
        return String(localized: "settings.cleanupSchedule.noneSelected")
    }
    return parts.joined(separator: ", ")
}
```

Der bestehende, an `cleanupRunOnWeekdayTime` gebundene bedingte Block (7 Checkbox-Zeilen
+ Uhrzeit) bleibt unverändert direkt darunter erhalten — der Menü-Umbau betrifft nur die
Auswahl-Darstellung selbst, nicht die Wochentags-Unterzeile.

## Bereinigungsverlauf als eigenes Fenster

Neue Datei `Feedivo/Views/Settings/CleanupHistoryWindowView.swift`, nach dem Muster von
`OrganizerWindowView.swift`/`StatisticsWindowView.swift` (`static let windowID`, Sprache/
Textgröße/Darstellung werden wie bei diesen bestehenden Fenstern per `.environment(...)`
von `FeedivoApp.swift` injiziert):

```swift
import SwiftUI

struct CleanupHistoryWindowView: View {
    static let windowID = "cleanup-history-window"

    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersionForCleanupHistory = 0

    @State private var cleanupHistory: [CleanupRunRecord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.cleanupHistoryDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if cleanupHistory.isEmpty {
                Text(L10n.cleanupHistoryEmpty)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 5) {
                    ForEach(cleanupHistory, id: \.id) { run in
                        cleanupHistoryRow(run)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .onAppear(perform: loadCleanupHistory)
        .onChange(of: sqliteStatusVersionForCleanupHistory) {
            loadCleanupHistory()
        }
    }

    // cleanupHistoryRow(_:) und cleanupTriggerLabel(_:) 1:1 aus CleanupSettingsView
    // hierher verschoben (identischer Code, siehe bestehende Implementierung dort).
    // loadCleanupHistory() ebenfalls 1:1 verschoben.
}
```

`FeedivoApp.swift` bekommt eine neue `Window`-Scene (analog zum bestehenden Statistik-
Fenster):

```swift
Window(L10n.cleanupHistoryTitle, id: CleanupHistoryWindowView.windowID) {
    CleanupHistoryWindowView()
        .environment(\.locale, appLanguage.locale)
        .environment(\.interfaceTextSize, interfaceTextSize)
        .environment(\.feedivoDatabase, feedivoDatabase)
        .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
        .preferredColorScheme(appAppearance.colorScheme)
}
.defaultSize(width: 420, height: 480)
```

`CleanupSettingsView` verliert `cleanupHistoryRow`/`cleanupTriggerLabel`/
`loadCleanupHistory`/den `cleanupHistory`-State/die `sqliteStatusVersionForCleanupHistory`-
AppStorage (alle 1:1 nach `CleanupHistoryWindowView` verschoben) sowie den gesamten
`SettingsBlock(eyebrow: L10n.cleanupHistoryTitle)`-Block. Ersetzt durch:

```swift
@Environment(\.openWindow) private var openWindow
```

```swift
SettingRow(
    title: L10n.cleanupHistoryTitle,
    description: L10n.cleanupHistoryDescription
) {
    Button(L10n.settingsCleanupHistoryShowButton) { // neuer Key: "Anzeigen…" / "Show…" / "Afficher…" / "Mostra…"
        openWindow(id: CleanupHistoryWindowView.windowID)
    }
}
```

## Neue L10n-Keys

- `settings.cleanupSchedule.title` ("Auslöser" / "Triggers" / "Déclencheurs" / "Trigger")
- `settings.cleanupSchedule.description` (zusammenfassender Hinweistext für die neue
  Dropdown-Zeile; die drei bisherigen Titel-Keys bleiben bestehen, dienen jetzt als
  Menü-Item-Label statt als Zeilentitel — ihre bisherigen Beschreibungs-Keys
  (`*.description`) werden nicht mehr angezeigt und bleiben als verwaiste, aber harmlose
  Katalogeinträge zurück, analog zum bereits dokumentierten Umgang mit den
  `settingsAutomaticCleanup*`-Keys aus dem Basis-Feature)
- `settings.cleanupSchedule.noneSelected` ("Kein Auslöser ausgewählt" / "No trigger
  selected" / "Aucun déclencheur sélectionné" / "Nessun trigger selezionato")
- `settings.cleanupHistory.showButton` ("Anzeigen…" / "Show…" / "Afficher…" / "Mostra…")

Wie gehabt: neue Keys nach Implementierung per `grep -c` gegen `Localizable.xcstrings`
prüfen (kein automatischer Stub für indirekt referenzierte Keys).

## Tests

Keine neuen automatisierten Tests — reiner UI-Umbau ohne neue fachliche Logik (die
Zusammenfassungs-Funktion `cleanupScheduleSummaryText` ist eine private View-Property mit
reiner String-Verkettung ohne eigenständig testbare Semantik, konsistent mit dem übrigen
UI-only-Charakter dieses Nachtrags). Build-Grün-Verifikation genügt.

## Risiken / offene Punkte

- Keine — reiner UI-Umbau eines noch nicht gepushten Features, keine
  Abwärtskompatibilität zu wahren.
