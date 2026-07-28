# SQLite Migration Final Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Feedivo soll für Feed-/Artikelhandling strukturell so nah wie sinnvoll an NetNewsWire liegen: produktiv SQLite-first, ohne produktiven SwiftData-Container, mit nur noch klar isolierten oder entfernten SwiftData-Resten.

**Architecture:** Der produktive App-Start, Feed-/Artikelpfad, Sidebar, Tags, Rules, SmartFolders, Suche und Refresh laufen bereits über SQLite/GRDB. Diese Abschlussphase entfernt oder isoliert die letzten Legacy-/Bridge-Pfade, macht die SwiftData-Bridge standardmäßig aus oder löscht sie, entschlackt `FeedViewModel` und stellt sicher, dass Tests und Dokumentation den echten Zustand zeigen.

**Tech Stack:** Swift 6, SwiftUI macOS, GRDB/SQLite, Swift Testing, Xcode 26, bestehende Stores (`FeedStore`, `ArticleStore`, `ArticleStatusStore`, `TimelineStore`, `TagStore`, `SQLiteRuleStore`, `SQLiteSmartFolderStore`, `FeedFolderStore`).

---

## Aktueller Stand am 2026-07-04

### Effektiv abgeschlossen

- `FeedivoApp` startet produktiv ohne SwiftData-`ModelContainer` und ohne `.modelContainer(...)`.
- Content-/Reader-/ArticleWindow-Routing nutzt SQLite-Views:
  - `SQLiteFeedArticleListView`
  - `SQLiteReaderView`
- Tags laufen im produktiven Pfad über `TagStore`.
- Regeln laufen im produktiven Pfad über `SQLiteRuleStore`.
- SmartFolders und FeedFolders laufen im produktiven Pfad über `SQLiteSmartFolderStore` und `FeedFolderStore`.
- OPML-Import, Feed hinzufügen und First-Run/Empty-State-Flows sind SQLite-first.
- Große SQLite-Performance-Tests existieren und sind in `docs/performance/sqlite-large-dataset-results.md` dokumentiert.
- `SwiftDataBridgeSettings` existiert, die SwiftData-Bridge ist technisch abschaltbar.
- `SQLiteFeedRefreshCoordinator` existiert und kapselt den produktiven SQLite-Refresh für Einzel- und Sammel-Refresh.

### Noch offen

1. `FeedViewModel` ist noch zu groß und enthält weiter Legacy-/Bridge-/SwiftData-Methoden.
2. Die SwiftData-Bridge ist zwar abschaltbar, aber `SwiftDataBridgeSettings.defaultIsEnabled` ist aktuell noch `true`.
3. SwiftData-Modelle, Backfill-Services und `FeedivoModelContainerFactory` existieren noch in der Codebase.
4. Legacy-Views sind isoliert, aber noch als Typealias erreichbar:
   - `ArticleListView = LegacyArticleListView`
   - `ReaderView = LegacyReaderView`
5. Mehrere Tests nutzen noch SwiftData-Container, vor allem alte `FeedViewModelTests` und Legacy-Tests.
6. Die vollständige Test-Suite muss nach der finalen Bereinigung grün laufen.
7. `AGENTS.md`, `FEATURES.md`, `docs/performance/sqlite-only-audit.md` und `docs/performance/netnewswire-feedivo-mechanik-vergleich.md` müssen nach der Abschlussarbeit den finalen Zustand beschreiben.

---

## Zielstatus

Am Ende dieser Arbeit gilt:

- Kein produktiver Codepfad erzeugt oder erwartet einen SwiftData-`ModelContainer`.
- Feed-/Artikelhandling, Feedverwaltung, Artikelstatus, Suche, Tags, Rules, SmartFolders, FeedFolders, OPML und Refresh laufen über SQLite/GRDB.
- Wenn SwiftData-Code noch existiert, dann nur in klar benannten Legacy-Dateien oder Tests, die nicht den produktiven Pfad schützen.
- Die SwiftData-Bridge schreibt standardmäßig nicht mehr zurück.
- `FeedViewModel` ist primär UI-State und delegiert SQLite-Arbeit an Services/Stores.
- Die Tests schützen produktive SQLite-only-Routen.
- Die Dokumentation nennt die verbleibenden Legacy-Reste ehrlich oder bestätigt ihre Entfernung.

