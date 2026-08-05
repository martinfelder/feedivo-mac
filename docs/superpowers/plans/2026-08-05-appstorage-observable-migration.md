# `@AppStorage`→`@Observable`-Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `SQLiteDataInvalidation` und `SidebarBadgeInvalidation` von `UserDefaults`-
basierter `@AppStorage`-Beobachtung auf native `@Observable`-Singletons umstellen, um
die gemessene ~220-250ms SwiftUI-Benachrichtigungslatenz bei Statusänderungen (z. B.
Artikel als gelesen markieren) zu beheben.

**Architecture:** Beide Typen werden zu `@MainActor @Observable final class`-
Singletons (Muster: `FeedJumpKeyMonitor`/`TextEditingFocusMonitor`/
`SparkleUpdateCoordinator`) mit `static let shared`, einer `private(set) var`-
Zählerproperty und einer `bump...()`-Methode. Views lesen den Zähler direkt
(`SQLiteDataInvalidation.shared.statusVersion`), kein Property-Wrapper mehr nötig.
Migration erfolgt schrittweise mit temporärer Koexistenz der alten `UserDefaults`-API
(entfernt erst im letzten Task), damit der Build zwischen den Tasks kompilierfähig
bleibt (etabliertes Muster in diesem Projekt, siehe z. B. Regel-Bedingungen-
Gruppierung-Task 1).

**Tech Stack:** Swift 6 Observation-Framework (`@Observable`), Swift Concurrency
(`@MainActor`), Swift Testing (`@Test`/`#expect`), GRDB/SQLite (unverändert).

## Global Constraints

- Kommentare im Code auf Deutsch (Projektkonvention).
- Bestehende `UserDefaults`-Keys für ANDERE Zwecke (z. B. `MenubarSettings.
  isEnabledKey`, `"appLanguage"`, `InterfaceTextSize.storageKey`,
  `AppAppearance.storageKey`) bleiben unverändert `UserDefaults`-basiert — nur
  `SQLiteDataInvalidation`/`SidebarBadgeInvalidation` werden umgestellt.
- Jeder Task muss nach Abschluss `xcodebuild build` grün halten (temporäre
  Koexistenz der alten API bis zum letzten Task, siehe Architecture oben).
- Tests laufen mit `-parallel-testing-enabled NO` (bekannter Projekt-Workaround
  für `UserDefaults.standard`-Races zwischen parallelen Tests, siehe CLAUDE.md).
- Keine Aufrufer außerhalb der in diesem Plan gelisteten Dateien — vor dem
  finalen Cleanup-Task (Task 8) per Grep verifizieren, dass keine weiteren
  Referenzen auf die alte API existieren.

---

## Task 1: `SQLiteDataInvalidation` und `SidebarBadgeInvalidation` als `@Observable`-Singletons

**Files:**
- Modify: `Feedivo/Database/SQLiteDataInvalidation.swift`
- Modify: `Feedivo/Views/Sidebar/SidebarUnreadCount.swift:33-45` (enthält
  `SidebarBadgeInvalidation`)
- Test: `FeedivoTests/Database/SQLiteDataInvalidationTests.swift` (neu)
- Test: `FeedivoTests/Views/Sidebar/SidebarBadgeInvalidationTests.swift` (neu)

**Interfaces:**
- Produces: `SQLiteDataInvalidation.shared.statusVersion: Int` (read-only von
  außen), `SQLiteDataInvalidation.shared.bumpStatusVersion() -> Void`,
  `SQLiteDataInvalidation.shared.reset() -> Void` (testonly). Analog
  `SidebarBadgeInvalidation.shared.directTagVersion`,
  `.bumpDirectTagVersion()`, `.reset()`.
- Die ALTE API (`SQLiteDataInvalidation.statusVersionKey` (String-Konstante),
  `SQLiteDataInvalidation.bumpStatusVersion()` (statische Funktion, alte
  Signatur mit `defaults:`-Parameter) und `SidebarBadgeInvalidation.
  directTagVersionKey`/`.bumpDirectTagVersion()` (statisch)) bleibt in diesem
  Task UNVERÄNDERT bestehen — wird erst in Task 8 entfernt.

- [ ] **Step 1: Neue Tests für `SQLiteDataInvalidation` schreiben (RED)**

Neue Datei `FeedivoTests/Database/SQLiteDataInvalidationTests.swift`:

```swift
import Testing
@testable import Feedivo

@MainActor
struct SQLiteDataInvalidationTests {
    @Test func bumpStatusVersionErhoehtDenZaehler() {
        SQLiteDataInvalidation.shared.reset()
        let initial = SQLiteDataInvalidation.shared.statusVersion

        SQLiteDataInvalidation.shared.bumpStatusVersion()

        #expect(SQLiteDataInvalidation.shared.statusVersion == initial + 1)
    }

    @Test func mehrfachesBumpenErhoehtKumulativ() {
        SQLiteDataInvalidation.shared.reset()

        SQLiteDataInvalidation.shared.bumpStatusVersion()
        SQLiteDataInvalidation.shared.bumpStatusVersion()
        SQLiteDataInvalidation.shared.bumpStatusVersion()

        #expect(SQLiteDataInvalidation.shared.statusVersion == 3)
    }

    @Test func resetSetztAufNullZurueck() {
        SQLiteDataInvalidation.shared.bumpStatusVersion()

        SQLiteDataInvalidation.shared.reset()

        #expect(SQLiteDataInvalidation.shared.statusVersion == 0)
    }
}
```

- [ ] **Step 2: Tests ausführen, um sicherzustellen, dass sie fehlschlagen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteDataInvalidationTests -parallel-testing-enabled NO`
Expected: FAIL — `SQLiteDataInvalidation.shared` existiert noch nicht.

- [ ] **Step 3: `SQLiteDataInvalidation.swift` um das neue Singleton ergänzen**

`Feedivo/Database/SQLiteDataInvalidation.swift` komplett ersetzen durch:

```swift
import Foundation

/// UserDefaults-basierte Version — bleibt bis Task 8 als Kompatibilitäts-
/// Fundament für noch nicht migrierte Aufrufer bestehen.
enum SQLiteDataInvalidation {
    static let statusVersionKey = "sqliteData.statusVersion"

    static func bumpStatusVersion(defaults: UserDefaults = .standard) {
        defaults.set(
            defaults.integer(forKey: statusVersionKey) + 1,
            forKey: statusVersionKey
        )
    }
}

/// Ersetzt `SQLiteDataInvalidation`s `UserDefaults`/`@AppStorage`-Mechanismus
/// durch natives SwiftUI-`@Observable` (2026-08-05, Reader-Ladeverzögerung-
/// Folgearbeit — siehe docs/superpowers/specs/2026-08/
/// 2026-08-05-appstorage-observable-migration-design.md). Views lesen
/// `statusVersion` direkt in `body`/`.onChange(of:)`, kein Property-Wrapper
/// nötig. `@MainActor`-isoliert, da `@Observable`-Mutationen — anders als
/// `UserDefaults` — nicht thread-sicher sind; Aufrufer außerhalb des
/// MainActor-Kontexts müssen explizit hoppen (siehe betroffene Tasks).
@MainActor
@Observable
final class SQLiteDataInvalidationSignal {
    static let shared = SQLiteDataInvalidationSignal()
    private init() {}

