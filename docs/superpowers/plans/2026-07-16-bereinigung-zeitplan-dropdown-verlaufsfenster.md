# Zeitplan-Dropdown + Verlaufsfenster Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die drei Zeitplan-Toggle-Zeilen zu einem Mehrfachauswahl-Dropdown-Menü
zusammenfassen und den Bereinigungsverlauf aus den Settings in ein eigenes Fenster
verlagern (2. Nachtrag zu Feature 17.3a).

**Architecture:** `CleanupSettingsView` verliert die drei `SettingRow`-Toggles zugunsten
eines `Menu`-Buttons mit Mehrfachauswahl sowie die eingebettete History-Liste zugunsten
eines Buttons, der eine neue `CleanupHistoryWindowView` per `openWindow(id:)` öffnet
(neue `Window`-Scene in `FeedivoApp.swift`, analog zum bestehenden Statistik-Fenster).
Die History-Rendering-Logik wird 1:1 dorthin verschoben, nicht dupliziert.

**Tech Stack:** Swift, SwiftUI.

## Global Constraints

- Kommentare im Code auf Deutsch.
- Direktes Committen auf `main` (kein Feature-Branch/Worktree).
- `xcodebuild build` muss grün sein.
- Neue `L10n.swift`-Keys ohne direktes String-Literal erzeugen keinen automatischen
  xcstrings-Stub — alle 4 neuen Keys manuell per gezieltem `Edit` (kein
  `json.dump`-Rewrite) in allen 4 Sprachen (de/en/fr/it) ergänzen.
- Keine neuen automatisierten Tests nötig (reiner UI-Umbau ohne neue fachliche Logik).
- Feature 17.3a ist noch nicht gepusht — keine Abwärtskompatibilität zu wahren.

---

### Task 1: Dropdown-Menü + Verlaufsfenster

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (`CleanupSettingsView`)
- Create: `Feedivo/Views/Settings/CleanupHistoryWindowView.swift`
- Modify: `Feedivo/App/FeedivoApp.swift`
- Modify: `Feedivo/Resources/L10n.swift`
- Modify: `Feedivo/Resources/Localizable.xcstrings`

**Interfaces:**
- Produces: `CleanupHistoryWindowView.windowID = "cleanup-history-window"` (String),
  konsumiert von `FeedivoApp.swift`s neuer `Window`-Scene und von
  `CleanupSettingsView`s neuem `openWindow(id:)`-Aufruf.

- [ ] **Step 1: Neue L10n-Keys ergänzen**

In `Feedivo/Resources/L10n.swift`, direkt nach Zeile 416
(`static let settingsCleanupScheduleOnQuitDescription = LocalizedStringKey("settings.cleanupSchedule.onQuit.description")`)
und vor Zeile 417 (`static let cleanupHistoryTitle = ...`):

```swift
    static let settingsCleanupScheduleTitle = LocalizedStringKey("settings.cleanupSchedule.title")
    static let settingsCleanupScheduleDescription = LocalizedStringKey("settings.cleanupSchedule.description")
    static let settingsCleanupScheduleNoneSelected = LocalizedStringKey("settings.cleanupSchedule.noneSelected")
    static let settingsCleanupHistoryShowButton = LocalizedStringKey("settings.cleanupHistory.showButton")
```

- [ ] **Step 2: `Localizable.xcstrings`-Einträge ergänzen**

Per **Edit-Tool** (kein `json.dump`-Rewrite) direkt nach dem Ende des Eintrags
`"settings.cleanupSchedule.onQuit.title"` einfügen. Anker (exakter bestehender Text):

```
        }
      }
    },
    "settings.cleanupSchedule.weekdayTime.description" : {
```

Ersetzen durch:

```
        }
      }
    },
    "settings.cleanupHistory.showButton" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Anzeigen…"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Show…"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Afficher…"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Mostra…"
          }
        }
      }
    },
    "settings.cleanupSchedule.description" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Wählt aus, wann die Bereinigung automatisch ausgeführt wird."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Choose when cleanup runs automatically."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Choisissez quand le nettoyage s'exécute automatiquement."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Scegli quando la pulizia viene eseguita automaticamente."
          }
        }
      }
    },
    "settings.cleanupSchedule.noneSelected" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Kein Auslöser ausgewählt"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "No trigger selected"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Aucun déclencheur sélectionné"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Nessun trigger selezionato"
          }
        }
      }
    },
    "settings.cleanupSchedule.title" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Auslöser"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Triggers"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Déclencheurs"
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Trigger"
          }
        }
      }
    },
    "settings.cleanupSchedule.weekdayTime.description" : {
```