---

## Files

### Wahrscheinlich zu ändern

- `Feedivo/ViewModels/FeedViewModel.swift`
  - UI-State behalten.
  - SQLite-Refresh/Add/Delete/OPML an Services delegieren.
  - SwiftData-Legacy-Methoden entfernen oder in klar benannte Legacy-Datei verschieben.

- `Feedivo/Services/SQLiteFeedSubscriptionService.swift`
  - Bridge-Verhalten finalisieren.
  - Standardmäßig keine SwiftData-Bridge mehr schreiben.

- `Feedivo/Services/SwiftDataBridgeSettings.swift`
  - `defaultIsEnabled` auf `false` setzen oder Datei entfernen, wenn Bridge gelöscht wird.

- `Feedivo/App/FeedivoModelContainerFactory.swift`
  - Entfernen, sobald keine produktiven oder notwendigen Tests mehr darauf zugreifen.

- `Feedivo/Services/FeedBackgroundRefreshService.swift`
  - Entfernen oder als Legacy eindeutig aus Build-/Produktpfad lösen.

- `Feedivo/Views/ArticleList/ArticleListView.swift`
  - Typealias entfernen oder Datei zu einem klaren Legacy-Ort verschieben.

- `Feedivo/Views/Reader/ReaderView.swift`
  - Typealias entfernen oder Datei zu einem klaren Legacy-Ort verschieben.

- `FeedivoTests/FeedViewModelTests.swift`
  - SwiftData-lastige Tests auf SQLite-Services verschieben oder Legacy-Tests löschen.

- `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`
  - Source-Guards aktualisieren.
  - Sicherstellen, dass produktive Views/Services keine SwiftData-Rückfälle bekommen.

- `AGENTS.md`
  - Projektgedächtnis nachziehen.

- `FEATURES.md`
  - Migrationsstatus nachziehen.

- `docs/performance/sqlite-only-audit.md`
  - Finalen Audit-Stand nachziehen.

- `docs/performance/swiftdata-blocker-scan-2026-07-04.md`
  - Als historische Momentaufnahme belassen oder mit Abschlussnotiz ergänzen.

- `docs/performance/netnewswire-feedivo-mechanik-vergleich.md`
  - Vergleich aktualisieren: Was Feedivo jetzt gleich/anders macht.

---

## Task 1: Finalen SwiftData-Blocker-Scan ausführen

**Files:**
- Modify: `docs/performance/sqlite-only-audit.md`
- Modify: `docs/performance/swiftdata-blocker-scan-2026-07-04.md`

- [ ] **Step 1: Aktuelle Treffer erfassen**

Run:

```bash
rg -n 'import SwiftData|@Model|@Query|ModelContext|ModelContainer|FetchDescriptor<' Feedivo -g '*.swift'
```

Expected:

- Treffer in Legacy-/Model-/Test-nahen Dateien sind möglich.
- Keine Treffer in `Feedivo/App/FeedivoApp.swift`.
- Keine produktiven `.modelContainer(...)`-Treffer.

- [ ] **Step 2: Produktive Treffer klassifizieren**

Jeden Treffer in eine dieser Gruppen einordnen:

- `remove`: kann jetzt gelöscht werden.
- `legacy-isolate`: darf bleiben, muss aber klar Legacy sein und darf produktiv nicht geroutet werden.
- `test-only`: betrifft nur Tests.
- `model-only`: betrifft alte SwiftData-Modelle, die erst gelöscht werden, wenn alle Kompatibilitätstests umgestellt sind.

- [ ] **Step 3: Audit-Dokument aktualisieren**

In `docs/performance/sqlite-only-audit.md` ergänzen:

```markdown
## Final Closure Scan

Stand: 2026-07-04

- App-Start: SQLite-only, kein produktiver `ModelContainer`.
- Feed-/Artikelproduktpfad: SQLite-only.
- SwiftData-Reste nach dem Scan als konkrete Datei-Liste eintragen:
  - `remove`: Dateien, die gelöscht wurden oder im selben Task gelöscht werden.
  - `legacy-isolate`: Dateien, die bleiben, aber mit Legacy-Kommentar und ohne produktives Routing.
  - `test-only`: Testdateien, die bewusst alte Migrations- oder Kompatibilitätspfade prüfen.
  - `model-only`: alte SwiftData-Modelle, die erst nach Umstellung aller Tests gelöscht werden.

Entscheidung:
SwiftData wird nicht mehr als produktive Persistenzschicht verwendet. Verbleibende
Treffer sind entweder zu entfernen oder als Legacy/Test bewusst isoliert.
```

- [ ] **Step 4: Commit**

Run:

```bash
git add docs/performance/sqlite-only-audit.md docs/performance/swiftdata-blocker-scan-2026-07-04.md
git commit -m "Dokumentiere finalen SwiftData Blocker Scan"
```

Expected: Commit succeeds.

---

## Task 2: SwiftData-Bridge standardmäßig abschalten

**Files:**
- Modify: `Feedivo/Services/SwiftDataBridgeSettings.swift`
- Modify: `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift`
- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

- [ ] **Step 1: Test für neuen Default ergänzen**

In `FeedivoTests/FeedivoAppSceneConfigurationTests.swift` einen Source-Test ergänzen:

```swift
@Test func swiftDataBridgeIstStandardmaessigAusgeschaltet() throws {
    let source = try sourceFile(at: "Feedivo/Services/SwiftDataBridgeSettings.swift")

    #expect(source.contains("static let defaultIsEnabled = false"))
}
```

- [ ] **Step 2: Test ausführen und Fail bestätigen**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/swiftDataBridgeIstStandardmaessigAusgeschaltet
```

Expected: FAIL, solange `defaultIsEnabled = true` ist.

- [ ] **Step 3: Default ändern**

In `Feedivo/Services/SwiftDataBridgeSettings.swift` ändern:

```swift
static let defaultIsEnabled = false
```

Kommentar anpassen:

```swift
/// `false` ist der SQLite-only Standard. `true` darf nur noch für gezielte
/// Legacy-Migrationstests gesetzt werden.
```

- [ ] **Step 4: Tests ausführen**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/swiftDataBridgeIstStandardmaessigAusgeschaltet
```

Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

Run:

```bash
git add Feedivo/Services/SwiftDataBridgeSettings.swift FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift FeedivoTests/FeedivoAppSceneConfigurationTests.swift
git commit -m "Schalte SwiftData Bridge standardmaessig aus"
```

Expected: Commit succeeds.

---

## Task 3: FeedViewModel weiter auf UI-State reduzieren

**Files:**
- Modify: `Feedivo/ViewModels/FeedViewModel.swift`
- Create or Modify: `Feedivo/Services/SQLiteFeedSubscriptionService.swift`
- Create or Modify: `Feedivo/Services/SQLiteFeedRefreshCoordinator.swift`
- Modify: `FeedivoTests/FeedViewModelTests.swift`
- Modify: `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift`
- Modify: `FeedivoTests/SQLiteFeedRefreshCoordinatorTests.swift`

> **Status 2026-07-05 (Commit 3b089bd):** Task 3 ist produktiv umgesetzt.
> `FeedViewModel` ist auf UI-State + Delegation reduziert; die produktive
> OPML-Importvorschau, der produktive `addFeed(urlString:sqliteDatabase:)`-Pfad
> und der Coordinator-Refresh liegen in den SQLite-Services. Verbleibende
> SwiftData-Methoden sind in der `// MARK: - Legacy SwiftData Compatibility`-
> Region isoliert. Die ursprünglich fünf Steps sind unten mit dem erreichten
> Stand abgehakt; die Source-Tests liegen in `FeedivoAppSceneConfigurationTests`.
>
> **Nachtrag 2026-07-05:** `SQLiteFeedActionService` bündelt zusätzlich die
> produktiven Add-/Refresh-/Delete-Serviceaufrufe. `FeedViewModel` ruft diesen
> Service auf und übersetzt nur noch in UI-State.