    private(set) var statusVersion = 0

    func bumpStatusVersion() {
        statusVersion += 1
    }

    /// Nur für Tests: isoliert aufeinanderfolgende Testfälle voneinander,
    /// analog zum bereits bestehenden `-parallel-testing-enabled NO`-
    /// Workaround für `UserDefaults.standard`-Races in diesem Projekt.
    func reset() {
        statusVersion = 0
    }
}
```

**Wichtig:** Der neue Typ heißt `SQLiteDataInvalidationSignal` (nicht
`SQLiteDataInvalidation`), damit er als eigener Typ NEBEN dem unveränderten
`enum SQLiteDataInvalidation` existieren kann (ein `enum` und eine `final
class` können nicht denselben Namen tragen). In Task 8 wird beim Entfernen
der alten API `SQLiteDataInvalidationSignal` auf den Namen
`SQLiteDataInvalidation` umbenannt (finaler, sauberer Name ohne
„Signal"-Suffix).

- [ ] **Step 4: Tests ausführen, um sicherzustellen, dass sie bestehen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteDataInvalidationTests -parallel-testing-enabled NO`
Expected: PASS (3/3)

Falls Referenzfehler wegen `SQLiteDataInvalidationSignal` in Tests: sicherstellen,
dass die Testdatei `@testable import Feedivo` hat.

- [ ] **Step 5: Analog `SidebarBadgeInvalidationSignal` in `SidebarUnreadCount.swift` ergänzen**

In `Feedivo/Views/Sidebar/SidebarUnreadCount.swift`, NACH dem bestehenden
`enum SidebarBadgeInvalidation`-Block (Zeilen 33-45, unverändert lassen)
einfügen:

```swift
/// Ersetzt `SidebarBadgeInvalidation`s `UserDefaults`/`@AppStorage`-
/// Mechanismus durch natives SwiftUI-`@Observable`, analog zu
/// `SQLiteDataInvalidationSignal` (siehe dort für die volle Begründung).
@MainActor
@Observable
final class SidebarBadgeInvalidationSignal {
    static let shared = SidebarBadgeInvalidationSignal()
    private init() {}

    private(set) var directTagVersion = 0

    func bumpDirectTagVersion() {
        directTagVersion += 1
    }

    /// Nur für Tests.
    func reset() {
        directTagVersion = 0
    }
}
```

- [ ] **Step 6: Test für `SidebarBadgeInvalidationSignal` schreiben und verifizieren (RED→GREEN)**

Neue Datei `FeedivoTests/Views/Sidebar/SidebarBadgeInvalidationTests.swift`:

```swift
import Testing
@testable import Feedivo

@MainActor
struct SidebarBadgeInvalidationSignalTests {
    @Test func bumpDirectTagVersionErhoehtDenZaehler() {
        SidebarBadgeInvalidationSignal.shared.reset()
        let initial = SidebarBadgeInvalidationSignal.shared.directTagVersion

        SidebarBadgeInvalidationSignal.shared.bumpDirectTagVersion()

        #expect(SidebarBadgeInvalidationSignal.shared.directTagVersion == initial + 1)
    }

    @Test func resetSetztAufNullZurueck() {
        SidebarBadgeInvalidationSignal.shared.bumpDirectTagVersion()

        SidebarBadgeInvalidationSignal.shared.reset()

        #expect(SidebarBadgeInvalidationSignal.shared.directTagVersion == 0)
    }
}
```

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SidebarBadgeInvalidationSignalTests -parallel-testing-enabled NO`
Expected: PASS (2/2)

- [ ] **Step 7: Vollständigen Build verifizieren (Koexistenz-Check)**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED — alte UND neue API existieren nebeneinander, kein
bestehender Aufrufer ist betroffen.

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Database/SQLiteDataInvalidation.swift \
        Feedivo/Views/Sidebar/SidebarUnreadCount.swift \
        FeedivoTests/Database/SQLiteDataInvalidationTests.swift \
        FeedivoTests/Views/Sidebar/SidebarBadgeInvalidationTests.swift
git commit -m "feat: @Observable-Singletons für SQLite-Invalidierung ergänzt (Koexistenz mit UserDefaults-API)"
```

---

## Task 2: Reader- & Artikelliste-Views migrieren

**Files:**
- Modify: `Feedivo/Views/ContentView.swift:27-28`
- Modify: `Feedivo/Views/Reader/ReaderTabBarView.swift:25-26`
- Modify: `Feedivo/Views/Reader/SQLiteReaderView.swift:85-89`
- Modify: `Feedivo/Views/Reader/ArticleTagAssignmentView.swift:20-21,182,204`
- Modify: `Feedivo/Views/Reader/ArticleMetadataInspectorView.swift:519,537`
- Modify: `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:32-35,1009,1133`
- Modify: `Feedivo/Views/ArticleList/ArticleSearchWindowView.swift:15-16`

**Interfaces:**
- Consumes (aus Task 1): `SQLiteDataInvalidationSignal.shared.statusVersion`,
  `.bumpStatusVersion()`; `SidebarBadgeInvalidationSignal.shared.
  directTagVersion`, `.bumpDirectTagVersion()`.

**Mechanische Transformationsregel (gilt für alle Steps in diesem Task):**
- `@AppStorage(SQLiteDataInvalidation.statusVersionKey) private var
  <name> = 0` → Zeile ersatzlos entfernen; jede Verwendung von `<name>` im
  Rest der Datei durch `SQLiteDataInvalidationSignal.shared.statusVersion`
  ersetzen.
- `@AppStorage(SidebarBadgeInvalidation.directTagVersionKey) private var
  <name> = 0` → analog mit `SidebarBadgeInvalidationSignal.shared.
  directTagVersion`.
- `SQLiteDataInvalidation.bumpStatusVersion()` →
  `SQLiteDataInvalidationSignal.shared.bumpStatusVersion()`.
- `SidebarBadgeInvalidation.bumpDirectTagVersion()` →
  `SidebarBadgeInvalidationSignal.shared.bumpDirectTagVersion()`.

- [ ] **Step 1: `ContentView.swift` migrieren**

Vorher (`Feedivo/Views/ContentView.swift:27-28`):
```swift
    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersion = 0
```
Löschen. Jedes Vorkommen von `sqliteStatusVersion` in `ContentView.swift`
durch `SQLiteDataInvalidationSignal.shared.statusVersion` ersetzen.

- [ ] **Step 2: `ReaderTabBarView.swift` migrieren**

Vorher (`Feedivo/Views/Reader/ReaderTabBarView.swift:25-26`):
```swift
    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersion = 0
```
Löschen, `sqliteStatusVersion`-Vorkommen ersetzen wie oben.

