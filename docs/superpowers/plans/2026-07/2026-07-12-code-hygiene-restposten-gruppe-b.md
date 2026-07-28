# Restposten Gruppe B — Code-Hygiene ohne Verhaltensänderung Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vier unabhängige Aufräum-Punkte aus dem Code-Qualitäts-Review beheben —
drei unbenannte Fetch-Limits, zwei divergente Debounce-Implementierungen, ein
vestigiales `New`-Präfix an 17 Typen in `SettingsView.swift`, und toten Code
(`RuleViewModel`) entfernen. Keiner dieser vier Punkte ändert beobachtbares
App-Verhalten.

**Architecture:** Task 1 und 2 extrahieren Magic Numbers/duplizierte Logik in
neue, kleine `Feedivo/Extensions/`-Dateien (nach dem in Gruppe A etablierten
Muster von `SilentErrorLogging.swift`). Task 3 ist ein reiner Identifier-Rename
innerhalb einer Datei plus zwei externer Anpassungsstellen. Task 4 ist eine
reine Löschung. Tasks 1+2 sind unabhängig von 3+4 und können in beliebiger
Reihenfolge laufen; 3 und 4 sind ebenfalls gegenseitig unabhängig.

**Tech Stack:** SwiftUI, GRDB (SQLite), Swift Testing (`@testable import
Feedivo`).

## Global Constraints

- Arbeitsweise für diese Gruppe: Commits direkt auf `main` (Nutzerentscheid,
  konsistent mit Gruppe A und allen vorherigen Gruppen dieser Session).
- Kommentare im Code auf Deutsch (Projektkonvention laut CLAUDE.md).
- Volle Testsuite hängt (CLAUDE.md-Gotcha) — immer gezielt mit
  `-only-testing:FeedivoTests/<SuiteName> -parallel-testing-enabled NO`
  testen.