- [x] **Step 1: Methodengruppen markieren**

`FeedViewModel.swift` trennt seit 3b089bd zwei Regionen:
`// MARK: - Legacy SwiftData Compatibility` für alle Methoden mit
`ModelContext`/`ModelContainer`/`Feed`/`Article` und
`// MARK: - SQLite Feed Actions` für die produktiven SQLite-Pfade.

- [x] **Step 2: Source-Test ergänzen**

`FeedivoTests/FeedivoAppSceneConfigurationTests.swift` enthält die Source-Tests,
die das Delegationsverhalten absichern, u. a.
`feedViewModelProduktiveMethodenDelegierenAnSQLiteServices` und
`feedViewModelDelegiertOPMLPreviewAnSQLiteSubscriptionService` (verhindert
Rückfall der Preview-Logik ins ViewModel).

- [x] **Step 3: Tests ausführen**

`FeedivoTests/FeedViewModelTests`, `SQLiteFeedRefreshCoordinatorTests` und
`SQLiteFeedSubscriptionServiceTests` wurden zum Abschluss von Task 3 grün
ausgeführt (TEST SUCCEEDED).

- [x] **Step 4: Alte FeedViewModelTests bewerten**

Die produktiven Preview-Tests wurden nach `SQLiteFeedSubscriptionServiceTests`
migriert; `FeedViewModelTests` prüft nur noch Delegation/UI-State. Reine
SwiftData-Bridge-Erwartungen wurden gelöscht oder als Legacy gekennzeichnet.

- [x] **Step 5: Commit**

Commit 3b089bd (`Phase 6: FeedViewModel in Services schneiden`) auf `main`
hat diese Reduktion abgeschlossen.

---

## Task 4: Legacy ArticleList/Reader endgültig entscheiden

**Files:**
- Modify or Delete: `Feedivo/Views/ArticleList/ArticleListView.swift`
- Modify or Delete: `Feedivo/Views/Reader/ReaderView.swift`
- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

- [ ] **Step 1: Entscheidung treffen**

Empfohlene Entscheidung:

- Legacy-Dateien vorerst behalten.
- Typealiases entfernen, damit neue produktive Nutzung nicht versehentlich wieder `ArticleListView` oder `ReaderView` anspricht.

- [ ] **Step 2: Typealiases entfernen**

Aus `Feedivo/Views/ArticleList/ArticleListView.swift` entfernen:

```swift
typealias ArticleListView = LegacyArticleListView
```

Aus `Feedivo/Views/Reader/ReaderView.swift` entfernen:

```swift
typealias ReaderView = LegacyReaderView
```

- [ ] **Step 3: Source-Test ergänzen**

In `FeedivoTests/FeedivoAppSceneConfigurationTests.swift` ergänzen:

```swift
@Test func legacyArtikelTypealiasesSindEntfernt() throws {
    let listSource = try sourceFile(at: "Feedivo/Views/ArticleList/ArticleListView.swift")
    let readerSource = try sourceFile(at: "Feedivo/Views/Reader/ReaderView.swift")

    #expect(!listSource.contains("typealias ArticleListView = LegacyArticleListView"))
    #expect(!readerSource.contains("typealias ReaderView = LegacyReaderView"))
}
```

