# OPML-Import-Deduplikation (M1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die zweifach gepflegte OPML-Vorschau-Logik aus `OPMLImportReviewView` und `FirstRunWizardView` in einen gemeinsamen `@Observable OPMLImportPreviewController` und eine einheitliche `OPMLImportFeedRow` extrahieren — reines Verhaltens-Erhaltungs-Refactor.

**Architecture:** Ein `@MainActor @Observable`-Controller hält den gesamten geteilten State + Logik + Helfer (ohne externe Abhängigkeiten als Felder; `feeds`/`feedViewModel` werden pro Aufruf übergeben). Eine parameterisierbare `OPMLImportFeedRow` ersetzt die beiden Zeilen-Structs. Tabellen-Layouts bleiben pro View. Import-Nachbearbeitung bleibt pro View (divergent).

**Tech Stack:** SwiftUI, SwiftData, `@Observable` (Observation), FeedKit, Swift Testing (`@Test`/`#expect`). Swift 5.0 (kein Strict-Concurrency).

## Global Constraints

- Kommentare im Code auf Deutsch (CLAUDE.md).
- Keine nutzer­sichtbare Verhaltensänderung — reines Refactor.
- SwiftData-@Model-Properties bleiben Optional-oder-Default (CloudKit-Blocker B1 bereits done).
- `NavigationView` deprecated → nicht verwenden.
- Neue `.swift`-Dateien auto-inkludiert via `PBXFileSystemSynchronizedRootGroup` → **kein `.pbxproj`-Edit**.
- Build-Test-Befehl (seriell, wie im Projekt etabliert): `xcodebuild -scheme Feedivo -destination 'platform=macOS' build` und `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests test`.
- xcstrings nicht anfassen in diesem Refactor (keine neuen User-Strings).

---

## File Structure

- **Create** `Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift` — `OPMLImportPreviewConfiguration`, die verschobenen Shared-Typen (`OPMLImportStatusFilter`, `OPMLImportSelectionOptions`, `OPMLImportDroppedFile`), `@Observable @MainActor OPMLImportPreviewController`.
- **Create** `Feedivo/Views/OPMLImport/OPMLImportFeedRow.swift` — `OPMLImportFeedRowLayout`, einheitliche `OPMLImportFeedRow`, `hostName`-Helfer.
- **Create** `FeedivoTests/OPMLImportPreviewControllerTests.swift` — Charakterisierungstests für die reine Controller-Logik.
- **Modify** `Feedivo/Views/OPMLImport/OPMLImportReviewView.swift` — State/Logik/Zeile entfernen, an Controller + `OPMLImportFeedRow` binden; Shared-Typen löschen (verschoben).
- **Modify** `Feedivo/Views/FirstRun/FirstRunWizardView.swift` — State/Logik/Zeile entfernen, an Controller + `OPMLImportFeedRow` binden; Step-Nähte behalten.

---

## Task 1: `OPMLImportPreviewController` + Shared-Typen + Tests (TDD)

**Files:**
- Create: `Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift`
- Create: `FeedivoTests/OPMLImportPreviewControllerTests.swift`
- Modify: `Feedivo/Views/OPMLImport/OPMLImportReviewView.swift` (nur: Shared-Typen `OPMLImportStatusFilter`/`OPMLImportSelectionOptions`/`OPMLImportDroppedFile` löschen — sie sind jetzt in der neuen Datei; Rest der View bleibt unangetastet bis Task 3)

**Interfaces:**
- Consumes: `OPMLImportPreviewRow`, `OPMLFeed`, `OPMLImportPreviewProgress`, `OPMLImportFeedStatus` (aus `FeedViewModel.swift`), `OPMLService.parseFeeds(from:)`, `Feed` (`Models/Feed.swift`), `FeedViewModel.opmlImportPreviewRows(for:existingFeeds:onProgress:)`.
- Produces (für Tasks 2–4):
  - `struct OPMLImportPreviewConfiguration { let initialSourceDescription: String; let initialPreviewProgressText: String; let initialSelectedFileName: String; static let importSheet; static let firstRun }`
  - `@Observable @MainActor final class OPMLImportPreviewController`
  - Stored (public set, über Binding mutierbar): `var rows: [OPMLImportPreviewRow]`, `var allowsDuplicates: Bool`, `var allowsUnreachable: Bool`, `var refreshAfterImport: Bool`, `var statusFilter: OPMLImportStatusFilter`, `var newFolderName: String`, `var isFileImporterPresented: Bool`, `var isDropTargeted: Bool`
  - Stored (`private(set)`): `var selectedFileName: String`, `var sourceDescription: String`, `var previewProgressText: String`, `var errorMessage: String?`, `var resultMessage: String?`, `var isPreparingPreview: Bool`, `var customFolders: [String]`
  - Computed: `var selectionOptions: OPMLImportSelectionOptions`, `var selectedImportRows: [OPMLImportPreviewRow]`, `var duplicateCount: Int`, `var unreachableCount: Int`, `var folderCount: Int`, `var visibleRowIDs: Set<OPMLImportPreviewRow.ID>`, `var visibleRowCount: Int`
  - Methods: `init(configuration:)`, `selectAllImportableRows()`, `deselectVisibleRows()`, `createFolder()`, `reset()`, `func availableFolders(existingFeeds: [Feed]) -> [String]`, `func trimmedFolderName(_:) -> String?`, `func loadOPML(from:existingFeeds:feedViewModel:)`, `func preparePreview(feeds:existingFeeds:feedViewModel:sourceText:)`, `func handleDroppedFiles(_:existingFeeds:feedViewModel:onValidFile:) -> Bool`

- [ ] **Step 1: Test-Datei schreiben (RED)**