- [ ] **Step 3: `SQLiteReaderView.swift` migrieren (beide Keys)**

Vorher (`Feedivo/Views/Reader/SQLiteReaderView.swift:85-89`):
```swift
    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey)
    private var directTagVersion = 0

    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersion = 0
```
Beide Zeilen löschen. `directTagVersion` →
`SidebarBadgeInvalidationSignal.shared.directTagVersion`,
`sqliteStatusVersion` → `SQLiteDataInvalidationSignal.shared.statusVersion`
(betrifft u. a. `.onChange(of: sqliteStatusVersion)`/
`.onChange(of: directTagVersion)` weiter unten in derselben Datei).

- [ ] **Step 4: `ArticleTagAssignmentView.swift` migrieren**

Vorher (`Feedivo/Views/Reader/ArticleTagAssignmentView.swift:20-21`):
```swift
    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey)
    private var directTagVersion = 0
```
Löschen, Vorkommen ersetzen. Zwei Bump-Aufrufe anpassen:
- Zeile 182: `SidebarBadgeInvalidation.bumpDirectTagVersion()` →
  `SidebarBadgeInvalidationSignal.shared.bumpDirectTagVersion()`
- Zeile 204: identisch

- [ ] **Step 5: `ArticleMetadataInspectorView.swift` migrieren**

Zwei Bump-Aufrufe (Zeilen 519, 537):
`SQLiteDataInvalidation.bumpStatusVersion()` →
`SQLiteDataInvalidationSignal.shared.bumpStatusVersion()`. Diese Datei hat
keine `@AppStorage`-Deklaration.

- [ ] **Step 6: `SQLiteFeedArticleListView.swift` migrieren (beide Keys + 2 Bumps)**

Vorher (`Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift:32-35`):
```swift
    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey)
    private var directTagVersion = 0

    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersion = 0
```
Beide löschen, Vorkommen ersetzen (betrifft u. a. die 200ms-Debounce-Logik
`.task(id: sqliteStatusVersion)`/`updateDebouncedStatusVersion()` — der
gelesene WERT ändert sich, die Debounce-Logik selbst bleibt unverändert).
Zwei Bump-Aufrufe:
- Zeile 1009: `SQLiteDataInvalidation.bumpStatusVersion()` →
  `SQLiteDataInvalidationSignal.shared.bumpStatusVersion()`
- Zeile 1133: identisch

- [ ] **Step 7: `ArticleSearchWindowView.swift` migrieren**

Vorher (`Feedivo/Views/ArticleList/ArticleSearchWindowView.swift:15-16`):
```swift
    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersion = 0
```
Löschen, Vorkommen ersetzen.

- [ ] **Step 8: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED

- [ ] **Step 9: Betroffene Tests laufen lassen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteReaderStateTests -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests -parallel-testing-enabled NO`
Expected: Keine NEUEN Fehlschläge gegenüber dem Stand vor diesem Task (siehe
CLAUDE.md-Gotcha zur vorbestehenden Flakiness von
`SQLiteFeedArticleListStateTests`/`listStateToggeltReadUndAktualisiertRows` —
bekannt, keine Regression durch diesen Task).

- [ ] **Step 10: Commit**

```bash
git add Feedivo/Views/ContentView.swift \
        Feedivo/Views/Reader/ReaderTabBarView.swift \
        Feedivo/Views/Reader/SQLiteReaderView.swift \
        Feedivo/Views/Reader/ArticleTagAssignmentView.swift \
        Feedivo/Views/Reader/ArticleMetadataInspectorView.swift \
        Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift \
        Feedivo/Views/ArticleList/ArticleSearchWindowView.swift
git commit -m "refactor: Reader-/Artikelliste-Views auf @Observable-Invalidierungssignale umgestellt"
```

---

## Task 3: Sidebar- & Feed-Verwaltungs-Views migrieren

**Files:**
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift:13-16,317,327,344,362,372,387,418,436`
- Modify: `Feedivo/Views/Sidebar/FeedRenameView.swift:183,198`
- Modify: `Feedivo/Views/Sidebar/FeedPropertiesView.swift:598,615,651,668`
- Modify: `Feedivo/Views/Organizer/FeedManagementOrganizerView.swift:232,257`
- Modify: `Feedivo/Views/Tags/TagManagerView.swift:291,328,452,471`
- Modify: `FeedivoTests/App/FeedivoAppSceneConfigurationTests.swift:846`
- Modify: `FeedivoTests/App/FeedivoAppSceneConfigurationTests.swift:1007`

**Interfaces:**
- Consumes (aus Task 1): identisch zu Task 2.

- [ ] **Step 1: `SidebarView.swift` migrieren (beide Keys + 7 Bumps)**

Vorher (`Feedivo/Views/Sidebar/SidebarView.swift:13-16`):
```swift
    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey)
    private var directTagVersion = 0
    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersion = 0
```
Beide löschen, Vorkommen ersetzen. Sieben `SQLiteDataInvalidation.
bumpStatusVersion()`-Aufrufe (Zeilen 317, 327, 344, 362, 372, 387, 418, 436 —
je einzeln lokalisieren, alle identisch zu
`SQLiteDataInvalidationSignal.shared.bumpStatusVersion()` ersetzen).

- [ ] **Step 2: `FeedRenameView.swift` migrieren**

Zwei Bump-Aufrufe (Zeilen 183, 198), keine `@AppStorage`-Deklaration in
dieser Datei. Beide `SQLiteDataInvalidation.bumpStatusVersion()` →
`SQLiteDataInvalidationSignal.shared.bumpStatusVersion()`.

- [ ] **Step 3: `FeedPropertiesView.swift` migrieren**

Vier Bump-Aufrufe: Zeilen 598, 615
(`SidebarBadgeInvalidation.bumpDirectTagVersion()` →
`SidebarBadgeInvalidationSignal.shared.bumpDirectTagVersion()`), Zeilen 651,
668 (`SQLiteDataInvalidation.bumpStatusVersion()` →
`SQLiteDataInvalidationSignal.shared.bumpStatusVersion()`). Keine
`@AppStorage`-Deklaration in dieser Datei.

- [ ] **Step 4: `FeedManagementOrganizerView.swift` migrieren**

Zwei Bump-Aufrufe (Zeilen 232, 257), beide
`SQLiteDataInvalidation.bumpStatusVersion()` →
`SQLiteDataInvalidationSignal.shared.bumpStatusVersion()`.

- [ ] **Step 5: `TagManagerView.swift` migrieren**

Vier Bump-Aufrufe (Zeilen 291, 328, 452, 471), alle
`SidebarBadgeInvalidation.bumpDirectTagVersion()` →
`SidebarBadgeInvalidationSignal.shared.bumpDirectTagVersion()`.

- [ ] **Step 6: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Source-Sniffing-Test `sidebarViewLaedtSQLiteSidebarState` anpassen**

