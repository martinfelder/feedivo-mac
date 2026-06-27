# Code-Review-Followup-Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Konkrete, verhaltenserhaltende Korrektheits- & Robustheits-Fixes aus dem frischen 5-Agenten-Review umsetzen — alle NEU (jenseits der bereits erledigten 66 Funde). Fokus auf Datenhygiene, Concurrency-Sicherheit und die frisch gebaute OPML-Vorschau.

**Architecture:** Reine Bugfixes ohne Architekturänderung. Tasks sind unabhängig commitbar. TDD wo deterministisch möglich; bei rein asyncen Concurrency-Fixen Implementierung + manueller Spot-Check. Alle Änderungen berühren nur Models, ViewModels und den OPML-Controller/Views.

**Tech Stack:** SwiftUI, SwiftData, `@Observable`, Swift Testing (`@Test`/`#expect`/`#require`), async/await, Swift 5.0 (kein Strict-Concurrency). Tests: in-memory `ModelContainer` über alle 9 Modelle.

## Global Constraints

- Kommentare im Code auf Deutsch (CLAUDE.md).
- Keine nutzer­sichtbare Verhaltensänderung außer dem jeweils behobenen Bug.
- SwiftData-`@Model`-Properties bleiben Optional-oder-Default (CloudKit-Blocker B1).
- `NavigationView` deprecated → nicht verwenden.
- Neue `.swift`-Dateien auto-inkludiert via `PBXFileSystemSynchronizedRootGroup` → **kein `.pbxproj`-Edit**.
- Build-Test-Befehl (seriell): `xcodebuild -scheme Feedivo -destination 'platform=macOS' build` und `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests test`.
- xcstrings nicht anfassen in diesem Plan (L10n → separater Plan).
- Bestehende Test-Helper: jeder Test baut einen in-memory Container `ModelContainer(for: Feed.self, Article.self, Tag.self, Rule.self, RuleCondition.self, [SmartFolder.self, SmartFolderCondition.self,] FeedLogEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))` + `ModelContext(container)` + `ViewModel()` (siehe `RuleViewModelTests.swift`/`SmartFolderViewModelTests.swift`).

---

## File Structure

- **Modify** `Feedivo/ViewModels/RuleViewModel.swift` — `updateRule`: alte Conditions manuell löschen (T1).
- **Modify** `Feedivo/ViewModels/SmartFolderViewModel.swift` — `updateFolder`: alte Conditions manuell löschen (T1).
- **Modify** `FeedivoTests/RuleViewModelTests.swift` — Orphan-Test (T1).
- **Modify** `FeedivoTests/SmartFolderViewModelTests.swift` — Orphan-Test (T1).
- **Modify** `Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift` — `previewTask`-Handle + cancel in `loadOPML`/`preparePreview`/`reset` (T2); `selectedFileName` reset (T7); `applyToggleSelectionToRows()` (T7).
- **Modify** `Feedivo/Views/OPMLImport/OPMLImportReviewView.swift` — Datei-Picker `.disabled(isPreparingPreview)` (T2); onChange-Block durch Controller-Methode ersetzen (T7).
- **Modify** `Feedivo/Views/FirstRun/FirstRunWizardView.swift` — onChange-Block durch Controller-Methode ersetzen (T7).
- **Modify** `Feedivo/Views/OPMLImport/OPMLImportFeedRow.swift` — „Ohne Ordner"-Sentinel → leerer String; Accessibility-Labels (T7).
- **Modify** `FeedivoTests/OPMLImportPreviewControllerTests.swift` — Cancel/Reset-/Sentinel-/Toggle-Tests (T2, T7).
- **Modify** `Feedivo/ViewModels/FeedViewModel.swift` — `unreadIncrement`-Helper (T3); `addFeed`-Guard (T4); `opmlImportPreviewRows` parallelisieren (T5).
- **Modify** `FeedivoTests/FeedViewModelTests.swift` — Tests für T3, T4, T5.
- **Modify** `Feedivo/Models/RuleCondition.swift` — typsicherer Getter (T6).
- **Modify** `Feedivo/Models/SmartFolderCondition.swift` — typsicherer Getter (T6).
- **Modify** Engine-Konsum-Stellen — Getter nutzen (T6, siehe Task).

---

## Task 1: Verwaiste Conditions bei `updateRule`/`updateFolder` löschen

**Files:**
- Modify: `Feedivo/ViewModels/RuleViewModel.swift:174-182` (`updateRule`)
- Modify: `Feedivo/ViewModels/SmartFolderViewModel.swift:102-103` (`updateFolder`)
- Modify: `FeedivoTests/RuleViewModelTests.swift` (Test anfügen)
- Modify: `FeedivoTests/SmartFolderViewModelTests.swift` (Test anfügen)

**Interfaces:** keine neuen öffentlichen Signaturen.

**Hintergrund:** `Rule.conditions` und `SmartFolder.conditions` haben `deleteRule: .nullify` (B2). `updateRule`/`updateFolder` machen `conditions.removeAll()` — bei `.nullify` werden die alten Condition-Objekte nur verwaist (`rule = nil`), nicht gelöscht. `deleteRule`/`deleteFolder` löschen korrekt manuell. Update häuft also Orphans.

- [ ] **Step 1: Failing Test für RuleViewModel**

Ans Ende von `RuleViewModelTests` (neue `@Test`-Methode in der bestehenden `struct`):

```swift
@MainActor
@Test func updateRuleLoeschtAlteConditionsStattSieZuVerwaisten() throws {
    let container = try ModelContainer(
        for: Feed.self, Article.self, Tag.self, Rule.self,
        RuleCondition.self, FeedLogEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let tag = Tag(name: "Swift", colorHex: "#3B82F6")
    context.insert(tag)
    let viewModel = RuleViewModel()

    viewModel.createRule(
        name: "Alt",
        isEnabled: true,
        matchMode: .all,
        conditionDrafts: [
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "A"),
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "B")
        ],
        assignTag: tag,
        context: context
    )
    let rule = try #require(context.fetch(FetchDescriptor<Rule>()).first)

    viewModel.updateRule(
        rule,
        name: "Neu",
        isEnabled: true,
        matchMode: .all,
        conditionDrafts: [
            RuleConditionDraft(field: .title, conditionOperator: .contains, value: "C")
        ],
        assignTag: tag,
        context: context
    )

    // .nullify würde 2 Orphans + 1 neue = 3 hinterlassen; korrekt ist nur die 1 neue.
    let allConditions = try context.fetch(FetchDescriptor<RuleCondition>())
    #expect(allConditions.count == 1)
    #expect(rule.conditions.count == 1)
    #expect(allConditions.first?.rule != nil)
}
```

- [ ] **Step 2: Failing Test für SmartFolderViewModel**

Ans Ende von `SmartFolderViewModelTests`:

```swift
@MainActor
@Test func updateFolderLoeschtAlteConditionsStattSieZuVerwaisten() throws {
    let container = try ModelContainer(
        for: Feed.self, Article.self, Tag.self, Rule.self, RuleCondition.self,
        SmartFolder.self, SmartFolderCondition.self, FeedLogEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let viewModel = SmartFolderViewModel()

    viewModel.createFolder(
        name: "Alt",
        matchMode: .all,
        isShownInSidebar: true,
        iconName: "tray",
        colorHex: "#3B82F6",
        conditionDrafts: [
            SmartFolderConditionDraft(field: .title, conditionOperator: .contains, value: "A"),
            SmartFolderConditionDraft(field: .title, conditionOperator: .contains, value: "B")
        ],
        existingFolders: [],
        context: context
    )
    let folder = try #require(context.fetch(FetchDescriptor<SmartFolder>()).first)

    viewModel.updateFolder(
        folder,
        name: "Neu",
        matchMode: .all,
        isShownInSidebar: true,
        iconName: "tray",
        colorHex: "#3B82F6",
        conditionDrafts: [
            SmartFolderConditionDraft(field: .title, conditionOperator: .contains, value: "C")
        ],
        context: context
    )

    let allConditions = try context.fetch(FetchDescriptor<SmartFolderCondition>())
    #expect(allConditions.count == 1)
    #expect(folder.conditions.count == 1)
    #expect(allConditions.first?.smartFolder != nil)
}
```

- [ ] **Step 3: Tests laufen lassen → RED**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests-red test 2>&1 | grep -E "LoeschtAlteConditions|TEST"`
Expected: beide Tests FAIL (Rule: 3 statt 1; SmartFolder: 3 statt 1).

- [ ] **Step 4: `RuleViewModel.updateRule` fixen (GREEN)**

In `Feedivo/ViewModels/RuleViewModel.swift` die Zeile `rule.conditions.removeAll()` (Z. 174) ersetzen durch manuelles Löschen:

```swift
        // .nullify statt .cascade (CloudKit-kompatibel): removeAll würde die
        // alten Conditions nur verwaisten lassen — deshalb manuell löschen,
        // analog deleteRule.
        for condition in Array(rule.conditions) {
            context.delete(condition)
        }
        rule.conditions = conditions.enumerated().map { index, condition in
            RuleCondition(
                field: condition.field,
                conditionOperator: condition.conditionOperator,
                value: condition.value,
                sortOrder: index
            )
        }
```

- [ ] **Step 5: `SmartFolderViewModel.updateFolder` fixen (GREEN)**

In `Feedivo/ViewModels/SmartFolderViewModel.swift` die Zeile `folder.conditions.removeAll()` (Z. 102) ersetzen:

```swift
        // .nullify statt .cascade (CloudKit-kompatibel): removeAll würde die
        // alten Conditions nur verwaisten lassen — deshalb manuell löschen,
        // analog deleteFolder.
        for condition in Array(folder.conditions) {
            context.delete(condition)
        }
        folder.conditions = conditions
```

- [ ] **Step 6: Tests + Build → GREEN**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests test 2>&1 | grep -E "LoeschtAlteConditions|TEST SUCCEEDED"`
Expected: beide Tests PASS, `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/ViewModels/RuleViewModel.swift Feedivo/ViewModels/SmartFolderViewModel.swift FeedivoTests/RuleViewModelTests.swift FeedivoTests/SmartFolderViewModelTests.swift
git commit -m "$(cat <<'EOF'
Review-Followup: verwaiste Conditions bei updateRule/updateFolder löschen

Conditions haben deleteRule:.nullify (B2). removeAll() verwaiste die alten
Condition-Objekte nur — bei jeder Regel-/Ordnerbearbeitung häuften sie sich
in der DB. Jetzt manuell context.delete wie bei deleteRule/deleteFolder.
Zwei Orphan-Count-Tests ergänzt.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: OPML-Vorschau-Task abbruchbar machen + UI sperren

**Files:**
- Modify: `Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift` (`loadOPML`:226-264, `preparePreview`:267-289, `reset`:204-218)
- Modify: `Feedivo/Views/OPMLImport/OPMLImportReviewView.swift:214-217` (Datei-Picker-Button)
- Modify: `FeedivoTests/OPMLImportPreviewControllerTests.swift` (Test anfügen)

**Hintergrund:** `loadOPML`/`preparePreview` starten `Task { @MainActor in … }` fire-and-forget — Handle nicht gespeichert, nicht kündbar. `OPMLImportReviewView` sperrt „Datei auswählen"/`.onDrop` während `isPreparingPreview` nicht (FirstRunWizardView tut es). Zweite Datei während laufender Vorschau → konkurrierende Tasks überschreiben State.

- [ ] **Step 1: Failing Test**

Ans Ende von `OPMLImportPreviewControllerTests`:

```swift
@Test func resetBrichtLaufendenPreviewAbUndSetztStateZurueck() async {
    let controller = OPMLImportPreviewController()
    controller.isPreparingPreview = true
    controller.rows = [makeRow(title: "A", xmlURL: "https://a.example.com/feed.xml", status: .available, isSelected: true)]
    controller.sourceDescription = "Zwischenstand"
    controller.previewProgressText = "Zwischenstand"

    controller.reset()

    #expect(controller.isPreparingPreview == false)
    #expect(controller.rows == [])
    // Task-Handle ist nach reset wieder nil (kein aktiver Preview).
    #expect(controller.previewTask == nil)
}
```

- [ ] **Step 2: Test laufen lassen → RED**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests-red test 2>&1 | grep -E "BrichtLaufenden|TEST"`
Expected: FAIL — „'previewTask' does not exist" (Compiler-Fehler).

- [ ] **Step 3: Controller um Task-Handle + Cancel erweitern**

In `OPMLImportPreviewController.swift`:

a) Property ergänzen (bei den `private(set)` Display-Props, ~Z. 114):
```swift
    private(set) var previewTask: Task<Void, Never>?
```

b) `reset()` (Z. 204) am Anfang canceln:
```swift
    func reset() {
        previewTask?.cancel()
        previewTask = nil
        rows = []
        // …bestehende Zeilen bleiben unverändert…
```