Create `FeedivoTests/OPMLImportPreviewControllerTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import Feedivo

@MainActor
struct OPMLImportPreviewControllerTests {
    private func makeRow(
        title: String,
        xmlURL: String,
        status: OPMLImportFeedStatus,
        folderName: String? = nil,
        isSelected: Bool = false
    ) -> OPMLImportPreviewRow {
        OPMLImportPreviewRow(
            feed: OPMLFeed(title: title, xmlURL: xmlURL, htmlURL: nil, folderName: folderName),
            status: status,
            isSelected: isSelected
        )
    }

    @Test func selectAllImportableRowsMarkiertNurSichtbareImportierbareFeeds() {
        let controller = OPMLImportPreviewController()
        controller.rows = [
            makeRow(title: "A", xmlURL: "https://a.example.com/feed.xml", status: .available, isSelected: false),
            makeRow(title: "D", xmlURL: "https://d.example.com/feed.xml", status: .duplicate, isSelected: false),
            makeRow(title: "U", xmlURL: "https://u.example.com/feed.xml", status: .unreachable, isSelected: false)
        ]
        controller.statusFilter = .available
        controller.allowsDuplicates = false
        controller.allowsUnreachable = false

        controller.selectAllImportableRows()

        #expect(controller.rows[0].isSelected == true)
        #expect(controller.rows[1].isSelected == false)
        #expect(controller.rows[2].isSelected == false)
    }

    @Test func selectAllImportableRowsErlaubtDuplikateBeiOffenemFilter() {
        let controller = OPMLImportPreviewController()
        controller.rows = [
            makeRow(title: "D", xmlURL: "https://d.example.com/feed.xml", status: .duplicate, isSelected: false)
        ]
        controller.statusFilter = .all
        controller.allowsDuplicates = true

        controller.selectAllImportableRows()

        #expect(controller.rows[0].isSelected == true)
    }

    @Test func deselectVisibleRowsSetztNurSichtbareAufFalse() {
        let controller = OPMLImportPreviewController()
        controller.rows = [
            makeRow(title: "A", xmlURL: "https://a.example.com/feed.xml", status: .available, isSelected: true),
            makeRow(title: "D", xmlURL: "https://d.example.com/feed.xml", status: .duplicate, isSelected: true)
        ]
        controller.statusFilter = .available

        controller.deselectVisibleRows()

        #expect(controller.rows[0].isSelected == false)
        #expect(controller.rows[1].isSelected == true)
    }

    @Test func createFolderFuegtGetrimmtenOrdnerHinzuUndLeertFeld() {
        let controller = OPMLImportPreviewController()
        controller.newFolderName = " News "

        controller.createFolder()

        #expect(controller.customFolders == ["News"])
        #expect(controller.newFolderName == "")
    }

    @Test func createFolderDedupeltCaseInsensitive() {
        let controller = OPMLImportPreviewController()
        controller.customFolders = ["News"]
        controller.newFolderName = "news"

        controller.createFolder()

        #expect(controller.customFolders == ["News"])
    }

    @Test func createFolderIgnoriertLeerenNamen() {
        let controller = OPMLImportPreviewController()
        controller.newFolderName = "   "

        controller.createFolder()

        #expect(controller.customFolders == [])
        #expect(controller.newFolderName == "   ")
    }

    @Test func availableFoldersFasstExistingPreviewUndCustomZusammenUndSortiert() {
        let controller = OPMLImportPreviewController()
        controller.customFolders = ["Zeta"]
        controller.rows = [
            makeRow(title: "A", xmlURL: "https://a.example.com/feed.xml", status: .available, folderName: "Alpha"),
            makeRow(title: "A2", xmlURL: "https://a2.example.com/feed.xml", status: .available, folderName: "Alpha")
        ]
        let existing = [
            Feed(url: "https://b.example.com/feed.xml", title: "B", folderName: "Beta")
        ]

        let folders = controller.availableFolders(existingFeeds: existing)

        #expect(folders == ["Alpha", "Beta", "Zeta"])
    }

    @Test func duplicateUnreachableUndFolderCountZaehlenKorrekt() {
        let controller = OPMLImportPreviewController()
        controller.allowsDuplicates = true
        controller.rows = [
            makeRow(title: "A", xmlURL: "https://a.example.com/feed.xml", status: .available, isSelected: true, folderName: "News"),
            makeRow(title: "D", xmlURL: "https://d.example.com/feed.xml", status: .duplicate, isSelected: true, folderName: "News"),
            makeRow(title: "U", xmlURL: "https://u.example.com/feed.xml", status: .unreachable, isSelected: false)
        ]

        #expect(controller.duplicateCount == 1)
        #expect(controller.unreachableCount == 1)
        #expect(controller.selectedImportRows.count == 2)
        #expect(controller.folderCount == 1)
    }

    @Test func resetStelltInitialStringsWiederHerUndLeertRows() {
        let controller = OPMLImportPreviewController(configuration: .firstRun)
        let initialSource = controller.sourceDescription
        let initialProgress = controller.previewProgressText
        controller.rows = [makeRow(title: "A", xmlURL: "https://a.example.com/feed.xml", status: .available, isSelected: true)]
        controller.allowsDuplicates = true
        controller.statusFilter = .duplicates
        controller.sourceDescription = "Zwischenstand"
        controller.previewProgressText = "Zwischenstand"
        controller.errorMessage = "irgendwas"

        controller.reset()

        #expect(controller.rows == [])
        #expect(controller.allowsDuplicates == false)
        #expect(controller.allowsUnreachable == false)
        #expect(controller.statusFilter == .all)
        #expect(controller.sourceDescription == initialSource)
        #expect(controller.previewProgressText == initialProgress)
        #expect(controller.errorMessage == nil)
    }
}
```

- [ ] **Step 2: Tests laufen lassen → RED (Compiler-Fehler)**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests-red test 2>&1 | tail -5`
Expected: BUILD FAILURE — „cannot find 'OPMLImportPreviewController' in scope".

- [ ] **Step 3: Controller-Datei implementieren (GREEN)**

Create `Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift`:

```swift
import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

// MARK: - Shared Typen (zuvor in OPMLImportReviewView.swift)

enum OPMLImportStatusFilter: String, CaseIterable, Identifiable {
    case all
    case available
    case duplicates
    case unreachable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Alle Stati"
        case .available: "Neue Feeds"
        case .duplicates: "Duplikate"
        case .unreachable: "Nicht erreichbar"
        }
    }

    func filteredRows(from rows: [OPMLImportPreviewRow]) -> [OPMLImportPreviewRow] {
        switch self {
        case .all: rows
        case .available: rows.filter { $0.status == .available }
        case .duplicates: rows.filter { $0.status == .duplicate }
        case .unreachable: rows.filter { $0.status == .unreachable }
        }
    }
}

struct OPMLImportSelectionOptions: Equatable {
    var allowsDuplicates: Bool
    var allowsUnreachable: Bool

    func canImport(_ status: OPMLImportFeedStatus) -> Bool {
        switch status {
        case .available: true
        case .duplicate: allowsDuplicates
        case .unreachable: allowsUnreachable
        }
    }
}