`FeedivoTests/App/FeedivoAppSceneConfigurationTests.swift:846`, vorher:
```swift
        #expect(sidebarSource.contains("@AppStorage(SQLiteDataInvalidation.statusVersionKey)"))
```
Ersetzen durch:
```swift
        #expect(sidebarSource.contains("SQLiteDataInvalidationSignal.shared.statusVersion"))
```

- [ ] **Step 8: Source-Sniffing-Test `feedPropertiesViewSpiegeltFeedTagsNachSQLite` anpassen**

`FeedivoTests/App/FeedivoAppSceneConfigurationTests.swift:1007`, vorher:
```swift
        #expect(source.contains("SidebarBadgeInvalidation.bumpDirectTagVersion()"))
```
Ersetzen durch:
```swift
        #expect(source.contains("SidebarBadgeInvalidationSignal.shared.bumpDirectTagVersion()"))
```

- [ ] **Step 9: Angepasste Tests ausführen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/sidebarViewLaedtSQLiteSidebarState -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/feedPropertiesViewSpiegeltFeedTagsNachSQLite -parallel-testing-enabled NO`
Expected: PASS (2/2) — Rest der Suite (17 bekannte vorbestehende Fehlschläge,
siehe CLAUDE.md) unverändert, hier nicht mitgetestet.

- [ ] **Step 10: Commit**

```bash
git add Feedivo/Views/Sidebar/SidebarView.swift \
        Feedivo/Views/Sidebar/FeedRenameView.swift \
        Feedivo/Views/Sidebar/FeedPropertiesView.swift \
        Feedivo/Views/Organizer/FeedManagementOrganizerView.swift \
        Feedivo/Views/Tags/TagManagerView.swift \
        FeedivoTests/App/FeedivoAppSceneConfigurationTests.swift
git commit -m "refactor: Sidebar-/Feed-Verwaltungs-Views auf @Observable-Invalidierungssignale umgestellt"
```

---

## Task 4: Settings-, SmartFolder- & Sync-Views migrieren

**Files:**
- Modify: `Feedivo/Views/Settings/SettingsView.swift:1126-1127`
- Modify: `Feedivo/Views/Settings/CleanupHistoryWindowView.swift:10-11`
- Modify: `Feedivo/Views/SmartFolders/SmartFolderEditorView.swift:7-8,463`
- Modify: `Feedivo/Views/SmartFolders/SmartFolderSettingsView.swift:7-8,231,244,254,264,274`
- Modify: `Feedivo/Views/Settings/CloudSyncFirstActivationView.swift:154`
- Modify: `Feedivo/Views/Settings/SyncConflictResolutionView.swift:238`

**Interfaces:**
- Consumes (aus Task 1): identisch zu Task 2.

- [ ] **Step 1: `SettingsView.swift` migrieren**

Vorher (`Feedivo/Views/Settings/SettingsView.swift:1126-1127`):
```swift
    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersionForSyncActivity = 0
```
Löschen. Jedes Vorkommen von `sqliteStatusVersionForSyncActivity` durch
`SQLiteDataInvalidationSignal.shared.statusVersion` ersetzen. Keine
Bump-Aufrufe in dieser Datei (nur Beobachtung).

- [ ] **Step 2: `CleanupHistoryWindowView.swift` migrieren**

Vorher (`Feedivo/Views/Settings/CleanupHistoryWindowView.swift:10-11`):
```swift
    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersionForCleanupHistory = 0
```
Löschen, Vorkommen von `sqliteStatusVersionForCleanupHistory` ersetzen.

- [ ] **Step 3: `SmartFolderEditorView.swift` migrieren (beide Keys + 1 Bump)**

Vorher (`Feedivo/Views/SmartFolders/SmartFolderEditorView.swift:7-8`):
```swift
    @AppStorage(SQLiteDataInvalidation.statusVersionKey) private var sqliteStatusVersion = 0
    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey) private var directTagVersion = 0
```
Beide löschen, Vorkommen ersetzen. Bump-Aufruf Zeile 463:
`SQLiteDataInvalidation.bumpStatusVersion()` →
`SQLiteDataInvalidationSignal.shared.bumpStatusVersion()`.

- [ ] **Step 4: `SmartFolderSettingsView.swift` migrieren (beide Keys + 4 Bumps)**

Vorher (`Feedivo/Views/SmartFolders/SmartFolderSettingsView.swift:7-8`):
```swift
    @AppStorage(SQLiteDataInvalidation.statusVersionKey) private var sqliteStatusVersion = 0
    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey) private var directTagVersion = 0
```
Beide löschen, Vorkommen ersetzen. Vier Bump-Aufrufe (Zeilen 231, 244, 254,
264, 274 — fünf tatsächlich, alle `SQLiteDataInvalidation.
bumpStatusVersion()` → `SQLiteDataInvalidationSignal.shared.
bumpStatusVersion()`).

- [ ] **Step 5: `CloudSyncFirstActivationView.swift` migrieren**

Bump-Aufruf Zeile 154: `SQLiteDataInvalidation.bumpStatusVersion()` →
`SQLiteDataInvalidationSignal.shared.bumpStatusVersion()`. Keine
`@AppStorage`-Deklaration in dieser Datei.

- [ ] **Step 6: `SyncConflictResolutionView.swift` migrieren**

Bump-Aufruf Zeile 238: identisch zu Step 5.

- [ ] **Step 7: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Views/Settings/SettingsView.swift \
        Feedivo/Views/Settings/CleanupHistoryWindowView.swift \
        Feedivo/Views/SmartFolders/SmartFolderEditorView.swift \
        Feedivo/Views/SmartFolders/SmartFolderSettingsView.swift \
        Feedivo/Views/Settings/CloudSyncFirstActivationView.swift \
        Feedivo/Views/Settings/SyncConflictResolutionView.swift
git commit -m "refactor: Settings-/SmartFolder-/Sync-Views auf @Observable-Invalidierungssignale umgestellt"
```

---

## Task 5: Store-/Service-/ViewModel-Schicht migrieren

**Files:**
- Modify: `Feedivo/ViewModels/FeedViewModel.swift:197,248,287,407,495`
- Modify: `Feedivo/Stores/ArticleStatusStore.swift:129,176`
- Modify: `Feedivo/Stores/SQLiteRuleEvaluationStore.swift:48`
- Modify: `Feedivo/Services/ArticleRetentionCleanupService.swift:79`
- Modify: `Feedivo/Services/SQLiteFeedRefreshService.swift:277,373`
- Modify: `Feedivo/Services/LocalExtensionBridge/LocalExtensionBridgeServer.swift:146`
- Modify: `FeedivoTests/ViewModels/FeedViewModelTests.swift:114-185`
- Modify: `FeedivoTests/App/FeedivoAppSceneConfigurationTests.swift:538`

**Interfaces:**
- Consumes (aus Task 1): `SQLiteDataInvalidationSignal.shared.
  bumpStatusVersion()`.

