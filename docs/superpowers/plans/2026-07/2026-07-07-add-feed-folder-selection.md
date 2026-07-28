# Ordner-Auswahl beim Feed-Hinzufügen — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Beim Anlegen eines Feeds über `AddFeedSheet` kann der Feed direkt einem Ordner zugeordnet werden (Auswahlmenü bestehender Ordner + „Neuer Ordner…").

**Architecture:** Ein optionaler `folderName: String?` wird durch die bestehende Aufrufkette gereicht (`AddFeedSheet` → `FeedViewModel.addFeed` → `SQLiteFeedActionService.addFeed` → `SQLiteFeedSubscriptionService.addFeed`). Die Kernlogik (folderName auf `FeedRecord` setzen + bei neuem Namen `FeedFolderRecord` anlegen) spiegelt exakt den bestehenden OPML-Import-Pfad. Atomar, kein zweiter Schreibvorgang.

**Tech Stack:** Swift, SwiftUI (macOS), GRDB/SQLite, Swift Testing.

## Global Constraints

- Code-Kommentare auf Deutsch.
- Persistenz ausschließlich GRDB/SQLite; nach Mutationen `SQLiteDataInvalidation.bumpStatusVersion()` (hier bereits in `FeedViewModel.addFeed` vorhanden — nicht doppeln).
- Ordnernamen immer über `FeedFolderOrganizer.normalizedFolderName(_:)` normalisieren (`nil`/leer → kein Ordner).
- Tests nur gezielt scoped ausführen: `-only-testing:FeedivoTests/<SuiteName>` — niemals unscoped (deadlockt).
- Neue DB-Migrationen sind NICHT nötig (`folderName` und `feed_folders` existieren bereits).
- SourceKit-Diagnosen sind unzuverlässig; Wahrheit ist ausschließlich ein echter `xcodebuild build`/`test`-Lauf.

---

### Task 1: Kernlogik — `folderName` in `SQLiteFeedSubscriptionService.addFeed`

**Files:**
- Modify: `Feedivo/Services/SQLiteFeedSubscriptionService.swift` (Methode `addFeed`, ca. Zeilen 98–171)
- Test: `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift`

**Interfaces:**
- Consumes: `FeedFolderOrganizer.normalizedFolderName(_:) -> String?`, `FeedFolderStore(database:).folders() -> [FeedFolderRecord]`, `FeedFolderStore.save(_:)`, `FeedFolderRecord(name:createdAt:updatedAt:)`.
- Produces: `SQLiteFeedSubscriptionService.addFeed(urlString:refreshIntervalMinutes:folderName:) async throws -> SQLiteFeedSubscriptionResult` — neuer optionaler Parameter `folderName: String? = nil`.

- [ ] **Step 1: Failing Tests schreiben**

Am Ende von `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift` (vor der schließenden `}` der Suite) einfügen:

```swift
    @MainActor
    @Test func addFeedMitFolderNameSetztOrdnerUndLegtOrdnerRecordAn() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { url in
                ParsedFeed(sourceURL: url, title: "Ordner Feed", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )

        _ = try await service.addFeed(
            urlString: "https://example.com/feed.xml",
            folderName: "Nachrichten"
        )

        let feed = try #require(try FeedStore(database: database).feeds().first)
        #expect(feed.folderName == "Nachrichten")

        let folderNames = try FeedFolderStore(database: database).folders().map(\.name)
        #expect(folderNames.contains("Nachrichten"))
    }

    @MainActor
    @Test func addFeedOhneFolderNameLaesstOrdnerLeer() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { url in
                ParsedFeed(sourceURL: url, title: "Kein Ordner Feed", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )

        _ = try await service.addFeed(urlString: "https://example.com/feed.xml")

        let feed = try #require(try FeedStore(database: database).feeds().first)
        #expect(feed.folderName == nil)
        #expect(try FeedFolderStore(database: database).folders().isEmpty)
    }

    @MainActor
    @Test func addFeedMitBestehendemOrdnerLegtKeinenZweitenRecordAn() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedFolderStore(database: database).save(FeedFolderRecord(name: "Technik"))
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: { url in
                ParsedFeed(sourceURL: url, title: "Technik Feed", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )

        // Andere Gross-/Kleinschreibung muss auf den bestehenden Ordner matchen.
        _ = try await service.addFeed(
            urlString: "https://example.com/feed.xml",
            folderName: "technik"
        )

        let folders = try FeedFolderStore(database: database).folders()
        #expect(folders.count == 1)
        let feed = try #require(try FeedStore(database: database).feeds().first)
        // Feed uebernimmt den getippten (normalisierten) Namen.
        #expect(feed.folderName == "technik")
    }
```