- [ ] **Step 4: Tests ausführen**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/legacyArtikelTypealiasesSindEntfernt -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/legacyArtikelViewsSindNichtMehrProduktRoute
```

Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

Run:

```bash
git add Feedivo/Views/ArticleList/ArticleListView.swift Feedivo/Views/Reader/ReaderView.swift FeedivoTests/FeedivoAppSceneConfigurationTests.swift
git commit -m "Entferne Legacy Reader Typealiases"
```

Expected: Commit succeeds.

---

## Task 5: FeedivoModelContainerFactory und alte SwiftData-App-Helfer entfernen

**Files:**
- Delete: `Feedivo/App/FeedivoModelContainerFactory.swift`
- Delete or Modify: `FeedivoTests/FeedivoModelContainerFactoryTests.swift`
- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

- [ ] **Step 1: Referenzen suchen**

Run:

```bash
rg -n 'FeedivoModelContainerFactory|makePersistentContainer|makeInMemoryFallbackContainer|ModelContainer' Feedivo FeedivoTests -g '*.swift'
```

Expected:

- `FeedivoApp.swift` darf keine Treffer haben.
- Treffer in Tests und Legacy-Dateien müssen bewertet werden.

- [ ] **Step 2: Source-Test ergänzen**

In `FeedivoTests/FeedivoAppSceneConfigurationTests.swift` ergänzen:

```swift
@Test func modelContainerFactoryIstNichtMehrTeilDesProduktcodes() throws {
    let appSource = try sourceFile(at: "Feedivo/App/FeedivoApp.swift")

    #expect(!appSource.contains("FeedivoModelContainerFactory"))
    #expect(!appSource.contains("ModelContainer"))
    #expect(!appSource.contains(".modelContainer("))
}
```

- [ ] **Step 3: Datei löschen**

Run:

```bash
rm Feedivo/App/FeedivoModelContainerFactory.swift
```

Wenn das Xcode-Projekt die Datei noch referenziert, den Eintrag in `Feedivo.xcodeproj/project.pbxproj` entfernen.

- [ ] **Step 4: Tests löschen oder anpassen**

Wenn `FeedivoTests/FeedivoModelContainerFactoryTests.swift` nur noch die alte Factory testet, löschen:

```bash
rm FeedivoTests/FeedivoModelContainerFactoryTests.swift
```

Wenn das Xcode-Projekt die Datei noch referenziert, den Eintrag in `Feedivo.xcodeproj/project.pbxproj` entfernen.

- [ ] **Step 5: Build ausführen**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/modelContainerFactoryIstNichtMehrTeilDesProduktcodes
```

Expected: TEST SUCCEEDED.

- [ ] **Step 6: Commit**

Run:

```bash
git add Feedivo/App/FeedivoModelContainerFactory.swift FeedivoTests/FeedivoModelContainerFactoryTests.swift FeedivoTests/FeedivoAppSceneConfigurationTests.swift Feedivo.xcodeproj/project.pbxproj
git commit -m "Entferne SwiftData ModelContainer Factory"
```

Expected: Commit succeeds. Falls gelöschte Dateien nicht mehr existieren, `git add -A` verwenden.

---

## Task 6: Legacy-Backfills und Legacy-Services isolieren oder entfernen

**Files:**
- Modify or Delete: `Feedivo/Services/FeedBackgroundRefreshService.swift`
- Modify or Delete: `Feedivo/Services/ArticleFeedIDBackfillService.swift`
- Modify or Delete: `Feedivo/Services/FeedTagBackfillService.swift`
- Modify or Delete: `Feedivo/Services/FeedUnreadCountBackfillService.swift`
- Modify or Delete: `Feedivo/Services/OrphanedArticleCleanupService.swift`
- Modify or Delete: `Feedivo/Services/SmartFolderDefaultKeyBackfillService.swift`
- Modify or Delete: `Feedivo/Services/SQLiteAdminDefinitionBackfillService.swift`
- Modify: `FeedivoTests/FeedivoAppSceneConfigurationTests.swift`

- [ ] **Step 1: Produktive Nutzung prüfen**

Run:

```bash
rg -n 'FeedBackgroundRefreshService|ArticleFeedIDBackfillService|FeedTagBackfillService|FeedUnreadCountBackfillService|OrphanedArticleCleanupService|SmartFolderDefaultKeyBackfillService|SQLiteAdminDefinitionBackfillService' Feedivo FeedivoTests -g '*.swift'
```