c) `loadOPML` (Z. 222) — Task-Handle speichern + auf Cancel prüfen. Funktionsrumpf beginnt statt `Task { @MainActor in`:
```swift
    func loadOPML(from result: Result<URL, Error>, existingFeeds: [Feed], feedViewModel: FeedViewModel) {
        previewTask?.cancel()
        let task = Task { @MainActor in
            defer { if previewTask === Task { self.previewTask = nil } }
            do {
                let url = try result.get()
                let canAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if canAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                selectedFileName = url.lastPathComponent
                sourceDescription = "Datei wird gelesen..."
                previewProgressText = "OPML-Datei wird gelesen und vorbereitet."
                errorMessage = nil
                resultMessage = nil
                rows = []
                isPreparingPreview = true

                let data = try Data(contentsOf: url)
                let opmlFeeds = try OPMLService.parseFeeds(from: data)
                try Task.checkCancellation()
                sourceDescription = "\(opmlFeeds.count) Feeds erkannt. Feed-Adressen werden geprüft..."
                previewProgressText = "\(opmlFeeds.count) Feeds erkannt. Prüfung startet..."
                rows = await feedViewModel.opmlImportPreviewRows(
                    for: opmlFeeds,
                    existingFeeds: existingFeeds,
                    onProgress: { progress in
                        self.previewProgressText = progress.displayText
                        self.sourceDescription = progress.displayText
                    }
                )
                guard !Task.isCancelled else { return }
                sourceDescription = "\(rows.count) Feeds erkannt · \(Set(rows.map { trimmedFolderName($0.feed.folderName) ?? "Ohne Ordner" }).count) Ordner · \(url.lastPathComponent)"
                previewProgressText = "Prüfung abgeschlossen."
                isPreparingPreview = false
            } catch is CancellationError {
                isPreparingPreview = false
                rows = []
            } catch {
                isPreparingPreview = false
                rows = []
                errorMessage = error.localizedDescription
                sourceDescription = "Die Datei konnte nicht gelesen werden."
                previewProgressText = "Die Datei konnte nicht gelesen werden."
            }
        }
        previewTask = task
    }
```

d) `preparePreview` (Z. 267) analog — Task-Handle speichern + Cancel-Check vor `isPreparingPreview = false`:
```swift
    func preparePreview(feeds: [OPMLFeed], existingFeeds: [Feed], feedViewModel: FeedViewModel, sourceText: String) {
        previewTask?.cancel()
        let task = Task { @MainActor in
            defer { if previewTask === Task { self.previewTask = nil } }
            errorMessage = nil
            resultMessage = nil
            rows = []
            sourceDescription = sourceText
            previewProgressText = sourceText
            isPreparingPreview = true

            rows = await feedViewModel.opmlImportPreviewRows(
                for: feeds,
                existingFeeds: existingFeeds,
                onProgress: { progress in
                    self.previewProgressText = progress.displayText
                    self.sourceDescription = progress.displayText
                }
            )
            guard !Task.isCancelled else { return }
            sourceDescription = "\(rows.count) Feeds geprüft."
            previewProgressText = "Prüfung abgeschlossen."
            isPreparingPreview = false
        }
        previewTask = task
    }
```

- [ ] **Step 4: UI — Datei-Picker während Vorschau sperren**

In `OPMLImportReviewView.swift` den „Datei auswählen..."-Button (Z. 214-217) um `.disabled` ergänzen:
```swift
            Button("Datei auswählen...") {
                previewController.isFileImporterPresented = true
            }
            .buttonStyle(OPMLSecondaryButtonStyle())
            .disabled(previewController.isPreparingPreview)
```

(Drop-Pfad bleibt aktiv, aber `handleDroppedFiles` → `loadOPML` cancelt nun den laufenden Task — kein konkurrierender State mehr.)

- [ ] **Step 5: Tests + Build → GREEN**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests test 2>&1 | grep -E "BrichtLaufenden|TEST SUCCEEDED"`
Expected: Test PASS, `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift Feedivo/Views/OPMLImport/OPMLImportReviewView.swift FeedivoTests/OPMLImportPreviewControllerTests.swift
git commit -m "$(cat <<'EOF'
Review-Followup: OPML-Vorschau-Task abbruchbar + UI sperren

loadOPML/preparePreview starteten fire-and-forget Tasks ohne Handle — eine
während laufender Vorschau gewählte/zugefallene zweite Datei ließ zwei Tasks
um rows/sourceDescription konkurrieren. Jetzt: previewTask-Handle speichern,
vor jedem Start + in reset canceln, in der Closure auf Task.isCancelled/
CancellationError prüfen. Datei-Picker im Import-Sheet während Vorschau gesperrt.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `Feed.unreadCount`-Increment konsistent mit `isRead` filtern

**Files:**
- Modify: `Feedivo/ViewModels/FeedViewModel.swift:785`
- Modify: `FeedivoTests/FeedViewModelTests.swift` (Test anfügen)

**Hintergrund:** `FeedViewModel.swift:785` zählt `newArticleObjects.filter { !$0.isHidden }.count` — inkonsistent zum Add-Pfad (`:400` `filter { !$0.isRead && !$0.isHidden }`). Heute latent (neue Artikel sind `isRead=false`), bricht sobald je ein neuer Artikel `isRead=true` importiert wird.

- [ ] **Step 1: Failing Test**

Ans Ende von `FeedViewModelTests` (die Helper für Container/FeedViewModel siehe bestehende Tests):

```swift
@MainActor
@Test func unreadIncrementZaehltKeineGelesenenOderVerstecktenArtikel() throws {
    let container = try ModelContainer(
        for: Feed.self, Article.self, Tag.self, Rule.self,
        RuleCondition.self, FeedLogEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let viewModel = FeedViewModel()

    let readArticle = Article(title: "Gelesen")
    readArticle.isRead = true
    let hiddenArticle = Article(title: "Versteckt")
    hiddenArticle.isHidden = true
    let freshArticle = Article(title: "Neu")

    #expect(viewModel.unreadIncrement(for: [readArticle, hiddenArticle, freshArticle]) == 1)
}
```

- [ ] **Step 2: Test laufen lassen → RED**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests-red test 2>&1 | grep -E "unreadIncrement|TEST"`
Expected: FAIL — „'unreadIncrement' does not exist".

- [ ] **Step 3: Helper extrahieren + verwenden (GREEN)**

In `FeedViewModel.swift` die Zeile 785 (`feed.unreadCount += newArticleObjects.filter { !$0.isHidden }.count`) ersetzen:
```swift
        feed.unreadCount += Self.unreadIncrement(for: newArticleObjects)
```

Und als `static func` ergänzen (z.B. direkt unter `refreshFeedContents`):
```swift
    /// Anzahl neuer Artikel, die den Ungelesen-Zähler erhöhen: nur nicht
    /// gelesene UND nicht versteckte. Konsistent zum addFeed-Pfad
    /// (Z. 400) — verhindert Drift, sobald jemals Artikel mit isRead=true
    /// importiert oder per Regel gelesen markiert werden.
    static func unreadIncrement(for articles: [Article]) -> Int {
        articles.filter { !$0.isRead && !$0.isHidden }.count
    }