- [ ] **Step 2: Tests laufen lassen, Fehlschlag prüfen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests 2>&1 | grep -E "error:|Compiling|failed|passed"`
Expected: Kompilierfehler „extra argument 'folderName' in call" (Parameter existiert noch nicht).

- [ ] **Step 3: Minimale Implementierung**

In `Feedivo/Services/SQLiteFeedSubscriptionService.swift` die Signatur von `addFeed` erweitern:

```swift
    func addFeed(
        urlString: String,
        refreshIntervalMinutes: Int = 60,
        folderName: String? = nil
    ) async throws -> SQLiteFeedSubscriptionResult {
```

Direkt nach `let feedStore = FeedStore(database: database)` (aktuell Zeile 108) den Folder-Store und den normalisierten Namen ergänzen:

```swift
        let feedStore = FeedStore(database: database)
        let folderStore = FeedFolderStore(database: database)
        let normalizedFolderName = FeedFolderOrganizer.normalizedFolderName(folderName)
```

Im `FeedRecord(...)`-Aufruf (aktuell Zeilen 118–128) `folderName:` ergänzen — zwischen `faviconURL:` und `refreshIntervalMinutes:` (Deklarationsreihenfolge von `FeedRecord.init`):

```swift
        let feedRecord = FeedRecord(
            id: feedID,
            url: parsedFeed.sourceURL,
            title: parsedFeed.title,
            originalTitle: parsedFeed.title,
            websiteURL: parsedFeed.siteURL,
            faviconURL: faviconURL,
            folderName: normalizedFolderName,
            refreshIntervalMinutes: BackgroundRefreshSettings.clampedIntervalMinutes(refreshIntervalMinutes),
            createdAt: now,
            updatedAt: now
        )
```

Unmittelbar vor `try feedStore.save(feedRecord)` (aktuell Zeile 130) die Ordner-Record-Anlage einfügen — gleiche Logik wie im OPML-Zweig:

```swift
        // Bei neuem (normalisiertem) Ordnernamen zusaetzlich einen expliziten
        // feed_folders-Record anlegen — analog zum OPML-Import. Case-insensitiver
        // Abgleich verhindert Duplikate zu bestehenden Ordnern.
        if let normalizedFolderName {
            let knownFolderNames = Set(try folderStore.folders().map { $0.name.lowercased() })
            if !knownFolderNames.contains(normalizedFolderName.lowercased()) {
                try folderStore.save(
                    FeedFolderRecord(name: normalizedFolderName, createdAt: now, updatedAt: now)
                )
            }
        }

        try feedStore.save(feedRecord)
```

- [ ] **Step 4: Tests laufen lassen, Erfolg prüfen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|passed|failed"`
Expected: `** TEST SUCCEEDED **`, die drei neuen Tests `passed`, keine Regression bei den bestehenden.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Services/SQLiteFeedSubscriptionService.swift FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift
git commit -m "Feed-Abo: folderName in SQLiteFeedSubscriptionService.addFeed

Neuer optionaler folderName wird auf den FeedRecord gesetzt; bei neuem
Namen wird zusaetzlich ein feed_folders-Record angelegt (analog OPML-Import).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Passthrough — `SQLiteFeedActionService` und `FeedViewModel`

**Files:**
- Modify: `Feedivo/Services/SQLiteFeedActionService.swift` (Methode `addFeed`, ca. Zeilen 28–41)
- Modify: `Feedivo/ViewModels/FeedViewModel.swift` (Methode `addFeed`, ca. Zeilen 238–273)
- Test: `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift` (Action-Service-Passthrough)

**Interfaces:**
- Consumes: `SQLiteFeedSubscriptionService.addFeed(urlString:refreshIntervalMinutes:folderName:)` aus Task 1.
- Produces:
  - `SQLiteFeedActionService.addFeed(urlString:refreshIntervalMinutes:folderName:) async throws` — neuer Parameter `folderName: String? = nil`.
  - `FeedViewModel.addFeed(urlString:sqliteDatabase:folderName:) async` — neuer Parameter `folderName: String? = nil`.

- [ ] **Step 1: Failing Test schreiben**

Am Ende von `FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift` (vor der schließenden `}` der Suite) einfügen:

```swift
    @MainActor
    @Test func actionServiceAddFeedReichtFolderNameDurch() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let service = SQLiteFeedActionService(
            database: database,
            fetchFeed: { url in
                ParsedFeed(sourceURL: url, title: "Action Feed", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )

        try await service.addFeed(
            urlString: "https://example.com/feed.xml",
            refreshIntervalMinutes: 60,
            folderName: "Blogs"
        )

        let feed = try #require(try FeedStore(database: database).feeds().first)
        #expect(feed.folderName == "Blogs")
    }
```

- [ ] **Step 2: Test laufen lassen, Fehlschlag prüfen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests 2>&1 | grep -E "error:|failed|passed"`
Expected: Kompilierfehler „extra argument 'folderName' in call" in `SQLiteFeedActionService.addFeed`.

- [ ] **Step 3: Implementierung — Action Service**

In `Feedivo/Services/SQLiteFeedActionService.swift` die `addFeed`-Methode anpassen:

```swift
    func addFeed(
        urlString: String,
        refreshIntervalMinutes: Int,
        folderName: String? = nil
    ) async throws {
        let service = SQLiteFeedSubscriptionService(
            database: database,
            fetchFeed: fetchFeed,
            discoverFaviconURL: discoverFaviconURL
        )
        _ = try await service.addFeed(
            urlString: urlString,
            refreshIntervalMinutes: refreshIntervalMinutes,
            folderName: folderName
        )
    }
```

- [ ] **Step 4: Implementierung — ViewModel**

In `Feedivo/ViewModels/FeedViewModel.swift` die `addFeed`-Signatur (Zeile 238) erweitern:

```swift
    func addFeed(urlString: String, sqliteDatabase: FeedivoDatabase?, folderName: String? = nil) async {
```

Im `try await service.addFeed(...)`-Aufruf (aktuell Zeilen 263–266) `folderName` durchreichen:

```swift
            try await service.addFeed(
                urlString: cleanedURL,
                refreshIntervalMinutes: BackgroundRefreshSettings.defaultIntervalMinutes,
                folderName: folderName
            )
```

- [ ] **Step 5: Test laufen lassen, Erfolg prüfen**

Run: `xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/SQLiteFeedSubscriptionServiceTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|passed|failed"`
Expected: `** TEST SUCCEEDED **`, `actionServiceAddFeedReichtFolderNameDurch` passed.

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Services/SQLiteFeedActionService.swift Feedivo/ViewModels/FeedViewModel.swift FeedivoTests/SQLiteFeedSubscriptionServiceTests.swift
git commit -m "Feed-Abo: folderName durch ActionService und FeedViewModel durchreichen

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: UI — Ordner-Auswahl in `AddFeedSheet` + L10n

**Files:**
- Modify: `Feedivo/Views/Sidebar/SidebarView.swift` (`struct AddFeedSheet`, ab Zeile 772)
- Modify: `Feedivo/Resources/L10n.swift` (neuer Key)
- Modify: `Feedivo/Resources/Localizable.xcstrings` (Deutsch/Englisch für neuen Key)

**Interfaces:**
- Consumes: `FeedViewModel.addFeed(urlString:sqliteDatabase:folderName:)` (Task 2); `FeedFolderStore(database:).folders()`; `FeedStore(database:).feeds()`; `FeedFolderOrganizer.folderNames(feedFolderNames:explicitFolderNames:) -> [String]`; `FeedFolderOrganizer.normalizedFolderName(_:)`; vorhandene L10n-Keys `feedPropertiesFolder` (`LocalizedStringKey`) und `feedPropertiesNoFolder` (`String`).
- Produces: UI-Zustand, kein von anderen Tasks konsumiertes Interface. Neuer L10n-Key `sidebarAddFeedNewFolder` (`LocalizedStringKey`).

- [ ] **Step 1: L10n-Key ergänzen**

In `Feedivo/Resources/L10n.swift` in der Nähe der übrigen `sidebarAddFeed*`-Keys einfügen:

```swift
    static let sidebarAddFeedNewFolder = LocalizedStringKey("sidebar.addFeed.newFolder")
```

- [ ] **Step 2: Übersetzungen in `Localizable.xcstrings` ergänzen**

In `Feedivo/Resources/Localizable.xcstrings` einen neuen Eintrag unter `"strings"` hinzufügen (Schlüssel `sidebar.addFeed.newFolder`), im selben Format wie bestehende Einträge:

```json
    "sidebar.addFeed.newFolder" : {
      "extractionState" : "manual",
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Neuer Ordner…"
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "New Folder…"
          }
        }
      }
    },
```

- [ ] **Step 3: View-State + Ordner-Zeile in `AddFeedSheet` ergänzen**

In `Feedivo/Views/Sidebar/SidebarView.swift`, `struct AddFeedSheet`, bei den `@State`-Properties (nach `@State private var isDiscovering = false`, Zeile 780) ergänzen:

```swift
    @State private var selectedFolderName: String?
    @State private var isCreatingNewFolder = false
    @State private var newFolderName = ""
    @State private var availableFolderNames: [String] = []
```

Sentinel-Konstante für die „Neuer Ordner…"-Menüauswahl als statische Property der `AddFeedSheet` (Menu-`tag`s brauchen einen stabilen Wert) ergänzen:

```swift
    // Sentinel-Tag fuer die "Neuer Ordner..."-Menueauswahl. Ein Zeichen, das in
    // normalisierten Ordnernamen nicht vorkommen kann, vermeidet Kollisionen.
    private static let newFolderSentinel = "\u{0}__new_folder__"
```

In `body` die Ordner-Zeile einfügen — direkt nach dem `if let selectedFeedPreview { … }`-Block (nach Zeile 804), also nur sichtbar, sobald ein Feed ausgewählt ist:

```swift
            if selectedFeedURL != nil {
                folderSelectionRow
            }
```

Die Ordner-Zeile als `private var` in `AddFeedSheet` ergänzen (z. B. nach `discoveryResultList`):

```swift
    private var folderSelectionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(L10n.feedPropertiesFolder)
                    .frame(width: 80, alignment: .leading)

                Picker(L10n.feedPropertiesFolder, selection: folderPickerSelection) {
                    Text(L10n.feedPropertiesNoFolder).tag(String?.none)

                    ForEach(availableFolderNames, id: \.self) { name in
                        Text(name).tag(String?.some(name))
                    }

                    Divider()

                    Text(L10n.sidebarAddFeedNewFolder).tag(String?.some(Self.newFolderSentinel))
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Spacer()
            }

            if isCreatingNewFolder {
                TextField(L10n.sidebarAddFeedNewFolder, text: $newFolderName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isBusy)
            }
        }
    }

    // Binding, das die Sentinel-Auswahl in den "Neuer Ordner..."-Modus uebersetzt
    // und sonst den gewaehlten Ordnernamen (bzw. nil) haelt.
    private var folderPickerSelection: Binding<String?> {
        Binding(
            get: {
                isCreatingNewFolder ? Self.newFolderSentinel : selectedFolderName
            },
            set: { newValue in
                if newValue == Self.newFolderSentinel {
                    isCreatingNewFolder = true
                    selectedFolderName = nil
                } else {
                    isCreatingNewFolder = false
                    newFolderName = ""
                    selectedFolderName = newValue
                }
            }
        )
    }

    // Effektiver Ordnername fuer das Abonnieren: im Neu-Modus der getippte Name,
    // sonst der ausgewaehlte. Normalisierung (leer -> nil) uebernimmt der Service.
    private var effectiveFolderName: String? {
        isCreatingNewFolder ? newFolderName : selectedFolderName
    }

    private func loadAvailableFolderNames() {
        guard let feedivoDatabase else {
            return
        }

        do {
            let folders = try FeedFolderStore(database: feedivoDatabase).folders()
            let feeds = try FeedStore(database: feedivoDatabase).feeds()
            availableFolderNames = FeedFolderOrganizer.folderNames(
                feedFolderNames: feeds.map(\.folderName),
                explicitFolderNames: folders.map { $0.name }
            )
        } catch {
            availableFolderNames = []
        }
    }
```

- [ ] **Step 4: Ordnerliste laden + folderName ans ViewModel übergeben**

In `AddFeedSheet.body` den vorhandenen `.onChange(of: urlString) { resetDiscovery() }`-Modifier (Zeilen 838–840) um das Laden der Ordner beim Erscheinen ergänzen. Direkt nach dem `.onChange(of: urlString)`-Block anfügen:

```swift
        .onAppear {
            loadAvailableFolderNames()
        }
```

Die `addFeed`-Hilfsmethode (Zeilen 1010–1018) den effektiven Ordnernamen übergeben lassen:

```swift
    private func addFeed(urlString: String) async {
        await viewModel.addFeed(
            urlString: urlString,
            sqliteDatabase: feedivoDatabase,
            folderName: effectiveFolderName
        )
        if viewModel.errorMessage == nil {
            dismiss()
        }
    }
```

- [ ] **Step 5: Build prüfen**

Run: `xcodebuild build -scheme Feedivo -destination 'platform=macOS' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Manuelle Verifikation**

App in Xcode starten (Cmd+R). Feed hinzufügen und je einmal prüfen:
1. „Kein Ordner" (Default) → Feed erscheint in der Sidebar ohne Ordner.
2. Bestehenden Ordner wählen → Feed erscheint unter diesem Ordner.
3. „Neuer Ordner…" → Textfeld erscheint, Namen eingeben → Feed erscheint unter neuem Ordner; Ordner bleibt auch nach App-Neustart bestehen.

- [ ] **Step 7: Commit**

```bash
git add Feedivo/Views/Sidebar/SidebarView.swift Feedivo/Resources/L10n.swift Feedivo/Resources/Localizable.xcstrings
git commit -m "Feed hinzufuegen: Ordner-Auswahl mit Menue + Neuer Ordner

AddFeedSheet zeigt am Abonnieren-Schritt eine Ordner-Zeile: Popup-Menue
mit bestehenden Ordnern, Kein Ordner (Default) und Neuer Ordner...
(Inline-Textfeld). Der gewaehlte Ordnername geht via folderName an
FeedViewModel.addFeed.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Schreibpfad Ansatz A (folderName durchreichen) → Tasks 1 + 2. ✓
- FeedRecord.folderName setzen + FeedFolderRecord bei neuem Namen → Task 1. ✓
- UI-Menü mit bestehenden Ordnern + „Kein Ordner" + „Neuer Ordner…" → Task 3. ✓
- Ordnerliste als Union (feed_folders + Feed-folderNames, normalisiert) → Task 3 `loadAvailableFolderNames` via `FeedFolderOrganizer.folderNames`. ✓
- Platzierung am Abonnieren-Schritt (nur bei ausgewähltem Feed) → Task 3 `if selectedFeedURL != nil`. ✓
- Edge Cases (leer → nil, case-insensitiver Duplikat-Schutz) → Task 1 (Normalisierung + knownFolderNames) + Test `addFeedMitBestehendemOrdnerLegtKeinenZweitenRecordAn`. ✓
- L10n (vorhandene Keys wiederverwenden + neuer „Neuer Ordner…"-Key) → Task 3. ✓
- Tests auf Service-Ebene (3 Fälle) → Task 1; Passthrough-Test → Task 2. ✓

**Placeholder scan:** Keine TODO/TBD; jeder Code-Step enthält vollständigen Code. ✓

**Type consistency:** `folderName: String?` durchgängig; `effectiveFolderName`/`folderPickerSelection`/`newFolderSentinel`/`loadAvailableFolderNames` konsistent benannt; `FeedFolderOrganizer.folderNames(feedFolderNames:explicitFolderNames:)` mit `[String?]`-Overload (Feed-`folderName`s sind optional) passt. ✓