struct OPMLImportDroppedFile {
    static func isSupported(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        return fileExtension == "opml" || fileExtension == "xml"
    }

    static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data,
           let string = String(data: data, encoding: .utf8),
           let url = URL(string: string) {
            return url
        }
        return nil
    }
}

// MARK: - Konfiguration der Initial-Strings

struct OPMLImportPreviewConfiguration: Equatable {
    let initialSourceDescription: String
    let initialPreviewProgressText: String
    let initialSelectedFileName: String

    /// Default: OPML-Import-Sheet.
    static let importSheet = OPMLImportPreviewConfiguration(
        initialSourceDescription: "Wähle eine .opml- oder .xml-Datei, danach erscheint hier die Import-Vorschau.",
        initialPreviewProgressText: "Noch keine Datei ausgewählt.",
        initialSelectedFileName: "Keine OPML-Datei ausgewählt"
    )

    /// FirstRun-Wizard-Varianten der Leer-Texte.
    static let firstRun = OPMLImportPreviewConfiguration(
        initialSourceDescription: "Wähle aus, wie du deine ersten Feeds hinzufügen möchtest.",
        initialPreviewProgressText: "Noch keine Feeds geprüft.",
        initialSelectedFileName: "Keine OPML-Datei ausgewählt"
    )
}

// MARK: - Controller

/// Hält den gesamten geteilten State + Logik + Helfer für die OPML-Import-
/// Vorschau. Hat KEINE externen Abhängigkeiten als Felder: `feeds`,
/// `feedViewModel` und `modelContext` werden pro Aufruf übergeben
/// (feeds stammt aus @Query und kann sich ändern → kein Stale-Cache).
@Observable
@MainActor
final class OPMLImportPreviewController {
    // Über Binding mutierbar (Toggle/Picker/fileImporter/onDrop):
    var rows: [OPMLImportPreviewRow] = []
    var allowsDuplicates = false
    var allowsUnreachable = false
    var refreshAfterImport = true
    var statusFilter: OPMLImportStatusFilter = .all
    var newFolderName = ""
    var isFileImporterPresented = false
    var isDropTargeted = false

    // Nur-Lesen für Views, geschrieben von Controller-Methoden:
    private(set) var selectedFileName: String
    private(set) var sourceDescription: String
    private(set) var previewProgressText: String
    private(set) var errorMessage: String?
    private(set) var resultMessage: String?
    private(set) var isPreparingPreview = false
    private(set) var customFolders: [String] = []

    private let configuration: OPMLImportPreviewConfiguration

    init(configuration: OPMLImportPreviewConfiguration = .importSheet) {
        self.configuration = configuration
        self.selectedFileName = configuration.initialSelectedFileName
        self.sourceDescription = configuration.initialSourceDescription
        self.previewProgressText = configuration.initialPreviewProgressText
    }

    // MARK: Abgeleitete Properties

    var selectionOptions: OPMLImportSelectionOptions {
        OPMLImportSelectionOptions(
            allowsDuplicates: allowsDuplicates,
            allowsUnreachable: allowsUnreachable
        )
    }

    var selectedImportRows: [OPMLImportPreviewRow] {
        rows.filter { $0.isSelected && selectionOptions.canImport($0.status) }
    }

    var duplicateCount: Int {
        rows.filter { $0.status == .duplicate }.count
    }

    var unreachableCount: Int {
        rows.filter { $0.status == .unreachable }.count
    }

    var folderCount: Int {
        Set(selectedImportRows.map { trimmedFolderName($0.feed.folderName) ?? "Ohne Ordner" }).count
    }

    var visibleRowIDs: Set<OPMLImportPreviewRow.ID> {
        Set(statusFilter.filteredRows(from: rows).map(\.id))
    }

    var visibleRowCount: Int {
        visibleRowIDs.count
    }

    // MARK: Helfer

    func trimmedFolderName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    func availableFolders(existingFeeds: [Feed]) -> [String] {
        let existingFolderNames = existingFeeds.compactMap { trimmedFolderName($0.folderName) }
        let previewFolderNames = rows.compactMap { trimmedFolderName($0.feed.folderName) }
        return Array(Set(existingFolderNames + previewFolderNames + customFolders))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: Auswahl

    func selectAllImportableRows() {
        for index in rows.indices {
            guard visibleRowIDs.contains(rows[index].id) else { continue }
            rows[index].isSelected = selectionOptions.canImport(rows[index].status)
        }
    }

    func deselectVisibleRows() {
        for index in rows.indices where visibleRowIDs.contains(rows[index].id) {
            rows[index].isSelected = false
        }
    }

    func createFolder() {
        let folderName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folderName.isEmpty else { return }
        if !customFolders.contains(where: { $0.caseInsensitiveCompare(folderName) == .orderedSame }) {
            customFolders.append(folderName)
        }
        newFolderName = ""
    }

    /// Setzt den gemeinsamen State auf die Initial-Konfiguration zurück.
    /// View-spezifische Extras (selectedFileName, completionSummary, step)
    /// werden von den Views zusätzlich behandelt.
    func reset() {
        rows = []
        errorMessage = nil
        resultMessage = nil
        isPreparingPreview = false
        sourceDescription = configuration.initialSourceDescription
        previewProgressText = configuration.initialPreviewProgressText
        statusFilter = .all
        allowsDuplicates = false
        allowsUnreachable = false
        newFolderName = ""
        customFolders = []
        isFileImporterPresented = false
        isDropTargeted = false
    }

    // MARK: Async Preview-Flow

    func loadOPML(from result: Result<URL, Error>, existingFeeds: [Feed], feedViewModel: FeedViewModel) {
        Task { @MainActor in
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
                sourceDescription = "\(opmlFeeds.count) Feeds erkannt. Feed-Adressen werden geprüft..."
                previewProgressText = "\(opmlFeeds.count) Feeds erkannt. Prüfung startet..."
                rows = await feedViewModel.opmlImportPreviewRows(
                    for: opmlFeeds,
                    existingFeeds: existingFeeds,
                    onProgress: { progress in
                        previewProgressText = progress.displayText
                        sourceDescription = progress.displayText
                    }
                )
                sourceDescription = "\(rows.count) Feeds erkannt · \(Set(rows.map { trimmedFolderName($0.feed.folderName) ?? "Ohne Ordner" }).count) Ordner · \(url.lastPathComponent)"
                previewProgressText = "Prüfung abgeschlossen."
                isPreparingPreview = false
            } catch {
                isPreparingPreview = false
                rows = []
                errorMessage = error.localizedDescription
                sourceDescription = "Die Datei konnte nicht gelesen werden."
                previewProgressText = "Die Datei konnte nicht gelesen werden."
            }
        }
    }