```

- [ ] **Step 4: Tests + Build → GREEN**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests test 2>&1 | grep -E "unreadIncrement|TEST SUCCEEDED"`
Expected: PASS, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/ViewModels/FeedViewModel.swift FeedivoTests/FeedViewModelTests.swift
git commit -m "$(cat <<'EOF'
Review-Followup: Feed.unreadCount-Increment konsistent mit isRead filtern

refreshFeedContents zählte neue Artikel nur nach !isHidden; der addFeed-Pfad
filtert !isRead && !isHidden. Latente Divergenz — sobald je ein neuer Artikel
mit isRead=true importiert/gelesen markiert wird, driftet unreadCount nach
oben. Beide Pfade nutzen jetzt die geteilte static unreadIncrement(for:).

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `addFeed` mit `!isLoading`-Reentrancy-Guard

**Files:**
- Modify: `Feedivo/ViewModels/FeedViewModel.swift:350-357` (`addFeed`)
- Modify: `FeedivoTests/FeedViewModelTests.swift` (Test anfügen)

**Hintergrund:** `refreshFeed`/`refreshAllFeeds`/`importOPMLFeeds` prüfen `guard !isLoading`. `addFeed` nicht → überschreibt `isLoading` bei parallelem Hintergrund-Refresh.

- [ ] **Step 1: Failing Test**

Ans Ende von `FeedViewModelTests`:

```swift
@MainActor
@Test func addFeedLehntAbWennBereitsEinLaufenderRefreshAktivIst() async throws {
    let container = try ModelContainer(
        for: Feed.self, Article.self, Tag.self, Rule.self,
        RuleCondition.self, FeedLogEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let viewModel = FeedViewModel()
    viewModel.isLoading = true  // simuliert laufenden Hintergrund-Refresh

    await viewModel.addFeed(urlString: "https://example.com/feed.xml", context: context)

    // Guard triggert: kein Fetch, Fehlermeldung gesetzt, isLoading bleibt true.
    #expect(viewModel.errorMessage == L10n.feedErrorAlreadyRunning)
    #expect(try context.fetch(FetchDescriptor<Feed>()).count == 0)
}
```