Expected:

- Kein Aufruf aus `FeedivoApp.swift`.
- Kein Aufruf aus `ContentView.swift`, `SQLiteFeedArticleListView.swift`, `SQLiteReaderView.swift`, `RuleSettingsView.swift`, `SmartFolderSettingsView.swift`, `TagManagerView.swift`.

- [ ] **Step 2: Nicht benötigte Services löschen**

Services löschen, wenn sie weder produktiv noch in sinnvollen Migrationstests gebraucht werden.

Run for each removed file:

```bash
git rm Feedivo/Services/<ServiceName>.swift
```

- [ ] **Step 3: Falls Behalten nötig ist, Legacy markieren**

Wenn ein Service behalten werden muss, am Typ ergänzen:

```swift
@available(*, deprecated, message: "Legacy SwiftData-Migrationspfad. Produktiver Feedivo-Pfad nutzt SQLite.")
```

- [ ] **Step 4: Source-Test ergänzen**

In `FeedivoTests/FeedivoAppSceneConfigurationTests.swift` ergänzen:

```swift
@Test func produktiverAppStartVerwendetKeineLegacySwiftDataBackfills() throws {
    let appSource = try sourceFile(at: "Feedivo/App/FeedivoApp.swift")

    #expect(!appSource.contains("ArticleFeedIDBackfillService"))
    #expect(!appSource.contains("FeedTagBackfillService"))
    #expect(!appSource.contains("FeedUnreadCountBackfillService"))
    #expect(!appSource.contains("SmartFolderDefaultKeyBackfillService"))
    #expect(!appSource.contains("SQLiteAdminDefinitionBackfillService"))
    #expect(!appSource.contains("FeedBackgroundRefreshService"))
}
```

- [ ] **Step 5: Tests ausführen**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoAppSceneConfigurationTests/produktiverAppStartVerwendetKeineLegacySwiftDataBackfills
```

Expected: TEST SUCCEEDED.

- [ ] **Step 6: Commit**

Run:

```bash
git add -A Feedivo/Services FeedivoTests/FeedivoAppSceneConfigurationTests.swift Feedivo.xcodeproj/project.pbxproj
git commit -m "Isoliere alte SwiftData Backfills"
```

Expected: Commit succeeds.

---

## Task 7: Vollständige Test-Suite stabilisieren

**Files:**
- Modify: failing test files only.

- [ ] **Step 1: Volltest laufen lassen**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
```

Expected:

- Finalziel: `TEST SUCCEEDED`.
- Wenn `TEST FAILED`, fehlende Tests einzeln fixen.

- [ ] **Step 2: Failures klassifizieren**

Für jeden Failure:

- Produktiver SQLite-Pfad kaputt: Code fixen.
- Alter SwiftData-Test prüft nicht mehr geltendes Verhalten: Test löschen oder auf SQLite-Service umstellen.
- Performance-Flake: Schwellwert nur nach Messung anpassen, nicht blind.

- [ ] **Step 3: Nach jedem Fix gezielt testen**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/<TestSuiteName>/<testName>
```

Expected: TEST SUCCEEDED.

- [ ] **Step 4: Volltest erneut laufen lassen**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
```

Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

Run:

```bash
git add -A
git restore --staged Feedivo.xcodeproj/project.xcworkspace/xcuserdata/martinfelder.xcuserdatad/UserInterfaceState.xcuserstate || true
git commit -m "Stabilisiere Tests nach SQLite Abschluss"
```

Expected: Commit succeeds and `UserInterfaceState.xcuserstate` is not committed.

---

## Task 8: Projektgedächtnis und NetNewsWire-Vergleich aktualisieren

**Files:**
- Modify: `AGENTS.md`
- Modify: `FEATURES.md`
- Modify: `docs/performance/sqlite-only-audit.md`
- Modify: `docs/performance/netnewswire-feedivo-mechanik-vergleich.md`
- Modify: `docs/superpowers/plans/2026-07-03-netnewswire-sqlite-structure.md`