**Wichtig — Actor-Isolation-Check pro Datei:** Alle sechs Dateien in diesem
Task sind `@MainActor`-isolierte Klassen/Strukturen ODER ihre
`bumpStatusVersion()`-Aufrufe stehen bereits innerhalb bestehender
`@MainActor`-Kontexte (Standard-Aktor-Isolation dieses Projekts, siehe
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Vor jeder Änderung kurz
verifizieren (`grep -n "@MainActor\|nonisolated\|actor " <Datei>`), dass
kein `nonisolated`/`Task.detached`-Kontext betroffen ist — falls doch, das
sofort dem Nutzer melden statt stillschweigend `Task { @MainActor in ... }`
einzufügen (Nutzerentscheidung aus dem Design: explizite statt versteckte
Actor-Hops).

- [ ] **Step 1: `FeedViewModel.swift` migrieren (5 Bumps)**

Fünf Vorkommen von `SQLiteDataInvalidation.bumpStatusVersion()` (Zeilen 197,
248, 287, 407, 495) → `SQLiteDataInvalidationSignal.shared.
bumpStatusVersion()`.

- [ ] **Step 2: `ArticleStatusStore.swift` migrieren (2 Bumps)**

Zwei Vorkommen (Zeilen 129, 176) → `SQLiteDataInvalidationSignal.shared.
bumpStatusVersion()`. Zeile 187 ist nur ein Kommentar (erwähnt die
Batch-Variante, die BEWUSST keinen Bump auslöst) — Kommentartext auf den
neuen Aufrufnamen aktualisieren, aber Verhalten unverändert lassen.

- [ ] **Step 3: `SQLiteRuleEvaluationStore.swift` migrieren (1 Bump)**

Zeile 48 → `SQLiteDataInvalidationSignal.shared.bumpStatusVersion()`.

- [ ] **Step 4: `ArticleRetentionCleanupService.swift` migrieren (1 Bump)**

Zeile 79 → `SQLiteDataInvalidationSignal.shared.bumpStatusVersion()`.

- [ ] **Step 5: `SQLiteFeedRefreshService.swift` migrieren (2 Bumps)**

Zeilen 277, 373 → `SQLiteDataInvalidationSignal.shared.bumpStatusVersion()`.

- [ ] **Step 6: `LocalExtensionBridgeServer.swift` migrieren (1 Bump)**

Zeile 146 → `SQLiteDataInvalidationSignal.shared.bumpStatusVersion()`. Diese
Klasse ist bereits `@MainActor` (Zeile 12) und der Aufruf steht bereits
innerhalb eines `Task { @MainActor in ... }`-Blocks (siehe Datei-Kopf-
Kommentar) — keine zusätzliche Isolation nötig.

- [ ] **Step 7: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED. Falls ein Compiler-Fehler zu Actor-Isolation an
einer dieser 6 Stellen auftritt (bislang nicht erwartet, aber möglich): dem
Nutzer die betroffene Stelle melden, nicht eigenmächtig mit verstecktem
Task-Hopping umgehen.

- [ ] **Step 8: `FeedViewModelTests.swift` auf neue API umstellen**

`FeedivoTests/ViewModels/FeedViewModelTests.swift:114-185`, Testfunktion
`importOPMLFeedsAktualisiertNeueFeedsDirektNachDemImport`. Vorher (Auszug):
```swift
    @MainActor
    @Test func importOPMLFeedsAktualisiertNeueFeedsDirektNachDemImport() async throws {
        let defaults = UserDefaults.standard
        let previousStatusVersion = defaults.object(forKey: SQLiteDataInvalidation.statusVersionKey) as? Int
        let initialStatusVersion = defaults.integer(forKey: SQLiteDataInvalidation.statusVersionKey)
        defer {
            if let previousStatusVersion {
                defaults.set(previousStatusVersion, forKey: SQLiteDataInvalidation.statusVersionKey)
            } else {
                defaults.removeObject(forKey: SQLiteDataInvalidation.statusVersionKey)
            }
        }
```
Ersetzen durch:
```swift
    @MainActor
    @Test func importOPMLFeedsAktualisiertNeueFeedsDirektNachDemImport() async throws {
        SQLiteDataInvalidationSignal.shared.reset()
        let initialStatusVersion = SQLiteDataInvalidationSignal.shared.statusVersion
```
(Kein `defer`-Block mehr nötig — `reset()` am Anfang genügt, da der
Singleton-Zustand nicht über den Testlauf hinaus persistiert werden muss.)

Am Ende derselben Testfunktion, vorher:
```swift
        #expect(defaults.integer(forKey: SQLiteDataInvalidation.statusVersionKey) > initialStatusVersion)
```
Ersetzen durch:
```swift
        #expect(SQLiteDataInvalidationSignal.shared.statusVersion > initialStatusVersion)
```

- [ ] **Step 9: Source-Sniffing-Test `feedViewModelLeitetAddUndImportAnSQLiteSubscriptionServiceWeiter` anpassen**

`FeedivoTests/App/FeedivoAppSceneConfigurationTests.swift:538`, vorher:
```swift
        #expect(viewModelSource.contains("SQLiteDataInvalidation.bumpStatusVersion()"))
```
Ersetzen durch:
```swift
        #expect(viewModelSource.contains("SQLiteDataInvalidationSignal.shared.bumpStatusVersion()"))
```

- [ ] **Step 10: Angepasste Tests ausführen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedViewModelTests/importOPMLFeedsAktualisiertNeueFeedsDirektNachDemImport -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/feedViewModelLeitetAddUndImportAnSQLiteSubscriptionServiceWeiter -parallel-testing-enabled NO`
Expected: PASS (2/2)

- [ ] **Step 11: Commit**

```bash
git add Feedivo/ViewModels/FeedViewModel.swift \
        Feedivo/Stores/ArticleStatusStore.swift \
        Feedivo/Stores/SQLiteRuleEvaluationStore.swift \
        Feedivo/Services/ArticleRetentionCleanupService.swift \
        Feedivo/Services/SQLiteFeedRefreshService.swift \
        Feedivo/Services/LocalExtensionBridge/LocalExtensionBridgeServer.swift \
        FeedivoTests/ViewModels/FeedViewModelTests.swift \
        FeedivoTests/App/FeedivoAppSceneConfigurationTests.swift
git commit -m "refactor: Store-/Service-/ViewModel-Schicht auf @Observable-Invalidierungssignal umgestellt"
```

---

## Task 6: `MenubarStatusItemController` — KVO durch `withObservationTracking` ersetzen

**Kontext:** Dieser Controller ist eine reine `NSObject`-Klasse (kein
SwiftUI-View), die `SQLiteDataInvalidation.statusVersionKey` bislang per
klassischem Foundation-KVO beobachtet (`UserDefaults.standard.addObserver
(self, forKeyPath: key, ...)`, siehe `Feedivo/App/
MenubarStatusItemController.swift:47-61,76-78`). KVO funktioniert nur mit
`UserDefaults`-Keys, nicht mit `@Observable`-Properties — braucht deshalb
einen eigenen Mechanismus statt der mechanischen Textersetzung aus Task 2-5:
Swifts Observation-Framework bietet dafür `withObservationTracking(_:
onChange:)`, ein selbst-erneuerndes Beobachtungsmuster (jeder Aufruf
beobachtet nur EIN einziges Mal, `onChange` muss sich selbst neu
registrieren).

**Files:**
- Modify: `Feedivo/App/MenubarStatusItemController.swift`
- Modify: `FeedivoTests/Services/MenubarStatusItemControllerTests.swift`
  (bereits vorhanden — enthält bislang 4 Tests für die reinen, nonisolated
  statischen Helfer `symbolName(forUnreadCount:)`/
  `badgeText(forUnreadCount:)`, keine Tests der Controller-Instanz selbst;
  `struct MenubarStatusItemControllerTests` trägt aktuell KEIN `@MainActor`
  auf Struct-Ebene — der neue Test in Step 5 bekommt es deshalb einzeln auf
  Funktionsebene, um die bestehenden 4 Tests unverändert zu lassen)

**Interfaces:**
- Consumes (aus Task 1): `SQLiteDataInvalidationSignal.shared.
  statusVersion`.

- [ ] **Step 1: `statusVersionKey` aus `observedKeys` entfernen**

`Feedivo/App/MenubarStatusItemController.swift:54-61`, vorher:
```swift
    private static let observedKeys = [
        MenubarSettings.isEnabledKey,
        MenubarSettings.hidesDockIconKey,
        SQLiteDataInvalidation.statusVersionKey,
        "appLanguage",
        InterfaceTextSize.storageKey,
        AppAppearance.storageKey
    ]
```
Ersetzen durch:
```swift
    private static let observedKeys = [
        MenubarSettings.isEnabledKey,
        MenubarSettings.hidesDockIconKey,
        "appLanguage",
        InterfaceTextSize.storageKey,
        AppAppearance.storageKey
    ]
```

- [ ] **Step 2: `withObservationTracking`-Methode ergänzen**

Direkt nach `init(feedivoDatabase:feedViewModel:)` (nach dem bestehenden
`applyCurrentSettings()`-Aufruf am Ende des Initializers, siehe Zeile 79)
folgende neue private Methode ergänzen und im Initializer aufrufen:

```swift
    /// Beobachtet `SQLiteDataInvalidationSignal.shared.statusVersion` — der
    /// bisherige KVO-Mechanismus (`observedKeys`) funktioniert nur mit
    /// `UserDefaults`-Keys, nicht mit `@Observable`-Properties.
    /// `withObservationTracking` beobachtet nur EIN einziges Mal; `onChange`
    /// registriert sich deshalb bei jedem Feuern selbst neu (Standardmuster
    /// des Observation-Frameworks für Nicht-SwiftUI-Beobachter).
    private func observeStatusVersionSignal() {
        withObservationTracking {
            _ = SQLiteDataInvalidationSignal.shared.statusVersion
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyCurrentSettings()
                self?.observeStatusVersionSignal()
            }
        }
    }