- [ ] **Step 2: Test laufen lassen → RED**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests-red test 2>&1 | grep -E "LehntAbWenn|TEST"`
Expected: FAIL — Guard fehlt, Test hängt oder `errorMessage != alreadyRunning`.

- [ ] **Step 3: Guard einbauen (GREEN)**

In `FeedViewModel.swift` `addFeed` (Z. 350) direkt nach der ersten Zeile den Guard ergänzen:
```swift
    func addFeed(urlString: String, context: ModelContext) async {
        let cleanedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedURL.isEmpty else {
            errorMessage = L10n.feedErrorEmptyURL
            return
        }

        // Reentrancy-Guard — konsistent mit refreshFeed/refreshAllFeeds/importOPMLFeeds:
        // ein parallel laufender Refresh würde sonst isLoading überschreiben und die
        // UI fälschlich „nicht lädt" zeigen, während der Hintergrund-Refresh weiterläuft.
        guard !isLoading else {
            errorMessage = L10n.feedErrorAlreadyRunning
            return
        }

        isLoading = true
        errorMessage = nil
        // …bestehender Rumpf ab `do {` bleibt unverändert bis `isLoading = false`…
```

- [ ] **Step 4: Tests + Build → GREEN**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests test 2>&1 | grep -E "LehntAbWenn|TEST SUCCEEDED"`
Expected: PASS, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/ViewModels/FeedViewModel.swift FeedivoTests/FeedViewModelTests.swift
git commit -m "$(cat <<'EOF'
Review-Followup: addFeed mit !isLoading-Reentrancy-Guard

refreshFeed/refreshAllFeeds/importOPMLFeeds hatten den Guard, addFeed nicht.
Paralleles Feed-Hinzufügen während Hintergrund-Refresh überschrieb isLoading
→ UI zeigte „nicht lädt", während Refresh weiterlief. Konsistenter Guard.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `opmlImportPreviewRows` parallelisieren

**Files:**
- Modify: `Feedivo/ViewModels/FeedViewModel.swift:107-159` (`opmlImportPreviewRows`)
- Modify: `FeedivoTests/FeedViewModelTests.swift` (Test anfügen)

**Hintergrund:** Die Vorschau ruft `fetchFeed` seriell in einer `for`-Schleife auf; `importOPMLFeeds` paralleliert denselben Abruf über `feedBatches`+`withTaskGroup`. Bei großen OPML-Imports (50–200 Feeds) blockt die Vorschau Minuten. Ergebnis (Reihenfolge/Status) muss erhalten bleiben.

**Interfaces:**
- Consumes: `FeedViewModel.feedBatches(from:)` (Z. 560, `private`), `fetchFeed(_:)`, `normalizedFeedURL(_:)`.
- Produces: unveränderte Signatur `opmlImportPreviewRows(for:existingFeeds:onProgress:)`.

- [ ] **Step 1: Charakterisierungs-Test (behält Reihenfolge/Status)**

Ans Ende von `FeedViewModelTests`. Verwendet einen FeedViewModel mit injiziertem `fetchFeed`-Doppel, das ohne Netzwerk antwortet (das Test-Setup mit Closure-Injektion ist im bestehenden `FeedViewModelTests`-Konstruktor etabliert — die Closures sind `addFeed`/`fetchFeed`/`enrichArticleImages`/`notifyFeedRefresh`/`notifyRuleNotifications`/`articleRetentionDefaults`; siehe Test-Datei). Wenn der Konstruktor in Tests bereits genutzt wird, das Muster übernehmen; sonst mit `fetchFeed`-Closure, die einen ParsedFeed zurückgibt.

```swift
@MainActor
@Test func opmlImportPreviewRowsParalleelisiertBehaeltReihenfolgeUndStatus() async throws {
    // fetchFeed-Doppel: "fail://" → unreachable, sonst available.
    let viewModel = FeedViewModel(
        fetchFeed: { urlString in
            if urlString.hasPrefix("fail://") {
                throw FeedServiceError.parsingFailed
            }
            return ParsedFeed(title: urlString, sourceURL: urlString, siteURL: nil,
                              description: nil, articles: [])
        },
        addFeed: { _, _ in },
        enrichArticleImages: { articles in articles },
        notifyFeedRefresh: { _ in },
        notifyRuleNotifications: { _ in },
        articleRetentionDefaults: ArticleRetentionSettings.globalDefaults
    )
    let opmlFeeds = (1...6).map { i in
        OPMLFeed(title: "F\(i)", xmlURL: "https://f\(i).example.com/feed.xml",
                 htmlURL: nil, folderName: nil)
    }
    // Einer unreachable, Rest available — Status muss pro Zeile stimmen.
    opmlFeeds[2].xmlURL = "fail://broken"

    let rows = await viewModel.opmlImportPreviewRows(for: opmlFeeds, existingFeeds: [])

    #expect(rows.count == 6)
    #expect(rows.map(\.feed.title) == ["F1","F2","F3","F4","F5","F6"])
    #expect(rows[0].status == .available)
    #expect(rows[1].status == .available)
    #expect(rows[2].status == .unreachable)
    #expect(rows[3].status == .available)
    #expect(rows.allSatisfy { $0.status != .duplicate })
}
```

> Falls die Closure-Parameter-Namen im `FeedViewModel`-Konstruktor abweichen, diese aus dem bestehenden `FeedViewModelTests`-Setup übernehmen (dort ist das etablierte Injektionsmuster zu sehen).

- [ ] **Step 2: Test läuft (Charakterisierung des IST-Verhaltens) → sollte bereits GRÜN sein**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests test 2>&1 | grep -E "Paralleelisiert|TEST SUCCEEDED"`
Expected: PASS (Test beschreibt aktuelles serielles Verhalten; schützt vor Regression durch die Parallelisierung).

- [ ] **Step 3: Implementierung parallelisieren**

`FeedViewModel.swift` `opmlImportPreviewRows` (Z. 107-159) ersetzen — Dedup-Phase bleibt sequenziell (URL-Set darf nicht concurrent mutiert werden), Abruf parallel in Batches; Ergebnisse in Original-Reihenfolge einsortieren:

```swift
    @MainActor
    func opmlImportPreviewRows(
        for opmlFeeds: [OPMLFeed],
        existingFeeds: [Feed],
        onProgress: ((OPMLImportPreviewProgress) -> Void)? = nil
    ) async -> [OPMLImportPreviewRow] {
        var knownFeedURLs = Set(existingFeeds.map { normalizedFeedURL($0.url) })

        // Phase 1 — sequenziell: Duplikat-Status feststellen (URL-Set darf nicht
        // concurrent mutiert werden) und Abruf-Bedarf ermitteln.
        struct PendingFeed {
            let index: Int
            let opmlFeed: OPMLFeed
            let isDuplicate: Bool
            let cleanedURL: String
        }
        var pending: [PendingFeed] = []
        var rowsByIndex = Array<OPMLImportPreviewRow?>(repeating: nil, count: opmlFeeds.count)

        for (index, opmlFeed) in opmlFeeds.enumerated() {
            onProgress?(
                OPMLImportPreviewProgress(
                    currentFeedTitle: opmlFeed.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    currentIndex: index + 1,
                    totalCount: opmlFeeds.count
                )
            )
            let cleanedURL = opmlFeed.xmlURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedURL = normalizedFeedURL(cleanedURL)
            let isDuplicate = !knownFeedURLs.insert(normalizedURL).inserted

            if isDuplicate {
                rowsByIndex[index] = OPMLImportPreviewRow(feed: opmlFeed, status: .duplicate, isSelected: false)
            } else {
                pending.append(PendingFeed(index: index, opmlFeed: opmlFeed, isDuplicate: false, cleanedURL: cleanedURL))
            }
        }

        // Phase 2 — parallel: Erreichbarkeit prüfen, in begrenzten Gruppen
        // (gleiche Drosselung wie importOPMLFeeds). Ergebnisse indexiert zurück,
        // damit die Original-Reihenfolge erhalten bleibt.
        let pendingBatches = feedBatches(from: pending)
        for batch in pendingBatches {
            await withTaskGroup(of: (Int, OPMLImportFeedStatus).self) { group in
                for item in batch {
                    group.addTask { @MainActor in
                        do {
                            _ = try await self.fetchFeed(item.cleanedURL)
                            return (item.index, .available)
                        } catch {
                            return (item.index, .unreachable)
                        }
                    }
                }
                for await (index, status) in group {
                    let isSelected = (status == .available)
                    rowsByIndex[index] = OPMLImportPreviewRow(
                        feed: item.opmlFeed, status: status, isSelected: isSelected
                    )
                    // Fortschritts-Text pro abgeschlossenem Abruf.
                    let done = rowsByIndex.compactMap { $0 }.count
                    onProgress?(OPMLImportPreviewProgress(
                        currentFeedTitle: opmlFeeds[index].title.trimmingCharacters(in: .whitespacesAndNewlines),
                        currentIndex: done,
                        totalCount: opmlFeeds.count
                    ))
                }
            }
        }

        return rowsByIndex.compactMap { $0 }
    }
```

> `feedBatches(from:)` ist aktuell `[Feed]`-typisiert; für die Wiederverwendung mit `PendingFeed` entweder `feedBatches` generisch machen (`func feedBatches<T>(from items: [T]) -> [[T]]` — nur Chunking, kein Feed-Wissen) oder eine lokale `chunked`-Helfer-Funktion im Methoden-Scope verwenden. Die generische Variante ist vorzuziehen (DRY). Wenn `feedBatches` Feed-spezifische Logik enthält, stattdessen lokale Helfer:
```swift
        func chunked<T>(_ items: [T], size: Int = 6) -> [[T]] {
            stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0+size, items.count)]) }
        }
```

- [ ] **Step 4: Tests + Build → GREEN**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests test 2>&1 | grep -E "Paralleelisiert|opmlImportPreview|TEST SUCCEEDED"`
Expected: Charakterisierungs-Test PASS (Reihenfolge/Status identisch), `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/ViewModels/FeedViewModel.swift FeedivoTests/FeedViewModelTests.swift
git commit -m "$(cat <<'EOF'
Review-Followup: opmlImportPreviewRows paralleisiert (feedBatches)

Die Vorschau rief fetchFeed seriell auf; importOPMLFeeds parallelt denselben
Abruf bereits gedrosselt. Bei 50-200 Feeds blockte die Vorschau Minuten.
Jetzt: Duplikat-Phase sequenziell (URL-Set), Abruf parallel in Batches mit
withTaskGroup, Ergebnisse indexiert in Original-Reihenfolge einsortiert.
Charakterisierungs-Test schützt Reihenfolge/Status.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Typsichere Getter für `RuleCondition`/`SmartFolderCondition`

**Files:**
- Modify: `Feedivo/Models/RuleCondition.swift`
- Modify: `Feedivo/Models/SmartFolderCondition.swift`
- Modify: `FeedivoTests/RuleConditionTests.swift` (neu oder ergänzt) + `FeedivoTests/SmartFolderConditionTests.swift`
- Modify: Konsum-Stellen (siehe unten)

**Hintergrund:** `RuleCondition.field`/`conditionOperator` und `SmartFolderCondition.fieldRaw`/`operatorRaw` sind rohe `String = ""`. Ungültige Werte persistieren still und matchen einfach nicht mehr — kein Fehler, kein Log. `SmartFolderViewModel.duplicateFolder` hat bereits das `?? .title`/`?? .contains`-Fallback-Muster; das soll der verpflichtende Getter werden.

- [ ] **Step 1: Failing Tests**

`FeedivoTests/RuleConditionTests.swift`:
```swift
import Foundation
import SwiftData
import Testing
@testable import Feedivo