- SourceKit/IDE-Diagnosen sind in diesem Projekt häufig veraltet/falsch
  (CLAUDE.md-Gotcha: z. B. "No such module 'GRDB'", "Cannot find type X in
  scope" für unveränderte, korrekte Symbole) — verlässlich ist ausschließlich
  ein echter `xcodebuild build`-Lauf.
- SwiftUI-View-Structs sind in diesem Projekt nicht direkt unit-testbar
  (private Methoden, kein UI-Test-Harness) — Tasks 3 und 4 werden daher nur
  über einen echten `xcodebuild build`-Lauf plus gezielte Regressionstests
  verifiziert, keine neuen Unit-Tests.
- `FeedivoAppSceneConfigurationTests` (betroffen in Task 3 und 4) hat laut
  CLAUDE.md 9 bekannte, vorbestehende, von dieser Arbeit unabhängige
  Testfehlschläge (u. a. `sqliteReaderBleibtOptischNahAnMainReaderToolbar`)
  — diese NICHT mit einer durch diese Gruppe verursachten Regression
  verwechseln. Die für Task 3/4 jeweils namentlich genannten Tests müssen
  grün sein; die 9 bekannten Fehlschläge bleiben bestehen.

---

### Task 1: Finding 2.7 — Benannte Konstanten für drei Fetch-Limits

**Files:**
- Create: `Feedivo/Extensions/ArticleFetchLimits.swift`
- Modify: `Feedivo/ViewModels/SQLiteFeedArticleListState.swift:395`
- Modify: `Feedivo/Views/Reader/ArticleWindowView.swift:159`
- Modify: `Feedivo/Views/ArticleList/ArticleSearchWindowView.swift:357`

**Interfaces:**
- Produces: `ArticleFetchLimits.mainArticleList: Int` (= 500),
  `ArticleFetchLimits.popoutNavigationIDs: Int` (= 1000),
  `ArticleFetchLimits.searchResults: Int` (= 200) — drei separate,
  einzeln dokumentierte Konstanten, KEINE gemeinsame Konstante (die drei
  Anwendungsfälle sind bewusst unterschiedlich groß).

- [ ] **Step 1: Neue Konstanten-Datei anlegen**

Neue Datei `Feedivo/Extensions/ArticleFetchLimits.swift`:

```swift
import Foundation

/// Zentrale, einzeln dokumentierte Obergrenzen für die drei unterschiedlichen
/// "Artikel laden"-Anwendungsfälle der App. Bewusst DREI separate Werte statt
/// einer gemeinsamen Konstante — die Anwendungsfälle sind unterschiedlich
/// genug (volle Snapshots vs. reine IDs, Haupt-Liste vs. Suche), dass ein
/// gemeinsamer Wert die falsche Kopplung suggerieren würde.
enum ArticleFetchLimits {
    /// Haupt-Timeline-Load der 3-Spalten-Artikelliste
    /// (`SQLiteFeedArticleListState.defaultTimelineLoader`).
    static let mainArticleList = 500

    /// Artikel-Popout-Fenster: lädt NUR Artikel-IDs (nicht die vollen
    /// Snapshots) für die Vor-/Zurück-Navigation über alle Artikel hinweg
    /// (`scope: .all`) — bewusst höher als `mainArticleList`, weil hier nur
    /// IDs statt kompletter Inhalte geladen werden.
    static let popoutNavigationIDs = 1000

    /// Obergrenze für angezeigte Ergebnisse im separaten Artikel-Suchfenster.
    static let searchResults = 200
}
```

- [ ] **Step 2: `SQLiteFeedArticleListState.swift:395` umstellen**

Vorher:
```swift
        let rows = try articleDatabase.timelineArticles(
            scope: timelineScope,
            searchText: request.searchText,
            includeRead: true,
            includeHidden: request.scope.includeHidden,
            limit: 500
        )
```

Nachher:
```swift
        let rows = try articleDatabase.timelineArticles(
            scope: timelineScope,
            searchText: request.searchText,
            includeRead: true,
            includeHidden: request.scope.includeHidden,
            limit: ArticleFetchLimits.mainArticleList
        )
```

- [ ] **Step 3: `ArticleWindowView.swift:159` umstellen**

Vorher:
```swift
            articleIDs = try TimelineStore(database: database).articles(
                scope: .all,
                includeRead: true,
                includeHidden: true,
                limit: 1000
            )
            .map(\.id)
```

Nachher:
```swift
            articleIDs = try TimelineStore(database: database).articles(
                scope: .all,
                includeRead: true,
                includeHidden: true,
                limit: ArticleFetchLimits.popoutNavigationIDs
            )
            .map(\.id)
```

- [ ] **Step 4: `ArticleSearchWindowView.swift:357` umstellen**

Vorher:
```swift
            snapshots = try ArticleStore(database: database).searchArticles(
                state: committedState,
                limit: 200
            )
```

Nachher:
```swift
            snapshots = try ArticleStore(database: database).searchArticles(
                state: committedState,
                limit: ArticleFetchLimits.searchResults
            )
```

- [ ] **Step 5: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Bestehende Regressionstests laufen lassen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests -parallel-testing-enabled NO`
Expected: Alle Tests weiterhin grün (Werte identisch, nur symbolisch
benannt). `ArticleWindowView.swift` und `ArticleSearchWindowView.swift` haben
keine eigenen Testsuiten (SwiftUI-View-Dateien, siehe Global Constraints) —
dafür genügt der grüne Build.

Hinweis: `FeedivoTests/SQLiteLargeDatasetPerformanceTests.swift` enthält
ebenfalls zwei `limit: 500`-Literale, ruft dabei aber direkt
`TimelineStore(database:).articles(...)` auf — ein komplett unabhängiger
Code-Pfad, nicht Teil dieser Task, nicht anfassen.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Extensions/ArticleFetchLimits.swift Feedivo/ViewModels/SQLiteFeedArticleListState.swift Feedivo/Views/Reader/ArticleWindowView.swift Feedivo/Views/ArticleList/ArticleSearchWindowView.swift
git commit -m "Refactor: Drei unbenannte Fetch-Limits durch benannte ArticleFetchLimits-Konstanten ersetzt (Finding 2.7)"
```

---

### Task 2: Finding 2.9 — Gemeinsamer Debounce-Helfer

**Files:**
- Create: `Feedivo/Extensions/SearchDebounce.swift`
- Test: `FeedivoTests/SearchDebounceTests.swift`
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:862-874`
- Modify: `Feedivo/Views/ArticleList/ArticleSearchWindowView.swift:60-69`

**Interfaces:**
- Produces: `SearchDebounce.delayMilliseconds: Int` (= 250),
  `SearchDebounce.wait() async -> Bool` (wartet die konfigurierte
  Verzögerung ab; gibt `true` zurück, wenn die Wartezeit ungestört
  durchgelaufen ist, `false`, wenn der aufrufende `Task` währenddessen
  abgebrochen wurde).

- [ ] **Step 1: Fehlschlagende Tests schreiben**

Neue Datei `FeedivoTests/SearchDebounceTests.swift`:

```swift
import Testing
@testable import Feedivo

struct SearchDebounceTests {
    @Test func waitGibtTrueZurueckWennUngestoertDurchgelaufen() async {
        let result = await SearchDebounce.wait()

        #expect(result == true)
    }

    @Test func waitGibtFalseZurueckWennTaskAbgebrochenWird() async {
        let task = Task {
            await SearchDebounce.wait()
        }
        task.cancel()

        let result = await task.value

        #expect(result == false)
    }
}
```

- [ ] **Step 2: Tests laufen lassen, Fehlschlag bestätigen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SearchDebounceTests -parallel-testing-enabled NO`
Expected: BUILD FAILED — `SearchDebounce` existiert noch nicht.

- [ ] **Step 3: Minimale Implementierung schreiben**

Neue Datei `Feedivo/Extensions/SearchDebounce.swift`:

```swift
import Foundation

/// Gemeinsamer Debounce-Baustein für Suchfeld-Verzögerung (Artikelliste,
/// Suchfenster). Ersetzt zwei zuvor unabhängig implementierte
/// `Task.sleep`-Aufrufe mit identischer Verzögerung, aber unterschiedlicher
/// API (Millisekunden-`Duration` vs. rohe Nanosekunden).
enum SearchDebounce {
    /// Wartezeit, bis ein eingegebener Suchtext als "fertig getippt" gilt.
    static let delayMilliseconds = 250

    /// Wartet `delayMilliseconds` ab. Gibt `true` zurück, wenn die Wartezeit
    /// ungestört durchgelaufen ist, `false`, wenn der aufrufende `Task`
    /// währenddessen abgebrochen wurde (z. B. weil `.task(id:)` durch neue
    /// Texteingabe neu gestartet wurde).
    static func wait() async -> Bool {
        try? await Task.sleep(for: .milliseconds(delayMilliseconds))
        return !Task.isCancelled
    }
}
```

- [ ] **Step 4: Tests laufen lassen, Erfolg bestätigen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SearchDebounceTests -parallel-testing-enabled NO`
Expected: TEST SUCCEEDED — beide Tests grün.

- [ ] **Step 5: `SQLiteFeedArticleListView.swift:862-874` umstellen**

Vorher:
```swift
    private func updateDebouncedSearchText() async {
        if searchText.isEmpty {
            debouncedSearchText = ""
            return
        }

        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else {
            return
        }

        debouncedSearchText = searchText
    }
```

Nachher:
```swift
    private func updateDebouncedSearchText() async {
        if searchText.isEmpty {
            debouncedSearchText = ""
            return
        }

        guard await SearchDebounce.wait() else {
            return
        }

        debouncedSearchText = searchText
    }
```

- [ ] **Step 6: `ArticleSearchWindowView.swift:60-69` umstellen**

Vorher:
```swift
        .task(id: searchState.searchText) {
            if searchState.searchText.isEmpty {
                debouncedSearchText = ""
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            if !Task.isCancelled {
                debouncedSearchText = searchState.searchText
            }
        }
```

Nachher:
```swift
        .task(id: searchState.searchText) {
            if searchState.searchText.isEmpty {
                debouncedSearchText = ""
                return
            }
            guard await SearchDebounce.wait() else {
                return
            }
            debouncedSearchText = searchState.searchText
        }
```

- [ ] **Step 7: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Extensions/SearchDebounce.swift FeedivoTests/SearchDebounceTests.swift Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift Feedivo/Views/ArticleList/ArticleSearchWindowView.swift
git commit -m "Refactor: Gemeinsamer SearchDebounce-Helfer statt zwei divergenter Task.sleep-Implementierungen (Finding 2.9)"
```

---

### Task 3: Finding 2.8 — `New`-Präfix in SettingsView.swift entfernen

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift` (17 Typ-Umbenennungen)
- Modify: `Feedivo/App/FeedivoApp.swift:171`
- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift:35-48`

**Nutzerentscheidung (bereits eingeholt):** Typnamen umbenennen, der
persistierte `windowID`-String `"feedivo-settings-new"` bleibt UNVERÄNDERT
(kein Migrationsrisiko).

**⚠️ Kritischer Sonderfall — unbedingt beachten:** `NewSlider` (Zeile 662)
wird zu **`SettingsSlider`**, NICHT zu bloßem `Slider`. Der Typ nutzt in
seinem eigenen `body` (aktuell Zeile 669) den echten SwiftUI-`Slider(value:
in:)`. Würde man ihn auf `Slider` umbenennen, würde der Typ sich SELBST
überschatten — Swift löst den unqualifizierten Aufruf in der eigenen
`body`-Property dann auf den gerade deklarierten eigenen Typ auf statt auf
`SwiftUI.Slider`, was wegen der abweichenden Argument-Label
(`value:range:suffix:` vs. `value:in:`) zu einem Compile-Fehler führt.
Verifiziert: kein anderer Typname aus dieser Liste kollidiert mit einem
System- oder Projekt-Symbol.

**Interfaces:**
- Produces: `SettingsView` (Typname, ersetzt `NewSettingsView`) —
  `SettingsView.windowID` bleibt `"feedivo-settings-new"`. Alle 16 übrigen
  Typen sind `private` (file-scoped) und daher nur innerhalb von
  `SettingsView.swift` relevant.

- [ ] **Step 1: Die 17 Typen in `SettingsView.swift` umbenennen**

Für jedes der folgenden Paare: mit dem Edit-Tool `old_string` = alter
Bezeichner, `new_string` = neuer Bezeichner, `replace_all: true`, angewendet
auf `Feedivo/Views/Settings/SettingsView.swift`. Das ersetzt sowohl die
Typ-Deklaration als auch alle internen Aufrufstellen (z. B.
`NewSettingsBlock(eyebrow: ...) { ... }` an vielen Stellen im Datei-Body).
Reihenfolge ist unkritisch (keiner der alten Bezeichner ist Teilstring eines
anderen alten oder neuen Bezeichners in dieser Liste — verifiziert):

| Alt | Neu |
|---|---|
| `NewSettingsView` | `SettingsView` |
| `NewSettingsBlock` | `SettingsBlock` |
| `NewSettingRow` | `SettingRow` |
| `NewInfoRow` | `InfoRow` |
| `NewGeneralSettingsView` | `GeneralSettingsView` |
| `NewAppearanceSettingsView` | `AppearanceSettingsView` |
| `NewArticleListSettingsView` | `ArticleListSettingsView` |
| `NewMenubarSettingsView` | `MenubarSettingsView` |
| `NewSlider` | `SettingsSlider` |
| `NewCacheSettingsView` | `CacheSettingsView` |
| `NewNotificationSettingsView` | `NotificationSettingsView` |
| `NewRefreshSettingsView` | `RefreshSettingsView` |
| `NewSyncSettingsView` | `SyncSettingsView` |
| `NewCleanupSettingsView` | `CleanupSettingsView` |
| `NewSettingsAboutView` | `SettingsAboutView` |
| `NewShortcutsSettingsView` | `ShortcutsSettingsView` |

Nach allen 16 Ersetzungen: per Grep in derselben Datei verifizieren, dass
kein `New[A-Z]`-Vorkommen mehr übrig ist:

Run: `grep -n "\bNew[A-Z][a-zA-Z]*\b" Feedivo/Views/Settings/SettingsView.swift`
Expected: keine Treffer (leere Ausgabe).

- [ ] **Step 2: `FeedivoApp.swift:171` umstellen**

Vorher:
```swift
            NewSettingsView()
```

Nachher:
```swift
            SettingsView()
```

- [ ] **Step 3: `FeedivoAppSceneConfigurationTests.swift:35-48` umstellen**

Vorher:
```swift
    @Test func settingsSceneUsesOnlyNewSettingsView() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSourceURL = projectRoot.appendingPathComponent("Feedivo/App/FeedivoApp.swift")
        let appSource = try String(contentsOf: appSourceURL, encoding: .utf8)

        #expect(appSource.contains("Settings {"))
        #expect(appSource.contains("NewSettingsView()"))
        #expect(!appSource.contains("SettingsCommands()"))
        #expect(!appSource.contains("Einstellungen alt"))
        #expect(!appSource.contains("SettingsView.oldWindowID"))
    }
```

Nachher (nur Funktionsname und die eine markierte Assertion ändern sich,
die drei anderen Assertions bleiben unverändert):
```swift
    @Test func settingsSceneUsesOnlySettingsView() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSourceURL = projectRoot.appendingPathComponent("Feedivo/App/FeedivoApp.swift")
        let appSource = try String(contentsOf: appSourceURL, encoding: .utf8)

        #expect(appSource.contains("Settings {"))
        #expect(appSource.contains("SettingsView()"))
        #expect(!appSource.contains("SettingsCommands()"))
        #expect(!appSource.contains("Einstellungen alt"))
        #expect(!appSource.contains("SettingsView.oldWindowID"))
    }
```

- [ ] **Step 4: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Gezielte Regressionstests laufen lassen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests -parallel-testing-enabled NO`
Expected: `settingsSceneUsesOnlySettingsView` und
`settingsFensterBleibtAufGlobalePreferencesReduziert` beide grün (letzterer
prüft nur `case general`/`case appearance`/… Enum-Case-Namen in
`SettingsView.swift`, nicht die hier umbenannten Typnamen — unverändert
betroffen). Die 9 bekannten, vorbestehenden Fehlschläge dieser Suite (siehe
Global Constraints) bleiben bestehen und sind KEINE neue Regression.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/Settings/SettingsView.swift Feedivo/App/FeedivoApp.swift FeedivoTests/FeedivoAppSceneConfigurationTests.swift
git commit -m "Refactor: Vestigiales New-Präfix an 17 SettingsView-Typen entfernt, windowID unverändert (Finding 2.8)"
```

---

### Task 4: `RuleViewModel.swift` löschen (toter Code)

**⚠️ Korrektur nach Blocker eines ersten Implementierungsversuchs (siehe
Whole-Branch-Kontext):** Der ursprüngliche Plantext ging davon aus,
`RuleViewModel.swift` sei komplett toter Code. Tatsächlich enthält die Datei
DREI Top-Level-Deklarationen — nur die Klasse `RuleViewModel` selbst
(Zeilen 20-260) ist tot (0 Produktions-Instanziierungen, verifiziert). Die
beiden anderen Deklarationen sind produktiv im Einsatz und MÜSSEN vor der
Löschung in eigene Dateien verschoben werden:
- `struct RuleConditionDraft` (Zeilen 8-13) — verwendet in
  `Feedivo/Views/Rules/RuleSettingsView.swift`,
  `Feedivo/Views/Rules/RuleWizardView.swift`,
  `Feedivo/Services/RuleEngine.swift`,
  `Feedivo/Stores/SQLiteRuleEvaluationStore.swift`,
  `Feedivo/Models/RuleConditionOperator.swift` sowie mehreren Testdateien
  (`SQLiteRuleEvaluationStoreTests.swift`, `RuleEngineTests.swift`,
  `RuleConditionOperatorTests.swift`).
- `enum RuleMoveDirection` (Zeilen 15-18) — verwendet in
  `Feedivo/Views/Rules/RuleSettingsView.swift:256`
  (`private func move(_ rule: RuleRecord, direction: RuleMoveDirection)`).

**Files:**
- Create: `Feedivo/Models/RuleConditionDraft.swift`
- Create: `Feedivo/Models/RuleMoveDirection.swift`
- Delete: `Feedivo/ViewModels/RuleViewModel.swift`
- Delete: `FeedivoTests/RuleViewModelTests.swift`

**Nutzerentscheidung (bereits eingeholt):** die tote `RuleViewModel`-Klasse
löschen, nicht liegen lassen — bezieht sich nur auf die Klasse selbst, nicht
auf die beiden produktiv genutzten Typen, die jetzt erhalten bleiben.
Verifiziert: 0 Instanziierungen `RuleViewModel(` in `Feedivo/`
(Produktionscode). `FeedivoTests/FeedivoAppSceneConfigurationTests.swift:952`
und `:960` enthalten bereits bestehende Regressionstests, die die
**Abwesenheit** von `RuleViewModel()` im Quelltext von `SettingsView.swift`
bzw. `RuleWizardView.swift` prüfen (reine String-Prüfungen des Quelltexts,
keine echte Kompilierungsabhängigkeit) — diese bleiben unverändert bestehen,
da sie nur nach `RuleViewModel()` suchen, nicht nach `RuleConditionDraft`
oder `RuleMoveDirection`. Das Xcode-Projekt nutzt file-system-synchronisierte
Gruppen für `Feedivo/` und `FeedivoTests/` — reines Anlegen/Löschen der
Dateien genügt, keine manuelle `project.pbxproj`-Bearbeitung nötig.
`FeedivoTests/RuleViewModelTests.swift` (334 Zeilen) testet ausschließlich
`RuleViewModel`-Verhalten (jeder Test instanziiert `RuleViewModel()`) — auch
dort, wo `RuleConditionDraft`-Instanzen als Testdaten übergeben werden, wird
NICHT `RuleConditionDraft` selbst getestet, sondern wie `RuleViewModel` damit
umgeht. Diese Testdatei wird komplett gelöscht; `RuleConditionDraft` bleibt
weiterhin durch die anderen, unabhängigen Testdateien abgedeckt
(`RuleConditionOperatorTests.swift`, `RuleEngineTests.swift`,
`SQLiteRuleEvaluationStoreTests.swift`).

**Interfaces:**
- Produces: `RuleConditionDraft` (unverändertes Interface, nur Datei
  verschoben) und `RuleMoveDirection` (unverändertes Interface, nur Datei
  verschoben) — beide weiterhin modulweit (`internal`) sichtbar wie zuvor.

- [ ] **Step 1: `RuleConditionDraft` in eigene Datei verschieben**

Neue Datei `Feedivo/Models/RuleConditionDraft.swift`:

```swift
import Foundation

struct RuleConditionDraft: Identifiable, Equatable {
    var id = UUID()
    var field: RuleConditionField
    var conditionOperator: RuleConditionOperator
    var value: String
}
```

- [ ] **Step 2: `RuleMoveDirection` in eigene Datei verschieben**

Neue Datei `Feedivo/Models/RuleMoveDirection.swift`:

```swift
enum RuleMoveDirection {
    case up
    case down
}
```

- [ ] **Step 3: `RuleViewModel.swift` und `RuleViewModelTests.swift` löschen**

```bash
git rm Feedivo/ViewModels/RuleViewModel.swift FeedivoTests/RuleViewModelTests.swift
```

- [ ] **Step 4: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Regressionstests laufen lassen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests -parallel-testing-enabled NO`
Expected: die beiden `RuleViewModel`-Abwesenheits-Tests (Zeilen 952, 960)
bleiben grün. Die bereits bekannten, vorbestehenden Fehlschläge dieser Suite
(siehe Global Constraints — Anzahl ist laut Task-3-Review-Erkenntnis
tatsächlich 13, nicht die in CLAUDE.md dokumentierten 9) bleiben bestehen und
sind KEINE neue Regression.

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/RuleConditionOperatorTests -only-testing:FeedivoTests/RuleEngineTests -only-testing:FeedivoTests/SQLiteRuleEvaluationStoreTests -parallel-testing-enabled NO`
Expected: alle Tests weiterhin grün — beweist, dass `RuleConditionDraft` nach
dem Verschieben in die neue Datei weiterhin korrekt auffindbar und nutzbar
ist für alle drei unabhängigen Verbraucher.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Models/RuleConditionDraft.swift Feedivo/Models/RuleMoveDirection.swift
git commit -m "Cleanup: RuleConditionDraft und RuleMoveDirection aus RuleViewModel.swift ausgelagert, tote RuleViewModel-Klasse entfernt"
```

---

## Abschließender Whole-Branch-Review

Nach Task 4: gesamten Diff seit dem letzten gepushten Commit (`43befc2fa`)
gegen diesen Plan und gegen CLAUDE.md prüfen (Opus-Review, wie bei Gruppe A).
Insbesondere prüfen: dass `NewSlider` tatsächlich zu `SettingsSlider`
geworden ist (nicht zu bloßem `Slider`), dass `SettingsView.windowID`
unverändert `"feedivo-settings-new"` ist, und dass keine der 17
Typumbenennungen aus Task 3 versehentlich einen Aufrufer außerhalb von
`SettingsView.swift`/`FeedivoApp.swift`/`FeedivoAppSceneConfigurationTests.swift`
übersehen hat.