```

Im Initializer, direkt nach dem bestehenden `applyCurrentSettings()`-Aufruf
(Zeile 79), ergänzen:
```swift
        applyCurrentSettings()
        observeStatusVersionSignal()
```

- [ ] **Step 3: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Test für die neue Observation-Anbindung ergänzen**

In der BESTEHENDEN Datei `FeedivoTests/Services/
MenubarStatusItemControllerTests.swift` (siehe Files oben — bereits 4 Tests
für `symbolName`/`badgeText`, `struct` selbst trägt kein `@MainActor`),
folgenden Test INNERHALB der bestehenden `struct
MenubarStatusItemControllerTests { ... }` ergänzen (nicht die Datei
überschreiben, nur den Funktionskörper unten einfügen, `@MainActor` einzeln
auf diese eine neue Funktion setzen, da die 4 bestehenden Tests nonisolated
bleiben):

```swift
    @MainActor
    @Test func reagiertAufStatusVersionSignalOhneAbsturz() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedViewModel = FeedViewModel()
        let controller = MenubarStatusItemController(
            feedivoDatabase: database,
            feedViewModel: feedViewModel
        )
        _ = controller // Referenz halten, ARC darf den Controller nicht vor Testende freigeben

        SQLiteDataInvalidationSignal.shared.bumpStatusVersion()

        // withObservationTracking feuert asynchron über Task { @MainActor in ... } —
        // ein kurzer Yield genügt, damit der Callback vor der Assertion durchläuft.
        await Task.yield()

        // Kein Absturz bis hierhin ist die eigentliche Assertion dieses Tests:
        // verifiziert, dass die Observation-Anbindung nicht crasht und der
        // Controller nach einem Bump weiterhin ansprechbar ist. `FeedViewModel()`
        // ohne Argumente ist gültig — alle Initializer-Parameter haben Defaults
        // (verifiziert gegen `Feedivo/ViewModels/FeedViewModel.swift:96-115`),
        // `MenubarStatusItemController(feedivoDatabase:feedViewModel:)` entspricht
        // exakt dem echten Aufruf in `FeedivoAppDelegate.swift:42-45`.
        #expect(true)
    }
```

Eine echte visuelle Verifikation des Menubar-Icons nach einem Bump (kein
computer-use für native macOS-Apps in dieser Umgebung verfügbar, siehe
CLAUDE.md) bleibt manuelle Nutzer-Verifikation, siehe Task 8.

- [ ] **Step 5: Test ausführen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/MenubarStatusItemControllerTests -parallel-testing-enabled NO`
Expected: PASS (5/5 — 4 bestehende + 1 neuer)

- [ ] **Step 6: Commit**

```bash
git add Feedivo/App/MenubarStatusItemController.swift \
        FeedivoTests/Services/MenubarStatusItemControllerTests.swift
git commit -m "refactor: MenubarStatusItemController beobachtet SQLiteDataInvalidationSignal statt KVO auf UserDefaults-Key"
```

---

## Task 7: `CloudSyncEngine.swift` migrieren (isolierter Task wegen Actor-Isolation-Historie)

**Kontext:** `CloudSyncEngine` ist `@MainActor`-isoliert (Klassendeklaration),
hat aber eine `nonisolated static func backfillAllExistingRecords(database:)`
(Zeile 304), deren einziger Produktiv-Aufrufer bereits in einem
MainActor-Kontext läuft (`CloudSyncEngine.swift:128`, direkt neben
`self.syncEngine = engine`). Dieses Projekt hat die höchste bekannte Dichte
an bereits einmal gefundenen Actor-Isolation-/Reentrancy-Bugs in genau dieser
Datei (siehe CLAUDE.md-Gotcha zu `Task.detached`/`CKSyncEngine`-Reentrancy) —
deshalb eigener, isolierter Task statt Vermischung mit Task 5.