    /// FirstRun: Vorschau für manuell eingegebene Feed-Adresse (Einzel-Feed).
    func preparePreview(feeds: [OPMLFeed], existingFeeds: [Feed], feedViewModel: FeedViewModel, sourceText: String) {
        Task { @MainActor in
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
                    previewProgressText = progress.displayText
                    sourceDescription = progress.displayText
                }
            )

            sourceDescription = "\(rows.count) Feeds geprüft."
            previewProgressText = "Prüfung abgeschlossen."
            isPreparingPreview = false
        }
    }

    /// Drop-Verarbeitung. `onValidFile` wird auf Main nach URL-Validierung
    /// gerufen (vor loadOPML) — FirstRun nutzt das, um `step = .importOPML`
    /// zu setzen; OPML übergibt nil.
    func handleDroppedFiles(
        _ providers: [NSItemProvider],
        existingFeeds: [Feed],
        feedViewModel: FeedViewModel,
        onValidFile: ((URL) -> Void)? = nil
    ) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            DispatchQueue.main.async {
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let url = OPMLImportDroppedFile.url(from: item),
                      OPMLImportDroppedFile.isSupported(url)
                else {
                    self.errorMessage = "Bitte eine OPML- oder XML-Datei ablegen."
                    return
                }
                onValidFile?(url)
                self.loadOPML(from: .success(url), existingFeeds: existingFeeds, feedViewModel: feedViewModel)
            }
        }
        return true
    }
}
```

- [ ] **Step 4: Shared-Typen aus OPMLImportReviewView.swift löschen**

In `Feedivo/Views/OPMLImport/OPMLImportReviewView.swift` lösche die drei Typ-Definitionen `enum OPMLImportStatusFilter` (Zeilen ~5–38), `struct OPMLImportSelectionOptions` (~40–54) und `struct OPMLImportDroppedFile` (~56–75) inkl. der leeren Zeile dazwischen. Sie sind jetzt in `OPMLImportPreviewController.swift`. Die `import`-Zeilen und der Rest der Datei bleiben unverändert. (Beide Views referenzieren diese Typen aus demselben Modul → Build bleibt grün.)

- [ ] **Step 5: Tests + Build laufen lassen → GREEN**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests task test 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **` — 9 neue Controller-Tests grün, alle bestehenden Tests weiterhin grün (insbesondere `OPMLImportStatusFilterTests`, der die verschobenen Typen nutzt).

- [ ] **Step 6: Commit**

```bash
git add Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift \
        FeedivoTests/OPMLImportPreviewControllerTests.swift \
        Feedivo/Views/OPMLImport/OPMLImportReviewView.swift
git commit -m "$(cat <<'EOF'
M1 (OPML-Dedup): OPMLImportPreviewController + Shared-Typen extrahieren

Zentrale @Observable-Controller-Klasse für State/Logik/Helfer der OPML-
Import-Vorschau (zuvor zweifach in OPMLImportReviewView & FirstRunWizardView).
Shared-Typen (StatusFilter/SelectionOptions/DroppedFile) in Controller-Datei
verschoben. 9 Charakterisierungstests für reine Logik.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Einheitliche `OPMLImportFeedRow`

**Files:**
- Create: `Feedivo/Views/OPMLImport/OPMLImportFeedRow.swift`

**Interfaces:**
- Consumes: `OPMLImportPreviewRow`, `OPMLFeed`, `OPMLImportSelectionOptions` (Task 1), `OPMLImportFeedStatus`.
- Produces (für Tasks 3–4):
  - `struct OPMLImportFeedRowLayout: Equatable { var showsWebsite: Bool; var rowHeight: CGFloat; var folderWidth: CGFloat; var statusWidth: CGFloat }`
  - `static let importSheet = OPMLImportFeedRowLayout(showsWebsite: true, rowHeight: 58, folderWidth: 154, statusWidth: 108)`
  - `static let firstRun = OPMLImportFeedRowLayout(showsWebsite: false, rowHeight: 42, folderWidth: 140, statusWidth: 110)`
  - `struct OPMLImportFeedRow: View` mit init `init(row:selectionOptions:availableFolders:layout:)`

- [ ] **Step 1: Zeilen-Komponente implementieren**

Create `Feedivo/Views/OPMLImport/OPMLImportFeedRow.swift`:

```swift
import SwiftUI

/// Layout-Konfiguration der OPML-Feed-Zeile. OPML-Import-Sheet zeigt eine
/// zusätzliche „Website"-Spalte, FirstRun nicht; Höhen/Spaltenbreiten
/// unterscheiden sich leicht.
struct OPMLImportFeedRowLayout: Equatable {
    var showsWebsite: Bool
    var rowHeight: CGFloat
    var folderWidth: CGFloat
    var statusWidth: CGFloat

    static let importSheet = OPMLImportFeedRowLayout(
        showsWebsite: true, rowHeight: 58, folderWidth: 154, statusWidth: 108
    )
    static let firstRun = OPMLImportFeedRowLayout(
        showsWebsite: false, rowHeight: 42, folderWidth: 140, statusWidth: 110
    )
}

/// Einheitliche Feed-Zeile für OPML-Import-Sheet und FirstRun-Wizard.
/// Ersetzt die zuvor separaten OPMLImportFeedRow und FirstRunImportFeedRow.
struct OPMLImportFeedRow: View {
    @Binding var row: OPMLImportPreviewRow
    let selectionOptions: OPMLImportSelectionOptions
    let availableFolders: [String]
    let layout: OPMLImportFeedRowLayout

    private var isSelectable: Bool {
        selectionOptions.canImport(row.status)
    }