Nach dem Einfügen: `grep -c "settings.cleanupSchedule.title\|settings.cleanupHistory.showButton" Feedivo/Resources/Localizable.xcstrings` muss `2` liefern.

- [ ] **Step 3: `CleanupHistoryWindowView.swift` anlegen**

Neue Datei `Feedivo/Views/Settings/CleanupHistoryWindowView.swift`:

```swift
import SwiftUI

// Eigenständiges Fenster für den Bereinigungsverlauf (Feature 17.3a, 2. Nachtrag) —
// löst die zuvor in den Einstellungen eingebettete History-Liste ab. Rendering-Logik
// 1:1 aus der bisherigen CleanupSettingsView übernommen.
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

    private func cleanupHistoryRow(_ run: CleanupRunRecord) -> some View {
        HStack {
            Text(run.executedAt.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.tertiary)
            Text(cleanupTriggerLabel(run.triggerSource))
                .foregroundStyle(.tertiary)
            Spacer()
            if run.succeeded {
                Text("\(run.deletedCount)")
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text(run.errorMessage ?? "")
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 9)
        .frame(minHeight: 26)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func cleanupTriggerLabel(_ rawValue: String) -> LocalizedStringKey {
        switch CleanupRunTrigger(rawValue: rawValue) {
        case .manual, nil:
            L10n.cleanupHistoryTriggerManual
        case .appStart:
            L10n.cleanupHistoryTriggerAppStart
        case .schedule:
            L10n.cleanupHistoryTriggerSchedule
        case .onQuit:
            L10n.cleanupHistoryTriggerOnQuit
        case .settingsChange:
            L10n.cleanupHistoryTriggerSettingsChange
        }
    }

    private func loadCleanupHistory() {
        guard let feedivoDatabase else {
            cleanupHistory = []
            return
        }
        cleanupHistory = (try? CleanupRunHistoryStore(database: feedivoDatabase).recentRuns()) ?? []
    }
}
```

- [ ] **Step 4: `FeedivoApp.swift` — neue `Window`-Scene ergänzen**

In `Feedivo/App/FeedivoApp.swift`, direkt nach dem bestehenden Statistik-Fenster-Block
(Zeile 161-170):

```swift
        Window(L10n.statisticsWindowTitle, id: StatisticsWindowView.windowID) {
            StatisticsWindowView()
                .environment(\.locale, appLanguage.locale)
                .environment(\.interfaceTextSize, interfaceTextSize)
                .environment(\.feedivoDatabase, feedivoDatabase)
                .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .defaultSize(width: 820, height: 640)
        .defaultSize(width: 920, height: 620)
```

direkt danach ergänzen:

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

- [ ] **Step 5: `CleanupSettingsView` — Dropdown-Menü statt drei Toggle-Zeilen**

In `Feedivo/Views/Settings/SettingsView.swift`, den bestehenden `Zeitplan`-Block
(die drei `SettingRow`-Toggles für App-Start, Wochentag, App-Beenden) ersetzen. Der
bedingte Wochentag/Uhrzeit-Block bleibt unverändert erhalten. Ersetze:

```swift
                SettingRow(
                    title: L10n.settingsCleanupScheduleAppStartTitle,
                    description: L10n.settingsCleanupScheduleAppStartDescription
                ) {
                    Toggle("", isOn: $cleanupRunOnAppStart)
                        .labelsHidden()
                }

                SettingRow(
                    title: L10n.settingsCleanupScheduleWeekdayTimeTitle,
                    description: L10n.settingsCleanupScheduleWeekdayTimeDescription
                ) {
                    Toggle("", isOn: $cleanupRunOnWeekdayTime)
                        .labelsHidden()
                }
```

durch:

```swift
                SettingRow(
                    title: L10n.settingsCleanupScheduleTitle,
                    description: L10n.settingsCleanupScheduleDescription
                ) {
                    Menu {
                        Toggle(L10n.settingsCleanupScheduleAppStartTitle, isOn: $cleanupRunOnAppStart)
                        Toggle(L10n.settingsCleanupScheduleWeekdayTimeTitle, isOn: $cleanupRunOnWeekdayTime)
                        Toggle(L10n.settingsCleanupScheduleOnQuitTitle, isOn: $cleanupRunOnQuit)
                    } label: {
                        Text(cleanupScheduleSummaryText)
                    }
                    .menuActionDismissBehavior(.disabled)
                }
```