@MainActor
struct RuleConditionTests {
    @Test func fieldEnumLiefertNilFuerUnbekanntenRawValue() {
        let condition = RuleCondition(field: "titel", conditionOperator: "contains", value: "x")
        #expect(condition.fieldEnum == nil)
    }

    @Test func fieldEnumLiefertEnumFuerBekanntenRawValue() {
        let condition = RuleCondition(field: RuleConditionField.title.rawValue,
                                       conditionOperator: RuleConditionOperator.contains.rawValue,
                                       value: "x")
        #expect(condition.fieldEnum == .title)
        #expect(condition.operatorEnum == .contains)
    }
}
```

`FeedivoTests/SmartFolderConditionTests.swift` analog:
```swift
@MainActor
struct SmartFolderConditionTests {
    @Test func fieldEnumLiefertNilFuerUnbekanntenRawValue() {
        let condition = SmartFolderCondition(field: .title, conditionOperator: .contains, value: "x")
        condition.fieldRaw = "unbekannt"
        #expect(condition.fieldEnum == nil)
    }

    @Test func fieldEnumLiefertEnumFuerBekanntenRawValue() {
        let condition = SmartFolderCondition(field: .status, conditionOperator: .is,
                                              value: SmartFolderStatusValue.unread.rawValue)
        #expect(condition.fieldEnum == .status)
        #expect(condition.operatorEnum == .is)
    }
}
```

- [ ] **Step 2: Tests laufen lassen → RED**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests-red test 2>&1 | grep -E "fieldEnum|TEST"`
Expected: FAIL — „'fieldEnum' does not exist".

- [ ] **Step 3: Getter ergänzen (GREEN)**

`RuleCondition.swift` ergänzen:
```swift
    // Typsicherer Zugriff — ungültige Raw-Values (z.B. nach Refactor verwaist)
    // fallen hier früh auf nil statt still zu matchen.
    var fieldEnum: RuleConditionField? { RuleConditionField(rawValue: field) }
    var operatorEnum: RuleConditionOperator? { RuleConditionOperator(rawValue: conditionOperator) }
```

`SmartFolderCondition.swift` ergänzen:
```swift
    var fieldEnum: SmartFolderConditionField? { SmartFolderConditionField(rawValue: fieldRaw) }
    var operatorEnum: SmartFolderConditionOperator? { SmartFolderConditionOperator(rawValue: operatorRaw) }
```

- [ ] **Step 4: Konsum-Stellen auf Getter umstellen**

Stellen, die roh `RuleConditionField(rawValue: condition.field)` / `SmartFolderConditionField(rawValue: condition.fieldRaw)` lesen, auf `fieldEnum`/`operatorEnum` umstellen. Suchen: `grep -rn "rawValue: condition.field\|rawValue: condition.fieldRaw\|rawValue: condition.operatorRaw\|rawValue: condition.conditionOperator" Feedivo/`. Die `SmartFolderViewModel.duplicateFolder`-Zeile 117/118 zu:
```swift
                field: condition.fieldEnum ?? .title,
                conditionOperator: condition.operatorEnum ?? .contains,
```
Entsprechende `??`-Defaults an jeder Konsum-Stelle belassen (bestehendes Verhalten), nur über den Getter. **Wichtig:** nur umstellen, wo bereits ein `??`-Default existiert — keine neue Fehlersemantik einführen (Verhaltens­erhalt).

- [ ] **Step 5: Tests + Build → GREEN**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests test 2>&1 | grep -E "fieldEnum|TEST SUCCEEDED"`
Expected: PASS, `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Models/RuleCondition.swift Feedivo/Models/SmartFolderCondition.swift FeedivoTests/RuleConditionTests.swift FeedivoTests/SmartFolderConditionTests.swift
# plus ggf. geänderte Konsum-Stellen:
git add -u
git commit -m "$(cat <<'EOF'
Review-Followup: typsichere Getter für RuleCondition/SmartFolderCondition

field/operator waren rohe Strings; ungültige Raw-Values (z.B. nach einem
Enum-Refactor verwaist) persistierten still und matchen einfach nicht mehr.
fieldEnum/operatorEnum-Getter machen sie früh sichtbar; Konsum-Stellen mit
??-Default auf die Getter umgestellt (Verhalten bleibt gleich).

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: OPML-Refactor-Nachwehen — Sentinel, onChange→Controller, Accessibility, selectedFileName-Reset

**Files:**
- Modify: `Feedivo/Views/OPMLImport/OPMLImportFeedRow.swift:32-47, 69-70` (Sentinel)
- Modify: `Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift` (`applyToggleSelectionToRows`, `reset` setzt `selectedFileName`)
- Modify: `Feedivo/Views/OPMLImport/OPMLImportReviewView.swift:50-59` (onChange→Controller)
- Modify: `Feedivo/Views/FirstRun/FirstRunWizardView.swift:94-103` (onChange→Controller)
- Modify: `FeedivoTests/OPMLImportPreviewControllerTests.swift` (Tests)

**Hintergrund:** Vier kleinere Nachwehen des M1-Refactors:
1. „Ohne Ordner"-String-Sentinel kollidiert mit echtem Ordner dieses Namens → wählt User den realen Ordner, wird `folderName = nil` (Datenverlust).
2. `onChange(allowsDuplicates/Unreachable)`-Sync **dupliziert** in beiden Views → driftet auseinander; gehört in den Controller.
3. Toggle/Picker der gemeinsamen Zeile ohne Accessibility-Label.
4. `reset()` setzt `selectedFileName` nicht zurück (inkonsistent zu `sourceDescription`/`previewProgressText`).

- [ ] **Step 1: Failing Tests**

Ans Ende von `OPMLImportPreviewControllerTests`:

```swift
@Test func applyToggleSelectionToRowsSetztDuplikateBeiOffenemFilter() {
    let controller = OPMLImportPreviewController()
    controller.rows = [
        makeRow(title: "A", xmlURL: "https://a.example.com/feed.xml", status: .duplicate, isSelected: false),
        makeRow(title: "U", xmlURL: "https://u.example.com/feed.xml", status: .unreachable, isSelected: true)
    ]
    controller.allowsDuplicates = true
    controller.allowsUnreachable = false

    controller.applyToggleSelectionToRows()

    #expect(controller.rows[0].isSelected == true)   // Duplikat → selected
    #expect(controller.rows[1].isSelected == false)  // Unreachable → abgewählt
}

@Test func resetSetztSelectedFileNameAufInitialwertZurueck() {
    let controller = OPMLImportPreviewController(configuration: .importSheet)
    controller.selectedFileName = "alt.opml"

    controller.reset()

    #expect(controller.selectedFileName == "Keine OPML-Datei ausgewählt")
}
```