    private var folderBinding: Binding<String> {
        Binding(
            get: {
                trimmedFolderName(row.feed.folderName) ?? "Ohne Ordner"
            },
            set: { newValue in
                let folderName = newValue == "Ohne Ordner" ? nil : newValue
                row.feed = OPMLFeed(
                    title: row.feed.title,
                    xmlURL: row.feed.xmlURL,
                    htmlURL: row.feed.htmlURL,
                    folderName: folderName
                )
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $row.isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(!isSelectable)
                .frame(width: 34, alignment: .leading)

            feedText
                .frame(maxWidth: .infinity, alignment: .leading)

            if layout.showsWebsite {
                Text(hostName(from: row.feed.htmlURL ?? row.feed.xmlURL))
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
                    .frame(width: 180, alignment: .leading)
            }

            Picker("", selection: folderBinding) {
                Text("Ohne Ordner").tag("Ohne Ordner")
                ForEach(availableFolders, id: \.self) { folder in
                    Text(folder).tag(folder)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: layout.folderWidth, alignment: .leading)

            statusBadge
                .frame(width: layout.statusWidth, alignment: .leading)
        }
        .frame(height: layout.rowHeight)
        .padding(.horizontal, 12)
        .background(rowBackground)
        .onChange(of: row.isSelected) {
            if !isSelectable {
                row.isSelected = false
            }
        }
    }

    private var feedText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.feed.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(row.feed.xmlURL)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var statusBadge: some View {
        Text(statusText)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(statusColor.opacity(0.16)))
            .lineLimit(1)
    }

    private var rowBackground: Color {
        switch row.status {
        case .available: .clear
        case .duplicate: Color(nsColor: .controlBackgroundColor).opacity(0.74)
        case .unreachable: Color.orange.opacity(0.08)
        }
    }

    private var statusText: String {
        switch row.status {
        case .available: "Neu"
        case .duplicate: "Duplikat"
        case .unreachable: "Nicht erreichbar"
        }
    }

    private var statusColor: Color {
        switch row.status {
        case .available: .green
        case .duplicate: .red
        case .unreachable: .orange
        }
    }

    private func hostName(from value: String) -> String {
        guard let host = URL(string: value)?.host(percentEncoded: false) else {
            return "Ungültige URL"
        }
        return host.replacing(/^www\./, with: "")
    }

    private func trimmedFolderName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}
```

- [ ] **Step 2: Build prüfen**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`. (Die neuen Typen sind noch nicht referenziert, aber sie kompilieren. Die alten `private OPMLImportFeedRow`/`FirstRunImportFeedRow` bestehen noch — kein Konflikt, da `OPMLImportFeedRow` neu internal ist und die alten private sind. Sollten Namenskollisionen auftreten: in diesem Schritt noch nicht, weil die alten `private` sind und nur in ihrer Datei sichtbar.)

- [ ] **Step 3: Commit**

```bash
git add Feedivo/Views/OPMLImport/OPMLImportFeedRow.swift
git commit -m "$(cat <<'EOF'
M1 (OPML-Dedup): einheitliche OPMLImportFeedRow mit Layout-Konfig

Ersetzt die separaten OPMLImportFeedRow und FirstRunImportFeedRow. Eine
Komponente, parameterisierbar via OPMLImportFeedRowLayout (Website-Spalte
an/aus, Höhen/Breiten). Status-Badge/folderBinding/… einmal gepflegt.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `OPMLImportReviewView` an Controller + einheitliche Zeile binden

**Files:**
- Modify: `Feedivo/Views/OPMLImport/OPMLImportReviewView.swift`

**Interfaces:**
- Consumes: `OPMLImportPreviewController` (Task 1), `OPMLImportFeedRow`/`OPMLImportFeedRowLayout` (Task 2).

**Transformation (alle Änderungen in dieser einen Datei):**

1. **State ersetzen:** Lösche alle `@State`-Variablen, die jetzt im Controller sind: `isFileImporterPresented`, `isDropTargeted`, `selectedFileName`, `fileDescription`, `previewProgressText`, `rows`, `isPreparingPreview`, `allowsDuplicates`, `allowsUnreachable`, `refreshAfterImport`, `newFolderName`, `customFolders`, `statusFilter`, `errorMessage`, `resultMessage`. Ersetze sie durch:

```swift
@State private var previewController = OPMLImportPreviewController(configuration: .importSheet)
```

Behalte: `feeds` (`let`), `feedViewModel` (`let`), `@Environment(\.dismiss)`, `@Environment(\.modelContext)`, `@AppStorage(BackgroundRefreshSettings.intervalMinutesKey)`, `tableBodyHeight` (`let`).

2. **Computed Props löschen** (jetzt am Controller): `selectedImportRows`, `selectionOptions`, `duplicateCount`, `unreachableCount`, `folderCount`, `availableFolders`, `visibleRowIDs`, `visibleRowCount`. Behalte `selectionSummaryText` als View-Chrome, aber lies vom Controller:

```swift
private var selectionSummaryText: String {
    if previewController.statusFilter == .all {
        return "Ausgewählt: \(previewController.selectedImportRows.count) von \(previewController.rows.count)"
    }
    return "Ausgewählt: \(previewController.selectedImportRows.count) von \(previewController.visibleRowCount) sichtbar"
}
```

`statusColor`/`statusText` (Header-Badge) — behalten, aber `duplicateCount`/`unreachableCount`/`rows` über `previewController.` lesen. Beispiel:

```swift
private var statusColor: Color {
    if previewController.unreachableCount > 0 { return .red }
    if previewController.duplicateCount > 0 { return .orange }
    if previewController.rows.isEmpty { return .secondary }
    return .green
}

private var statusText: String {
    if previewController.rows.isEmpty { return "Keine Datei" }
    var parts: [String] = []
    if previewController.duplicateCount > 0 {
        parts.append("\(previewController.duplicateCount) Duplikat\(previewController.duplicateCount == 1 ? "" : "e")")
    }
    if previewController.unreachableCount > 0 {
        parts.append("\(previewController.unreachableCount) nicht erreichbar")
    }
    return parts.isEmpty ? "Bereit" : parts.joined(separator: " · ")
}
```

3. **Bindings im `body` umleiten** — jedes Vorkommen der gelöschten `@State`-Vars durch `previewController.<prop>` bzw. `$previewController.<prop>` ersetzen:
   - `.fileImporter(isPresented: $previewController.isFileImporterPresented, …)` → Aufruf `previewController.loadOPML(from: result, existingFeeds: feeds, feedViewModel: feedViewModel)` im `result`-Closure.
   - `.onDrop(of: [UTType.fileURL.identifier], isTargeted: $previewController.isDropTargeted)` → `previewController.handleDroppedFiles(providers, existingFeeds: feeds, feedViewModel: feedViewModel)` (kein `onValidFile`).
   - `.onChange(of: previewController.allowsDuplicates)` setzt `previewController.rows[i].isSelected` für Duplikate; analog `allowsUnreachable`. (Beide onChange-Handler bleiben als View-Modifier, lesen/schreiben am Controller.)
   - `filePicker`-View: `Text(previewController.selectedFileName)`, `Text(previewController.sourceDescription)` (war `fileDescription`), `Button("Entfernen") { resetFile() }` `.disabled(previewController.rows.isEmpty && previewController.errorMessage == nil)`.
   - `toolbar`: `Text(selectionSummaryText)`, `Picker("Status", selection: $previewController.statusFilter)`, `Button("Alle auswählen") { previewController.selectAllImportableRows() }.disabled(previewController.rows.isEmpty)`, `Button("Alle abwählen") { previewController.deselectVisibleRows() }.disabled(previewController.rows.isEmpty)`, `TextField("Neuer Ordner", text: $previewController.newFolderName)`, `Button("Ordner erstellen") { previewController.createFolder() }.disabled(previewController.newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)`.
   - `feedTable`: `isPreparingPreview`/`rows`/`visibleRowIDs` über `previewController.`. `ForEach($previewController.rows) { $row in … OPMLImportFeedRow(row: $row, selectionOptions: previewController.selectionOptions, availableFolders: previewController.availableFolders(existingFeeds: feeds), layout: .importSheet) … }`.
   - `previewProgressRow`: `Text(previewController.previewProgressText)`.
   - `footer`: `Toggle("…", isOn: $previewController.refreshAfterImport)`, `Toggle("Duplikate importieren", isOn: $previewController.allowsDuplicates)`, `Toggle("Nicht erreichbare Feeds importieren", isOn: $previewController.allowsUnreachable)`, Import-Button `.disabled(previewController.selectedImportRows.isEmpty || previewController.isPreparingPreview || feedViewModel.isLoading)`.
   - `importButtonTitle`: `let count = previewController.selectedImportRows.count`.
   - `resultMessage`/`errorMessage`-Boxen: über `previewController.resultMessage`/`previewController.errorMessage`.

4. **Methoden löschen** (jetzt am Controller): `selectAllImportableRows`, `deselectVisibleRows`, `createFolder`, `trimmedFolderName`, `loadOPML`, `handleDroppedFiles`.

5. **`resetFile` umschreiben** (View-Wrapper um Controller.reset + selectedFileName):

```swift
private func resetFile() {
    previewController.reset()
    previewController.selectedFileName = "Keine OPML-Datei ausgewählt"
}
```

Hinweis: `selectedFileName` ist `private(set)` am Controller, aber `var` mit private-set bedeutet: Schreiben nur innerhalb der Klasse. Damit die View `selectedFileName` setzen darf, **`selectedFileName` in `OPMLImportPreviewController` von `private(set)` auf `internal(set)` oder ganz `var` ändern** (nur diese Property). Wähle `private(set)` entfernen → `var selectedFileName: String` (public set), da OPML `resetFile` es setzt. (FirstRun setzt es nicht, schadet aber nicht.)

6. **`importSelectedFeeds` umschreiben** (bleibt in der View — divergente resultMessage):

```swift
private func importSelectedFeeds() {
    Task {
        do {
            previewController.errorMessage = nil
            previewController.resultMessage = nil
            let selectedRows = previewController.selectedImportRows
            let selectedFeeds = selectedRows.map(\.feed)
            let result = try await feedViewModel.importOPMLFeeds(
                selectedFeeds,
                existingFeeds: feeds,
                allowsDuplicates: previewController.allowsDuplicates,
                refreshAfterImport: previewController.refreshAfterImport,
                refreshIntervalMinutes: backgroundRefreshIntervalMinutes,
                context: modelContext
            )
            let importedDuplicateCount = selectedRows.filter { $0.status == .duplicate }.count
            let duplicateText = importedDuplicateCount > 0
                ? "\(importedDuplicateCount) Duplikate bewusst importiert"
                : "\(previewController.duplicateCount) Duplikate angezeigt und übersprungen"
            let importedUnreachableCount = selectedRows.filter { $0.status == .unreachable }.count
            let unreachableText = importedUnreachableCount > 0
                ? "\(importedUnreachableCount) nicht erreichbare Feeds bewusst importiert"
                : "\(previewController.unreachableCount) nicht erreichbare Feeds angezeigt und übersprungen"
            previewController.resultMessage = "Import abgeschlossen: \(result.imported) Feeds importiert, \(duplicateText), \(unreachableText), \(previewController.folderCount) Ordner verwendet. \(previewController.refreshAfterImport ? "Direktes Aktualisieren ist aktiv." : "Aktualisierung erfolgt später manuell.")"
        } catch {
            previewController.errorMessage = error.localizedDescription
        }
    }
}
```

Hinweis: Schreiben von `errorMessage`/`resultMessage` durch die View → diese sind aktuell `private(set)`. Da beide Views sie schreiben müssen (import-Fehlerbehandlung), **`errorMessage` und `resultMessage` in `OPMLImportPreviewController` von `private(set)` auf `var` (public set) ändern**. (Konsequenterweise: alle `private(set)` Display-Props, die eine View schreibt, öffnen. Das sind: `errorMessage`, `resultMessage`, `selectedFileName`. `sourceDescription`/`previewProgressText`/`isPreparingPreview`/`customFolders` werden nur vom Controller geschrieben → bleiben `private(set)`.)

7. **Private `OPMLImportFeedRow` + `OPMLSecondaryButtonStyle` + `OPMLPrimaryButtonStyle`** am Ende der Datei: Die private `OPMLImportFeedRow` (Zeilen ~724–866) **löschen** — wird durch die neue `OPMLImportFeedRow` ersetzt. Die beiden ButtonStyles **behalten** (werden noch vom Import-Sheet genutzt).

- [ ] **Step 1: Transformation wie oben durchführen**

- [ ] **Step 2: Build prüfen**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Tests laufen lassen**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests test 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **` — alle Tests grün.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/OPMLImport/OPMLImportPreviewController.swift \
        Feedivo/Views/OPMLImport/OPMLImportReviewView.swift
git commit -m "$(cat <<'EOF'
M1 (OPML-Dedup): OPMLImportReviewView an Controller + einheitliche Zeile binden

State/Logik/Helfer an OPMLImportPreviewController delegiert; private Zeilen-
Komponente durch neue OPMLImportFeedRow (Layout .importSheet) ersetzt.
Import-Nachbearbeitung (resultMessage) bleibt pro View. ButtonStyles behalten.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `FirstRunWizardView` an Controller + einheitliche Zeile binden

**Files:**
- Modify: `Feedivo/Views/FirstRun/FirstRunWizardView.swift`

**Interfaces:**
- Consumes: `OPMLImportPreviewController` (Task 1), `OPMLImportFeedRow`/`OPMLImportFeedRowLayout` (Task 2).

**Transformation (alle Änderungen in dieser einen Datei):**

1. **State ersetzen:** Lösche die OPML-bezogenen `@State`-Vars: `selectedFileName`, `sourceDescription`, `previewProgressText`, `rows`, `isPreparingPreview`, `isFileImporterPresented`, `isDropTargeted`, `allowsDuplicates`, `allowsUnreachable`, `refreshAfterImport`, `statusFilter`, `newFolderName`, `customFolders`, `errorMessage`, `resultMessage`. Ersetze durch:

```swift
@State private var previewController = OPMLImportPreviewController(configuration: .firstRun)
```

Behalte: `step`, `inputStep`, `feedURLString`, `completionSummary`, `feeds` (`let`), `feedViewModel` (`let`), `onSkip`/`onComplete` (`let`), `@Environment(\.modelContext)`, die `@AppStorage`-Vars, `tableBodyHeight`/`usesCompactEmptyImportPreview` (computed, bleiben — nutzen `step`/`previewController.rows`/`previewController.isPreparingPreview`).

2. **Computed Props löschen**, die jetzt am Controller sind: `selectionOptions`, `selectedImportRows`, `duplicateCount`, `unreachableCount`, `folderCount`, `availableFolders`, `visibleRowIDs`. Stattdessen überall `previewController.<prop>` lesen. `selectedCountText`/`previewSummaryText` als View-Chrome behalten, aber vom Controller lesen:

```swift
private var selectedCountText: String {
    "Ausgewählt: \(previewController.selectedImportRows.count) von \(previewController.rows.count)"
}
private var previewSummaryText: String {
    "\(previewController.rows.count) Feeds geprüft · \(previewController.duplicateCount) Duplikate · \(previewController.unreachableCount) nicht erreichbar · \(previewController.selectedImportRows.count) ausgewählt"
}
```

`usesCompactEmptyImportPreview` anpassen:

```swift
private var usesCompactEmptyImportPreview: Bool {
    step == .importOPML && previewController.rows.isEmpty && !previewController.isPreparingPreview
}
```

`tableBodyHeight` bleibt (nutzt `usesCompactEmptyImportPreview`).

3. **Bindings im `body` umleiten:**
   - `.fileImporter(isPresented: $previewController.isFileImporterPresented, …)` → im result-Closure: `inputStep = .importOPML; previewController.loadOPML(from: result, existingFeeds: feeds, feedViewModel: feedViewModel)`.
   - `.onDrop(of: [UTType.fileURL.identifier], isTargeted: $previewController.isDropTargeted)` → `previewController.handleDroppedFiles(providers, existingFeeds: feeds, feedViewModel: feedViewModel) { _ in step = .importOPML; inputStep = .importOPML }`.
   - `.onChange(of: previewController.allowsDuplicates)`/`.onChange(of: previewController.allowsUnreachable)` — Handler wie gehabt, aber `previewController.rows[i].isSelected`.
   - `opmlSourceControl`: `Text(previewController.selectedFileName)`, `Text(previewController.sourceDescription)`, `Button("Andere OPML wählen") { previewController.isFileImporterPresented = true }.disabled(previewController.isPreparingPreview)`. Bedingung `if previewController.rows.isEmpty && !previewController.isPreparingPreview` für Drop-Zone.
   - `reviewToolbar`: `Picker("Statusfilter", selection: $previewController.statusFilter)`, `Button("Alle auswählen") { previewController.selectAllImportableRows() }.disabled(previewController.rows.isEmpty || previewController.isPreparingPreview)`, `Button("Alle abwählen") { previewController.deselectVisibleRows() }`, `TextField("Neuer Ordner", text: $previewController.newFolderName).disabled(previewController.isPreparingPreview)`, `Button("Ordner erstellen") { previewController.createFolder() }.disabled(previewController.newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || previewController.isPreparingPreview)`.
   - `feedTable`: `previewController.isPreparingPreview` → `previewProgressRow`; sonst `ForEach($previewController.rows) { $row in … OPMLImportFeedRow(row: $row, selectionOptions: previewController.selectionOptions, availableFolders: previewController.availableFolders(existingFeeds: feeds), layout: .firstRun) … }`. Leerfälle: `previewController.rows.isEmpty` / `previewController.visibleRowIDs.isEmpty`.
   - `previewProgressRow`: `Text(previewController.previewProgressText)`. `.frame(… minHeight: tableBodyHeight + 34 …)` bleibt.
   - `reviewSummaryCard`/`finishSummaryCard`: alle `selectedImportRows`/`duplicateCount`/`unreachableCount`/`folderCount` über `previewController.`
   - `resultBox`/`errorBox`: `previewController.resultMessage`/`previewController.errorMessage`.
   - `footer`/`primaryButtonTitle`/`isPrimaryButtonDisabled`: `previewController.rows.isEmpty`/`previewController.isPreparingPreview`/`previewController.selectedImportRows.isEmpty`/`feedViewModel.isLoading`.
   - `opmlImportOptions`: `Toggle("Duplikate importieren", isOn: $previewController.allowsDuplicates)`, `Toggle("Nicht erreichbare importieren", isOn: $previewController.allowsUnreachable)`, `.disabled(previewController.isPreparingPreview)`.
   - `optionToggles`: `Toggle(… isOn: $previewController.refreshAfterImport)`.
   - `importSummaryText`: nutzt `previewController.selectedImportRows.count`/`folderCount`/`refreshAfterImport`.

4. **Methoden löschen** (jetzt am Controller): `selectAllImportableRows`, `deselectVisibleRows`, `createFolder`, `trimmedFolderName`, `loadOPML`, `handleDroppedFiles`, `preparePreview`. 

5. **`prepareSingleFeedPreview` umschreiben** (ruft Controller.preparePreview):

```swift
private func prepareSingleFeedPreview() {
    let cleanedURL = feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedURL.isEmpty else { return }
    let title = URL(string: cleanedURL)?.host(percentEncoded: false) ?? cleanedURL
    let feed = OPMLFeed(title: title, xmlURL: cleanedURL, htmlURL: nil, folderName: nil)
    inputStep = .addFeed
    previewController.preparePreview(
        feeds: [feed],
        existingFeeds: feeds,
        feedViewModel: feedViewModel,
        sourceText: "Feed-Adresse wird geprüft..."
    )
}
```

6. **`resetPreview` umschreiben** (View-Wrapper):

```swift
private func resetPreview() {
    previewController.reset()
    completionSummary = nil
}
```

7. **`importSelectedFeedsAndComplete` umschreiben** (bleibt in der View — baut `FirstRunCompletionSummary` + step=.finish):

```swift
private func importSelectedFeedsAndComplete() {
    Task {
        do {
            previewController.errorMessage = nil
            previewController.resultMessage = nil
            let selectedRows = previewController.selectedImportRows
            let selectedFeeds = selectedRows.map(\.feed)
            let importedDuplicateCount = selectedRows.filter { $0.status == .duplicate }.count
            let importedUnreachableCount = selectedRows.filter { $0.status == .unreachable }.count
            let result = try await feedViewModel.importOPMLFeeds(
                selectedFeeds,
                existingFeeds: feeds,
                allowsDuplicates: previewController.allowsDuplicates,
                refreshAfterImport: previewController.refreshAfterImport,
                refreshIntervalMinutes: backgroundRefreshIntervalMinutes,
                context: modelContext
            )
            completionSummary = FirstRunCompletionSummary(
                importedFeeds: result.imported,
                folderCount: previewController.folderCount,
                skippedDuplicates: result.skippedDuplicates,
                importedDuplicates: importedDuplicateCount,
                importedUnreachable: importedUnreachableCount,
                refreshAfterImport: previewController.refreshAfterImport,
                refreshProblemMessage: feedViewModel.errorMessage
            )
            previewController.resultMessage = nil
            step = .finish
        } catch {
            completionSummary = FirstRunCompletionSummary(
                importedFeeds: 0,
                folderCount: previewController.folderCount,
                skippedDuplicates: 0,
                importedDuplicates: 0,
                importedUnreachable: 0,
                refreshAfterImport: previewController.refreshAfterImport,
                refreshProblemMessage: error.localizedDescription
            )
            previewController.errorMessage = nil
            step = .finish
        }
    }
}
```

8. **Private `FirstRunImportFeedRow` am Ende der Datei (Zeilen ~1237–1360) löschen** — ersetzt durch `OPMLImportFeedRow` (Layout `.firstRun`). Alle anderen privaten Hilfs-Structs (`FirstRunChoiceCard`, `FirstRunStepItem`, `FirstRunCompletionSummary`, `FirstRunTrafficDot`, `FirstRunStepRow`, `FirstRunSettingsLine`, `FirstRunSegmentButtonStyle`) **behalten**.

- [ ] **Step 1: Transformation wie oben durchführen**

- [ ] **Step 2: Build prüfen**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Tests laufen lassen**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests test 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/FirstRun/FirstRunWizardView.swift
git commit -m "$(cat <<'EOF'
M1 (OPML-Dedup): FirstRunWizardView an Controller + einheitliche Zeile binden

OPML-State/Logik/Helfer an OPMLImportPreviewController delegiert; private
FirstRunImportFeedRow durch neue OPMLImportFeedRow (Layout .firstRun) ersetzt.
Step-Nähte (inputStep im fileImporter, step via onValidFile-Closure) und
FirstRunCompletionSummary bleiben pro View erhalten.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: finale Verifikation

**Files:** keine.

- [ ] **Step 1: Voll-Suite seriell laufen lassen**

Run: `xcodebuild -scheme Feedivo -destination 'platform=macOS' -resultBundlePath /tmp/feedivo-tests-final test 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **` — alle bisherigen Tests (incl. der 9 neuen Controller-Tests, `OPMLImportStatusFilterTests`, `FirstRunWizardStateTests`) grün.

- [ ] **Step 2: Manuellem Spot-Check-Hinweis dokumentieren**

Prüfe manuell (nicht Teil der automatisierten Verifikation, aber vor Merge): Import-Sheet öffnen (Menü/Toolbar „Feed hinzufügen" → OPML-Import); FirstRun-Wizard (leere DB); jeweils: Datei auswählen, Drop, Statusfilter, Alle auswählen/abwählen, Ordner erstellen, Import. Keine nutzer­sichtbare Veränderung zur vorherigen Version.

- [ ] **Step 3: Memory aktualisieren (optional, nach Merge)**

In `code-review-full-codebase-2026-06.md` den M1-Eintrag als done markieren (Commit-SHA eintragen) und `MEMORY.md`-Index „offen: nur M1" entfernen. Damit ist das gesamte 66-Funde-Review abgeschlossen.

- [ ] **Step 4: Push (vom Nutzer freigegeben)**

```bash
git push origin main
```

---

## Self-Review

- **Spec coverage:** Controller (State/Logik/Helfer/async/Config) → Task 1. Einheitliche Zeile + Layout-Config → Task 2. OPMLImportReviewView-Bindung + resultMessage + resetFile + selectedFileName public-set → Task 3. FirstRunWizardView-Bindung + Step-Nähte + prepareSingleFeedPreview + resetPreview + importSelectedFeedsAndComplete → Task 4. Tests → Task 1. Verifikation → Task 5. Alle Spec-Punkte abgedeckt.
- **Placeholder scan:** Keine TBD/TODO; alle Code-Schritte enthalten vollständigen Code oder konkrete Transformationsanweisungen mit Code-Snippets.
- **Type consistency:** `OPMLImportPreviewController`-Signaturen (Properties/Methoden) sind in Task 1 definiert und in Tasks 3/4 identisch verwendet. `OPMLImportFeedRow`/`OPMLImportFeedRowLayout` (Task 2) identisch in Tasks 3/4. `selectedFileName`/`errorMessage`/`resultMessage` in Task 1 als `private(set)` deklariert → Task 3 vermerkt die notwendige Aufweichung auf `var` (public set); explizit ausformuliert, kein Widerspruch.
- **Eine Abweichung vom Spec** bewusst vorgenommen und im Plan notiert: `loadOPML` braucht **kein** `onStart`-Closure (FirstRun setzt `inputStep` direkt im fileImporter-Handler); nur `handleDroppedFiles` bekommt `onValidFile`. Spec hatte `onStart` noch gelistet — hier gestrichen, weil überflüssig.