und die bestehende, jetzt separate dritte `SettingRow` für "Beim Beenden der App"
entfernen:

```swift
                SettingRow(
                    title: L10n.settingsCleanupScheduleOnQuitTitle,
                    description: L10n.settingsCleanupScheduleOnQuitDescription
                ) {
                    Toggle("", isOn: $cleanupRunOnQuit)
                        .labelsHidden()
                }
```

(ersatzlos entfernen — die Option ist jetzt Teil des Menüs oben).

- [ ] **Step 6: `CleanupSettingsView` — History-Block durch Button ersetzen**

Den kompletten bestehenden Block

```swift
            SettingsBlock(eyebrow: L10n.cleanupHistoryTitle) {
                Text(L10n.cleanupHistoryDescription)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                if cleanupHistory.isEmpty {
                    Text(L10n.cleanupHistoryEmpty)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                } else {
                    VStack(spacing: 5) {
                        ForEach(cleanupHistory, id: \.id) { run in
                            cleanupHistoryRow(run)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .onAppear(perform: loadCleanupHistory)
        .onChange(of: sqliteStatusVersionForCleanupHistory) {
            loadCleanupHistory()
        }
    }
```

ersetzen durch:

```swift
            SettingsBlock(eyebrow: L10n.cleanupHistoryTitle) {
                SettingRow(
                    title: L10n.cleanupHistoryTitle,
                    description: L10n.cleanupHistoryDescription
                ) {
                    Button(L10n.settingsCleanupHistoryShowButton) {
                        openWindow(id: CleanupHistoryWindowView.windowID)
                    }
                }
            }
        }
    }
```

- [ ] **Step 7: `CleanupSettingsView` — nicht mehr benötigte Properties/Funktionen entfernen, neue ergänzen**

Die `@AppStorage(SQLiteDataInvalidation.statusVersionKey) private var
sqliteStatusVersionForCleanupHistory = 0` sowie `@State private var cleanupHistory:
[CleanupRunRecord] = []` (jetzt nur noch in `CleanupHistoryWindowView` gebraucht)
entfernen. Direkt darunter (wo bisher `@State private var cleanupHistory` stand)
ergänzen:

```swift
    @Environment(\.openWindow) private var openWindow
```

Die Funktionen `cleanupHistoryRow(_:)`, `cleanupTriggerLabel(_:)` und
`loadCleanupHistory()` komplett aus `CleanupSettingsView` entfernen (1:1 nach
`CleanupHistoryWindowView` verschoben, siehe Step 3 — nicht duplizieren).

Neue Computed Property `cleanupScheduleSummaryText` direkt vor
`cleanupScheduleTimeBinding` ergänzen:

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

- [ ] **Step 8: Build verifizieren**

Run: `xcodebuild build -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 9: Repo-weite Grep-Prüfung**

Run: `grep -rn "cleanupHistoryRow\|cleanupTriggerLabel\|loadCleanupHistory" Feedivo/Views/Settings/SettingsView.swift`
Expected: Keine Treffer mehr in `SettingsView.swift` (alle drei Funktionen jetzt
ausschließlich in `CleanupHistoryWindowView.swift`).

- [ ] **Step 10: Commit**

```bash
git add Feedivo/Views/Settings/SettingsView.swift \
  Feedivo/Views/Settings/CleanupHistoryWindowView.swift \
  Feedivo/App/FeedivoApp.swift \
  Feedivo/Resources/L10n.swift \
  Feedivo/Resources/Localizable.xcstrings
git commit -m "Feature: Zeitplan als Mehrfachauswahl-Dropdown + Bereinigungsverlauf als eigenes Fenster"
```

---

## Abschließende manuelle Live-Verifikation (nicht automatisierbar)

1. Einstellungen → Alte Artikel → Zeitplan-Menü öffnen — alle 3 Optionen mit Häkchen
   sichtbar, Menü bleibt beim Anklicken einer Option offen.
2. Mehrere Optionen anhaken — Button-Beschriftung zeigt alle ausgeschriebenen Namen
   kommagetrennt.
3. "Wochentage" anhaken — Checkbox-Zeilen + Uhrzeit erscheinen wie zuvor darunter.
4. "Anzeigen…"-Button beim Bereinigungsverlauf klicken — neues Fenster öffnet sich mit
   der History-Liste.