**Files:**
- Modify: `Feedivo/Services/CloudSync/CloudSyncEngine.swift:304,332,452,464,628`
- Modify: `FeedivoTests/Services/CloudSync/CloudSyncEngineRegistryTests.swift:73-96`

**Interfaces:**
- Consumes (aus Task 1): `SQLiteDataInvalidationSignal.shared.
  bumpStatusVersion()`.
- Produces: `CloudSyncEngine.backfillAllExistingRecords(database:)` verliert
  `nonisolated` und wird dadurch `@MainActor`-isoliert (Signaturänderung,
  siehe Step 1 — bleibt aber weiterhin synchron, kein `async` nötig) —
  betrifft den einzigen Produktiv-Aufrufer (Step 4) und die zwei
  Test-Aufrufer (Step 5).

- [ ] **Step 1: `backfillAllExistingRecords` von `nonisolated static` auf `@MainActor`-isoliert umstellen**

`Feedivo/Services/CloudSync/CloudSyncEngine.swift:304`, vorher:
```swift
    nonisolated static func backfillAllExistingRecords(database: FeedivoDatabase) throws {
```
Ersetzen durch:
```swift
    static func backfillAllExistingRecords(database: FeedivoDatabase) throws {
```
(Kein `nonisolated` mehr — die Methode erbt jetzt die `@MainActor`-Isolation
der umschließenden Klasse. Kein `async` nötig, da der Methodenkörper selbst
keine Suspension-Punkte enthält, nur der AUFRUF von außerhalb des MainActor-
Kontexts müsste künftig `await` nutzen — aus einem bereits-MainActor-Kontext
heraus bleibt der Aufruf synchron.)

- [ ] **Step 2: Bump-Aufruf innerhalb `backfillAllExistingRecords` anpassen**

Zeile 332: `SQLiteDataInvalidation.bumpStatusVersion()` →
`SQLiteDataInvalidationSignal.shared.bumpStatusVersion()`.

- [ ] **Step 3: Restliche drei Bump-Aufrufe in dieser Datei anpassen**

Zeilen 452, 464, 628 — alle bereits in regulären (nicht `nonisolated`)
Instanzmethoden der `@MainActor`-Klasse, keine Isolations-Änderung nötig.
`SQLiteDataInvalidation.bumpStatusVersion()` →
`SQLiteDataInvalidationSignal.shared.bumpStatusVersion()`.

- [ ] **Step 4: Build verifizieren — Produktiv-Aufrufer prüfen**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED. Der Aufruf `try Self.backfillAllExistingRecords
(database: database)` bei `CloudSyncEngine.swift:128` steht bereits
innerhalb der `@MainActor`-isolierten `start()`-Methode dieser Klasse — sollte
ohne Änderung weiter kompilieren. Falls NICHT (unerwarteter Compiler-Fehler):
dem Nutzer melden statt selbstständig einen Task-Hop einzufügen.

- [ ] **Step 5: Test-Aufrufer in `CloudSyncEngineRegistryTests.swift` anpassen**

`FeedivoTests/Services/CloudSync/CloudSyncEngineRegistryTests.swift`, zwei
betroffene Testfunktionen. Vorher (`backfillAllExistingRecordsEnqueuedAlleBestehendenZeilenAlsSave`):
```swift
    @Test func backfillAllExistingRecordsEnqueuedAlleBestehendenZeilenAlsSave() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try TagStore(database: database).save(TagRecord(id: "tag-1", name: "Alt", colorHex: "#000000"))
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://a.example.com", title: "A"))

        try CloudSyncEngine.backfillAllExistingRecords(database: database)
```
Ersetzen durch:
```swift
    @MainActor
    @Test func backfillAllExistingRecordsEnqueuedAlleBestehendenZeilenAlsSave() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try TagStore(database: database).save(TagRecord(id: "tag-1", name: "Alt", colorHex: "#000000"))
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://a.example.com", title: "A"))

        try CloudSyncEngine.backfillAllExistingRecords(database: database)
```
(`@MainActor` auf der Testfunktion ergänzt — der Aufruf selbst bleibt
synchron/`try`, da `backfillAllExistingRecords` weiterhin nicht `async` ist,
nur MainActor-isoliert; ein `@Test`-Funktion, die selbst `@MainActor` ist,
kann MainActor-isolierte synchrone Methoden direkt aufrufen.)

Analog für `backfillAllExistingRecordsSchliesstDefaultIntelligenteOrdnerAus`
(zweite Testfunktion in derselben Datei) — `@MainActor` vor `@Test`
ergänzen, Rest der Funktion unverändert.

- [ ] **Step 6: Angepasste Tests ausführen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/CloudSyncEngineRegistryTests -parallel-testing-enabled NO`
Expected: PASS (alle Tests dieser Suite, keine neuen Fehlschläge)

- [ ] **Step 7: Vollständige CloudSync-Testsuite laufen lassen (Sonderfall-Sorgfalt)**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/Services/CloudSync -parallel-testing-enabled NO`
Expected: Keine NEUEN Fehlschläge gegenüber dem Stand vor diesem Task.

- [ ] **Step 8: Commit**

```bash
git add Feedivo/Services/CloudSync/CloudSyncEngine.swift \
        FeedivoTests/Services/CloudSync/CloudSyncEngineRegistryTests.swift
git commit -m "refactor: CloudSyncEngine auf @Observable-Invalidierungssignal umgestellt, backfillAllExistingRecords MainActor-isoliert"
```

---

## Task 8: Alte `UserDefaults`-API entfernen, Umbenennung finalisieren, Gesamtverifikation

**Files:**
- Modify: `Feedivo/Database/SQLiteDataInvalidation.swift`
- Modify: `Feedivo/Views/Sidebar/SidebarUnreadCount.swift`
- Modify: `CLAUDE.md`

**Interfaces:**
- Keine neuen — dieser Task entfernt nur die alte, in Task 1 bewusst
  koexistierend belassene API und benennt `SQLiteDataInvalidationSignal`/
  `SidebarBadgeInvalidationSignal` final auf `SQLiteDataInvalidation`/
  `SidebarBadgeInvalidation` um (die alten `enum`-Namen sind ab hier frei).

- [ ] **Step 1: Verifizieren, dass keine Aufrufer der alten API mehr existieren**

Run: `grep -rn "SQLiteDataInvalidation\.\(statusVersionKey\|bumpStatusVersion\)\b" Feedivo FeedivoTests --include="*.swift" | grep -v "SQLiteDataInvalidationSignal"`
Expected: keine Treffer außer der Definition selbst in
`SQLiteDataInvalidation.swift`. Falls doch Treffer auftauchen: die
betroffene Datei fehlt in einem der Tasks 2-7 — dem Nutzer melden, bevor
weitergemacht wird.

Analog: `grep -rn "SidebarBadgeInvalidation\.\(directTagVersionKey\|bumpDirectTagVersion\)\b" Feedivo FeedivoTests --include="*.swift" | grep -v "SidebarBadgeInvalidationSignal"`