- [ ] **Step 1: AGENTS.md korrigieren**

`AGENTS.md` muss danach nicht mehr behaupten:

- `FeedivoApp.swift` habe `.modelContainer Setup`.
- `Models/` seien produktive SwiftData-Modelle.
- Sidebar/ContentView nutzten produktiv `@Query`.

Stattdessen dokumentieren:

```markdown
Persistenz: Produktiv SQLite/GRDB. SwiftData ist kein produktiver Feed-/Artikelstore mehr.
FeedivoApp startet ohne SwiftData-ModelContainer.
Verbleibende SwiftData-Dateien sind Legacy-/Migrationsreste oder Tests.
```

- [ ] **Step 2: FEATURES.md aktualisieren**

SQLite-Migration als produktiv abgeschlossen markieren, mit Restnotiz:

```markdown
Status: Produktiver Feed-/Artikelpfad SQLite-first abgeschlossen.
Rest: Legacy-SwiftData-Code ist isoliert oder entfernt; neue Features sollen ausschließlich gegen SQLite-Stores gebaut werden.
```

- [ ] **Step 3: NetNewsWire-Vergleich aktualisieren**

In `docs/performance/netnewswire-feedivo-mechanik-vergleich.md` ergänzen:

```markdown
## Stand nach SQLite Final Closure

Feedivo entspricht NetNewsWire strukturell in den relevanten Feed-/Artikelpunkten:
- Artikelinhalt und Status getrennt.
- Listen laden Snapshots.
- Suche läuft über SQLite/FTS.
- Counts kommen aus SQLite.
- Refresh schreibt in SQLite.

Bewusst anders:
- UI bleibt SwiftUI statt NSTableView, solange Performance-Tests grün bleiben.
- SwiftData-Legacy-Code kann als Migrationshistorie noch im Repo liegen, ist aber nicht produktive Quelle.
```

- [ ] **Step 4: Plan abhaken**

In `docs/superpowers/plans/2026-07-03-netnewswire-sqlite-structure.md` die Phasen 6-9 entsprechend aktualisieren.

- [ ] **Step 5: Commit**

Run:

```bash
git add AGENTS.md FEATURES.md docs/performance/sqlite-only-audit.md docs/performance/netnewswire-feedivo-mechanik-vergleich.md docs/superpowers/plans/2026-07-03-netnewswire-sqlite-structure.md
git commit -m "Aktualisiere SQLite Abschlussdokumentation"
```

Expected: Commit succeeds.

---

## Abschlussprüfung

Run:

```bash
git status --short --branch
rg -n 'import SwiftData|@Model|@Query|ModelContext|ModelContainer|FetchDescriptor<' Feedivo -g '*.swift'
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'
```

Expected:

- `git status` zeigt keine unerwarteten Änderungen außer eventuell lokaler Xcode-UI-State.
- SwiftData-Treffer sind entweder entfernt oder eindeutig Legacy/Test/Model-only dokumentiert.
- `xcodebuild test` endet mit `TEST SUCCEEDED`.

---

## Fortsetzungs-Prompt

Nutze diesen Prompt in einer neuen Session:

```text
Lies zuerst AGENTS.md vollständig und prüfe `git status --short --branch`.

Dann setze bitte den Plan
`docs/superpowers/plans/2026-07-04-sqlite-migration-final-closure.md`
vollständig um.

Wichtig:
- Verwende den Plan task-by-task.
- Mache nach jedem erledigten Task einen eigenen Commit.
- Committe keine Xcode-UserInterfaceState-Dateien.
- Führe nach jedem Task die dort genannten Tests aus.
- Am Ende muss `xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -destination 'platform=macOS'` laufen.
- Aktualisiere AGENTS.md, FEATURES.md und die Performance-Dokumente passend zum finalen Stand.
- Gib mir am Ende einen ausführlichen Bericht: erledigte Tasks, Commits, Tests, verbleibende SwiftData-Treffer und falls etwas nicht abgeschlossen werden konnte, warum.
```