- [ ] **Step 2: Tests laufen lassen → RED**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests-red test 2>&1 | grep -E "applyToggleSelectionToRows|resetSetztSelectedFileName|TEST"`
Expected: FAIL — „'applyToggleSelectionToRows' does not exist" / reset setzt selectedFileName nicht.

- [ ] **Step 3: Controller ergänzen (GREEN)**

In `OPMLImportPreviewController.swift`:

a) `selectedFileName` wird `internal(set)` statt `var` (damit Views es weiterhin setzen dürfen, `reset` es aber zurücksetzt):
```swift
    internal(set) var selectedFileName: String
```

b) `reset()` ergänzen (nach `previewTask?.cancel(); previewTask = nil`):
```swift
        selectedFileName = configuration.initialSelectedFileName
```

c) Neue Methode (bei den Auswahl-Methoden, nach `deselectVisibleRows`):
```swift
    /// Konsistente Auswahl-Synchronisation, wenn allowsDuplicates/Unreachable
    /// getoggelt werden: Duplikate werden auf allowsDuplicates gesetzt, nicht
    /// erreichbare auf allowsUnreachable. Zuvor in beiden Views dupliziert →
    /// hier die einzige Stelle, damit sie nicht auseinanderdriften.
    func applyToggleSelectionToRows() {
        for index in rows.indices {
            switch rows[index].status {
            case .duplicate:
                rows[index].isSelected = allowsDuplicates
            case .unreachable:
                rows[index].isSelected = allowsUnreachable
            case .available:
                continue
            }
        }
    }
```

- [ ] **Step 4: Beide Views — onChange durch Controller-Methode ersetzen**

In `OPMLImportReviewView.swift` (Z. 50-59) den Block:
```swift
        .onChange(of: previewController.allowsDuplicates) {
            for index in previewController.rows.indices where previewController.rows[index].status == .duplicate {
                previewController.rows[index].isSelected = previewController.allowsDuplicates
            }
        }
        .onChange(of: previewController.allowsUnreachable) {
            for index in previewController.rows.indices where previewController.rows[index].status == .unreachable {
                previewController.rows[index].isSelected = previewController.allowsUnreachable
            }
        }
```
ersetzen durch:
```swift
        .onChange(of: previewController.allowsDuplicates) {
            previewController.applyToggleSelectionToRows()
        }
        .onChange(of: previewController.allowsUnreachable) {
            previewController.applyToggleSelectionToRows()
        }
```

Analog in `FirstRunWizardView.swift` (Z. 94-103) denselben Block durch die beiden `.onChange { previewController.applyToggleSelectionToRows() }` ersetzen.

> Achtung: `OPMLImportReviewView.resetFile()` setzt `previewController.selectedFileName = "Keine OPML-Datei ausgewählt"` manuell — das bleibt zulässig (`internal(set)`), kann aber jetzt entfallen, da `reset()` es selbst zurücksetzt. `resetFile()` zu:
```swift
    private func resetFile() {
        previewController.reset()
    }
```

- [ ] **Step 5: OPMLImportFeedRow — Sentinel auf leerer String + Accessibility**

In `OPMLImportFeedRow.swift`:

a) `folderBinding` (Z. 32-47) — „Ohne Ordner"-Literal durch leeren String als internen nil-Sentinel ersetzen (ein realer Ordner kann nicht `""` heißen, da `createFolder` leere Namen ablehnt):
```swift
    private var folderBinding: Binding<String> {
        Binding(
            get: {
                trimmedFolderName(row.feed.folderName) ?? ""
            },
            set: { newValue in
                let folderName = newValue.isEmpty ? nil : newValue
                row.feed = OPMLFeed(
                    title: row.feed.title,
                    xmlURL: row.feed.xmlURL,
                    htmlURL: row.feed.htmlURL,
                    folderName: folderName
                )
            }
        )
    }