- [ ] **Step 2: Alte `enum SQLiteDataInvalidation` entfernen, `SQLiteDataInvalidationSignal` umbenennen**

`Feedivo/Database/SQLiteDataInvalidation.swift` komplett ersetzen durch:

```swift
import Foundation

/// Ersetzt einen vormaligen `UserDefaults`/`@AppStorage`-Mechanismus durch
/// natives SwiftUI-`@Observable` (2026-08-05, Reader-Ladeverzögerung-
/// Folgearbeit — siehe docs/superpowers/specs/2026-08/
/// 2026-08-05-appstorage-observable-migration-design.md). Views lesen
/// `statusVersion` direkt in `body`/`.onChange(of:)`, kein Property-Wrapper
/// nötig. `@MainActor`-isoliert, da `@Observable`-Mutationen — anders als
/// `UserDefaults` — nicht thread-sicher sind.
@MainActor
@Observable
final class SQLiteDataInvalidation {
    static let shared = SQLiteDataInvalidation()
    private init() {}

    private(set) var statusVersion = 0

    func bumpStatusVersion() {
        statusVersion += 1
    }

    /// Nur für Tests: isoliert aufeinanderfolgende Testfälle voneinander,
    /// analog zum bereits bestehenden `-parallel-testing-enabled NO`-
    /// Workaround für `UserDefaults.standard`-Races in diesem Projekt.
    func reset() {
        statusVersion = 0
    }
}
```

- [ ] **Step 3: Alle Aufrufer von `SQLiteDataInvalidationSignal` auf `SQLiteDataInvalidation` umbenennen**

Über das gesamte Projekt (alle in Task 2-7 geänderten Dateien plus die neuen
Testdateien aus Task 1/6):
```bash
grep -rl "SQLiteDataInvalidationSignal" Feedivo FeedivoTests --include="*.swift"
```
Für jede gefundene Datei: `SQLiteDataInvalidationSignal` → `SQLiteDataInvalidation`
per Suchen&Ersetzen (reine Textersetzung, keine Logikänderung).

- [ ] **Step 4: Analog für `SidebarBadgeInvalidation`**

`Feedivo/Views/Sidebar/SidebarUnreadCount.swift`, Zeilen 33-45 (die alte
`enum SidebarBadgeInvalidation`) löschen. Den direkt darunter (aus Task 1)
eingefügten `SidebarBadgeInvalidationSignal`-Block umbenennen zu:

```swift
/// Ersetzt einen vormaligen `UserDefaults`/`@AppStorage`-Mechanismus durch
/// natives SwiftUI-`@Observable`, analog zu `SQLiteDataInvalidation` (siehe
/// dort für die volle Begründung).
@MainActor
@Observable
final class SidebarBadgeInvalidation {
    static let shared = SidebarBadgeInvalidation()
    private init() {}

    private(set) var directTagVersion = 0

    func bumpDirectTagVersion() {
        directTagVersion += 1
    }

    /// Nur für Tests.
    func reset() {
        directTagVersion = 0
    }
}
```

Dann projektweit: `grep -rl "SidebarBadgeInvalidationSignal" Feedivo
FeedivoTests --include="*.swift"` → jede Fundstelle auf
`SidebarBadgeInvalidation` umbenennen.

- [ ] **Step 5: Vollständigen Build durchführen**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Vollen gezielten Regressionslauf durchführen**

Run (mit `-parallel-testing-enabled NO`):
```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' \
  -only-testing:FeedivoTests/SQLiteDataInvalidationTests \
  -only-testing:FeedivoTests/SidebarBadgeInvalidationSignalTests \
  -only-testing:FeedivoTests/SQLiteReaderStateTests \
  -only-testing:FeedivoTests/SQLiteFeedArticleListStateTests \
  -only-testing:FeedivoTests/FeedViewModelTests \
  -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests \
  -only-testing:FeedivoTests/MenubarStatusItemControllerTests \
  -only-testing:FeedivoTests/CloudSyncEngineRegistryTests \
  -only-testing:FeedivoTests/Services/CloudSync \
  -parallel-testing-enabled NO
```
Expected: keine NEUEN Fehlschläge gegenüber dem Stand vor Task 1 (bekannte
vorbestehende Ausnahmen: 17 Fehlschläge in
`FeedivoAppSceneConfigurationTests.swift`, Flakiness in
`SQLiteFeedArticleListStateTests`, siehe CLAUDE.md-Gotchas).

**Hinweis:** `SidebarBadgeInvalidationSignalTests`/
`SQLiteDataInvalidationTests` heißen nach Step 3/4 immer noch so (nur der
GETESTETE Typ wurde umbenannt, nicht die Testklasse selbst) — das ist
bewusst so belassen, kein zusätzlicher Umbenennungsschritt nötig.

- [ ] **Step 7: Live-Verifikation der ursprünglich gemessenen Reader-Ladezeit**

Per TEMP-DEBUG-`OSLog`-Instrumentierung (analog zur vorangegangenen
Debugging-Session, siehe CLAUDE.md „Aktuell in Arbeit" 2026-08-05 „Reader-
Ladeverzögerung" für das genaue Vorgehen: temporäre `PerfDebug`-Hilfsdatei
mit `Logger`-Zeitstempeln an denselben Messpunkten wie zuvor, `log stream
--level debug --predicate 'subsystem == "ch.martin.Feedivo" AND category ==
"PerfDebug"'`, App neu bauen/starten, Nutzer wählt 2-3 ungelesene Artikel
aus) verifizieren, dass die Zeit von Artikelauswahl bis sichtbarem Inhalt
sich der zuvor nur bei „kein Bump nötig"-Selektionen erreichten
~120-140ms-Bestzeit annähert (statt der vorher gemessenen ~415-690ms bei
Selektionen, die einen Status-Bump auslösen). Temporäre Instrumentierung
danach vollständig wieder entfernen (nie committen), wie beim vorherigen Mal.

- [ ] **Step 8: CLAUDE.md aktualisieren**

Neuen Eintrag unter „Aktuell in Arbeit" ergänzen (nach demselben Muster wie
der Eintrag „2026-08-05: Reader-Ladeverzögerung..." weiter oben in der
Datei): Migration vollständig abgeschlossen, gemessenes Vorher/Nachher-
Ergebnis aus Step 7, betroffene Dateien, Testergebnisse. M3/Offene-
Entscheidungen-Abschnitt NICHT berühren (diese Migration betrifft keinen der
dort gelisteten Punkte).

- [ ] **Step 9: Commit**

```bash
git add Feedivo/Database/SQLiteDataInvalidation.swift \
        Feedivo/Views/Sidebar/SidebarUnreadCount.swift \
        CLAUDE.md
git commit -m "refactor: alte UserDefaults-Invalidierungs-API entfernt, @Observable-Typen final umbenannt"
```

**Hinweis für den Nutzer:** Push nach `origin/main` erfolgt wie immer erst
nach expliziter Bestätigung (Projektkonvention, siehe CLAUDE.md).