```

b) Picker (Z. 69-74) — „Ohne Ordner" als sichtbaren Eintrag mit `.tag("")`:
```swift
            Picker("", selection: folderBinding) {
                Text("Ohne Ordner").tag("")
                ForEach(availableFolders, id: \.self) { folder in
                    Text(folder).tag(folder)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .accessibilityLabel("Ordner für \(row.feed.title)")
            .frame(width: layout.folderWidth, alignment: .leading)
```

c) Toggle (Z. 51-55) — Accessibility-Label ergänzen:
```swift
            Toggle("", isOn: $row.isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(!isSelectable)
                .accessibilityLabel("\(row.feed.title) importieren")
                .frame(width: 34, alignment: .leading)
```

- [ ] **Step 6: Tests + Build → GREEN**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests test 2>&1 | grep -E "applyToggleSelectionToRows|resetSetztSelectedFileName|TEST SUCCEEDED"`
Expected: beide Tests PASS, `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Views/OPMLImport/OPMLImportFeedRow.swift Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift Feedivo/Views/OPMLImport/OPMLImportReviewView.swift Feedivo/Views/FirstRun/FirstRunWizardView.swift FeedivoTests/OPMLImportPreviewControllerTests.swift
git commit -m "$(cat <<'EOF'
Review-Followup: OPML-Refactor-Nachwehen (Sentinel/onChange/Accessibility/reset)

- „Ohne Ordner"-String-Sentinel kollidierte mit echtem Ordner dieses Namens
  (Wahl setzte folderName=nil = Datenverlust). Interner Sentinel jetzt "".
- onChange(allowsDuplicates/Unreachable) war in beiden Views dupliziert →
  in Controller.applyToggleSelectionToRows() vereinheitlicht.
- Toggle/Picker in OPMLImportFeedRow ohne Accessibility-Label → ergänzt.
- reset() setzte selectedFileName nicht zurück (inkonsistent zu den anderen
  Display-Strings) → jetzt auf configuration.initialSelectedFileName.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Finale Verifikation

- [ ] **Step 1: Voll-Suite seriell**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests-final test 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Memory aktualisieren (nach Merge)**

In `code-review-full-codebase-2026-06.md` einen neuen Status-Block „Review-Followup umgesetzt" anlegen (Commits/SHAs); `MEMORY.md`-Index ggf. ergänzen.

- [ ] **Step 3: Push (vom Nutzer freigegeben)**

```bash
git push origin <branch>
```

---

## Deferred — separate Folgewpläne (nicht Teil dieses Plans)

Diese Cluster bewusst NICHT in diesem Plan — sie sind unabhängige Subsysteme (Scope-Check der Skill) oder klärungsbedürftig und verdienen eigene Pläne:

1. **L10n-Abschluss** (HIGH): Plural-Varianten in `Localizable.xcstrings` (0/23 Count-Strings pluralisiert → „1 new articles" in EN/FR/IT) + 67 verbliebene hardcoded deutsche Literale (`FirstRunWizardView` 19, `OPMLImportReviewView` 15, `SmartFolderSettingsView` 9, `SmartFolderEditorView` 8, `RuleSettingsView` 8, `SidebarView` 5). Mechanischer Bulk → eigener Plan.
2. **Service/Netzwerk-Härte** (MEDIUM, 7 Items): URL-Scheme-Validierung (`FeedService:99` → `file://` möglich); geteilte `URLSession` mit Timeouts/Redirect-Policy statt `URLSession.shared` (6 Services); `OPMLDocument` UTF-16/latin1-Decoding; stabile Notification-IDs (`FeedNotificationService:206`); `OrphanedArticleCleanupService` lightFetchDescriptor (P6-Pattern); `BackgroundRefreshService` Schedule-Fehler ≠ Refresh-Fehler; ZIP-UTF-8-Flag (`ArticleExportPackageBuilder:322/336`).
3. **`FeedViewModel` God-Object split** (MEDIUM, Aufwand L): `FeedRefreshService`/`ArticleDedupService`/`OPMLImportOrchestrator` auslagern; CLAUDE.md plant `FeedRefreshService` seit M2 — nie extrahiert.
4. **Fehler-Pipeline vereinheitlichen** (MEDIUM, Aufwand L): 3-4 parallele Alert-Quellen, `OPMLAlert` zweckentfremdet + `OfflineArchiveErrorAlert` dupliziert, 17× `error.localizedDescription` direkt in UI → einheitlicher `ErrorBus`/`AppErrorAlert` + `LocalizedError`-Enums.
5. **`existingArticlesByIdentity` Perf** (MEDIUM): faultet bei jedem Refresh alle `feed.articles` (inkl. `content`/`summary`-Blobs) nur für Duplikat-Keys. **Braucht Spike** — SwiftData-`#Predicate`-Limit für Optional-Attribute (siehe Memory `swiftdata-optional-date-predicate-limitation`): `feedID` (Optional<UUID>) per Prädikat filtern + `propertiesToFetch` auf Identitätsfelder. Zuerst Spike, ob das Prädikat kompiliert/fault wie erwartet.
6. **`SmartFolder.isDefault`-Invariante** (Bug-S): Restore matcht per Name, nicht `isDefault` → Duplikate bei Rename/Delete. **Braucht Design-Entscheidung** über Identität von Default-Ordnern (stabiler `defaultKey` vs. Match per Conditions) — kein reiner Bugfix.
7. **Ordner-Dual-Source-of-Truth** (`Feed.folderName` String + `FeedFolder`-Entity): keine Umbenenn-Operation, die beide synchron hält. Aktuell YAGNI (Rename-UI existiert nicht) — erst relevant, wenn eine Rename-UI gebaut wird.
8. **Low-Tier-Cleanup**: `ArticleMetadataEditor` `try?`-Schlucken; `TagViewModel.deleteTag` Rollback; `ArticleViewModel` nicht-persistierende Overloads; `ArticleNavigationState` neue VM pro Aufruf; `Feed` doppelte Inits; `Article.feed` ohne expliziten `deleteRule`; `Feed.refreshIntervalMinutes/Days`-Validierung; `ImageCacheService` paralleles Trim-Racen; `OPMLService` synchroner Parse; `FeedDiscoveryService` Netzwerkfehler als `noFeedsFound`; `ArticleRetentionCleanup` doppelter Feed-Fetch; `FeedService` RSS-Titel-Fallback = Description; `ReaderView` 5 onChange; `ContentUnavailableView` in `List`; `ContentView` DispatchQueue-Workaround; `@AppStorage`-Rohliterale (`markArticleReadOnSelection`/`appLanguage`); tote `XMLKit`-Dependency; `@Suite(.serialized)` an Value-Type-Tests; kein committed Scheme/Testplan; `ReaderFontRegistry` globale `static var`; Test-Lücken (`updateRule`/`updateFolder` jetzt in T1, aber `FeedViewModel.addFeed`-Fehlerpfad, `TagViewModel.deleteTag`-Rollback, `FeedService` Parsing-Tests fehlen weiter).

---

## Self-Review

- **Spec coverage:** Die 5 Agenten lieferten ~25 Funde (HIGH+Mittel). Dieser Plan deckt die sauberen, verhaltenserhaltenden Bugfixes im Model/ViewModel/OPML-Bereich ab: T1 (orphan conditions), T2 (OPML task race), T3 (unreadCount), T4 (addFeed guard), T5 (OPML preview parallel), T6 (typed getters), T7 (OPML nachwehen). Die übrigen (L10n, Service-Härte, God-Object, Fehler-Pipeline, perf-spike, isDefault-Design, dual-SoT, low-tier) sind im Deferred-Abschnitt mit Begründung aufgeführt — jeder Fund ist zugeordnet.
- **Placeholder scan:** T5 enthält eine bewusste Entscheidungsoption (`feedBatches` generisch vs. lokale `chunked`-Helfer) mit beiden vollständigen Code-Pfaden — kein TBD. T6 Step 4 nutzt `grep` zur Stellensuche statt fester Zeilen (Konsum-Stellen verteilt) — das ist eine konkrete Anweisung, kein Platzhalter. Kein „TODO"/„ähnlich wie Task N".
- **Type consistency:** `OPMLImportPreviewController.previewTask` (T2) und `applyToggleSelectionToRows`/`selectedFileName`-Reset (T7) sind konsistent zwischen Definition und Nutzung. `FeedViewModel.unreadIncrement(for:)` (T3) statisch, in T5 nicht verwendet. `RuleCondition.fieldEnum`/`operatorEnum` und `SmartFolderCondition.fieldEnum`/`operatorEnum` (T6) konsistent benannt und in T6 Step 4 genutzt. `OPMLImportFeedRow`-Sentinel `""` intern, Display bleibt „Ohne Ordner" — kein Konflikt mit `OPMLImportPreviewController.folderCount` (nutzt `trimmedFolderName ?? "Ohne Ordner"` als Display-String im Zähler, nicht als Picker-Tag — unbeeinflusst).
- **Bewusste Abweichung:** T5 nutzt `withTaskGroup`-Rückgabe `(index, status)` statt des exakten `String?`-Musters aus `importOPMLFeeds`, weil die Vorschau Status+Reihenfolge braucht (Import braucht nur Fehler-Titel). In Task notiert.
- **Risiko-Hinweis:** T2 nutzt `defer { if previewTask === Task { self.previewTask = nil } }` — das `===Task`-Check verhindert, dass ein neu gestarteter Task das Handle des vorigen nilt. Konservativ; alternativ Handle nur in `reset()` und bei Abschluss auf nil setzen. Im Task-Code umgesetzt.