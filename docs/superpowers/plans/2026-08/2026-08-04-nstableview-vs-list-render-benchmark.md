# NSTableView-vs-List-Render-Benchmark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein `#if DEBUG`-only, von der Produktion vollständig isolierter Vergleichs-Spike, der eine SwiftUI-`List`-Baseline und einen NetNewsWire-artigen `NSTableView`-Prototyp auf identischen, synthetischen Artikeldaten gegenüberstellt — als Entscheidungsgrundlage für eine mögliche künftige Migration der produktiven Artikelliste.

**Architecture:** Ein synthetischer Fixture-Generator erzeugt 1000 `ArticleListSnapshot`-Werte ohne DB-Zugriff. Die Baseline rendert sie unverändert über das bestehende `ArticleRowView` in einer `List`. Der Prototyp rendert sie über einen `NSViewRepresentable`-gewrappten `NSTableView` mit echten `NSTableCellView`-Zellen (keine `NSHostingView`), fester Zeilenhöhe (`ArticleRowHeightMetrics`, unverändert wiederverwendet) und eigenem, per Lade-Token gegen Zell-Wiederverwendung abgesichertem Bild-Laden über `ImageCacheService.shared`. Ein `#if DEBUG`-only Fenster mit Umschalter macht beide Varianten live unter Instruments vergleichbar.

**Tech Stack:** Swift, SwiftUI, AppKit (`NSTableView`, `NSTableCellView`, `NSViewRepresentable`), Swift Testing (`@Test`/`#expect`, kein XCTest), GRDB (unverändert, nicht betroffen).

## Global Constraints

- Alles Neue liegt hinter `#if DEBUG` — kein Symbol darf im Release-Build existieren oder erreichbar sein.
- `Feedivo/Views/ArticleList/SQLiteFeedArticleListView.swift` (produktive Artikelliste) wird **nicht** verändert — der Spike ist vollständig separat.
- Kein Datenbankzugriff im Benchmark — Fixture-Daten sind rein synthetisch, direkt in Swift konstruiert.
- `ArticleRowHeightMetrics.height(...)` und `ImageCacheService.shared` werden unverändert wiederverwendet, nicht dupliziert.
- Kein Kontextmenü, kein Drag&Drop, keine Sticky-Rows, keine Tastatur-Navigation im Prototyp (explizit außerhalb des Scopes laut Spec).
- Neue Tests nutzen Swift Testing (`import Testing`, `@Test`, `#expect`), analog zur gesamten bestehenden Testsuite — kein XCTest.
- Kommentare im Code auf Deutsch (Projektkonvention, siehe `CLAUDE.md`).
- Alle neuen Dateien liegen unter `Feedivo/Views/ArticleList/RenderBenchmark/`, damit der komplette Spike später mit einem einzigen Löschvorgang (Ordner + eine `Window`-Scene-Zeile in `FeedivoApp.swift` + ein Testfile) rückstandsfrei entfernbar ist.

---

### Task 1: Synthetisches Fixture

**Files:**
- Create: `Feedivo/Views/ArticleList/RenderBenchmark/ArticleListRenderBenchmarkFixture.swift`
- Test: `FeedivoTests/ArticleListRenderBenchmarkFixtureTests.swift`

**Interfaces:**
- Produziert: `ArticleListRenderBenchmarkFixture.defaultCount: Int` (= 1000), `ArticleListRenderBenchmarkFixture.makeSnapshots(count: Int = defaultCount) -> [ArticleListSnapshot]`, `ArticleListRenderBenchmarkFixture.makeSnapshot(index: Int) -> ArticleListSnapshot`.

- [ ] **Step 1: Schreibe den fehlschlagenden Test**

```swift
import Testing
@testable import Feedivo

@Suite("ArticleListRenderBenchmarkFixture")
struct ArticleListRenderBenchmarkFixtureTests {
    @Test func defaultCountIst1000() {
        #expect(ArticleListRenderBenchmarkFixture.defaultCount == 1_000)
    }

    @Test func makeSnapshotsErzeugtDieAngeforderteAnzahl() {
        let snapshots = ArticleListRenderBenchmarkFixture.makeSnapshots(count: 250)
        #expect(snapshots.count == 250)
    }

    @Test func makeSnapshotsErzeugtEindeutigeIDs() {
        let snapshots = ArticleListRenderBenchmarkFixture.makeSnapshots(count: 500)
        #expect(Set(snapshots.map(\.id)).count == 500)
    }

    @Test func makeSnapshotsMischtArtikelMitUndOhneBild() {
        let snapshots = ArticleListRenderBenchmarkFixture.makeSnapshots(count: 100)
        #expect(snapshots.contains { $0.imageURL != nil })
        #expect(snapshots.contains { $0.imageURL == nil })
    }

    @Test func makeSnapshotsMischtArtikelMitUndOhneSummary() {
        let snapshots = ArticleListRenderBenchmarkFixture.makeSnapshots(count: 100)
        #expect(snapshots.contains { $0.summary != nil })
        #expect(snapshots.contains { $0.summary == nil })
    }

    @Test func makeSnapshotsMischtGelesenUndUngelesen() {
        let snapshots = ArticleListRenderBenchmarkFixture.makeSnapshots(count: 100)
        #expect(snapshots.contains { $0.isRead })
        #expect(snapshots.contains { !$0.isRead })
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -scheme Feedivo -configuration Debug -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListRenderBenchmarkFixtureTests`
Expected: FAIL — `ArticleListRenderBenchmarkFixture` existiert noch nicht (Compile-Fehler).

- [ ] **Step 3: Implementiere den Fixture-Generator**

```swift
import Foundation

#if DEBUG
/// Erzeugt einen deterministischen, rein synthetischen Satz von
/// `ArticleListSnapshot`s für den NSTableView-vs-List-Render-Benchmark
/// (docs/superpowers/specs/2026-08/2026-08-04-nstableview-vs-list-render-benchmark-design.md).
/// Bewusst ohne Datenbankzugriff — die SQL-Schicht ist laut
/// docs/performance/sqlite-large-dataset-results.md bereits nachweislich
/// schnell, dieser Benchmark isoliert ausschließlich die Render-Variable.
enum ArticleListRenderBenchmarkFixture {
    static let defaultCount = 1_000

    static func makeSnapshots(count: Int = defaultCount) -> [ArticleListSnapshot] {
        (0 ..< count).map(makeSnapshot)
    }

    static func makeSnapshot(index: Int) -> ArticleListSnapshot {
        let feedIndex = index % 25
        let hasImage = index % 3 != 0
        let hasSummary = index % 4 != 0
        let titleWordCount = 3 + (index % 6)
        let summaryWordCount = 8 + (index % 12)
        let publishedAt = Date(timeIntervalSinceReferenceDate: TimeInterval(-index * 3_600))

        return ArticleListSnapshot(
            id: "benchmark-article-\(index)",
            feedID: "benchmark-feed-\(feedIndex)",
            feedTitle: "Benchmark-Feed \(feedIndex)",
            title: makeWords(prefix: "Titelwort", wordCount: titleWordCount, seed: index),
            summary: hasSummary ? makeWords(prefix: "Zusammenfassung", wordCount: summaryWordCount, seed: index) : nil,
            link: "https://example.com/benchmark/article/\(index)",
            imageURL: hasImage ? "https://example.com/benchmark/image/\(index).jpg" : nil,
            publishedAt: publishedAt,
            arrivedAt: publishedAt,
            estimatedReadingMinutes: hasSummary ? 1 + (index % 8) : nil,
            isRead: index % 5 == 0,
            isStarred: index % 11 == 0,
            isArchived: false,
            isHidden: false,
            faviconURL: hasImage ? "https://example.com/benchmark/favicon/\(feedIndex).png" : nil
        )
    }

    private static func makeWords(prefix: String, wordCount: Int, seed: Int) -> String {
        (0 ..< wordCount)
            .map { "\(prefix)-\(seed)-\($0)" }
            .joined(separator: " ")
    }
}
#endif
```

- [ ] **Step 4: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild test -scheme Feedivo -configuration Debug -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListRenderBenchmarkFixtureTests`
Expected: PASS, 6/6 Tests grün.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/ArticleList/RenderBenchmark/ArticleListRenderBenchmarkFixture.swift FeedivoTests/ArticleListRenderBenchmarkFixtureTests.swift
git commit -m "feat: synthetisches Fixture für NSTableView-vs-List-Render-Benchmark"
```

---

### Task 2: Stale-Load-Guard für Bild-Zellwiederverwendung

**Files:**
- Create: `Feedivo/Views/ArticleList/RenderBenchmark/NativeArticleImageLoadGuard.swift`
- Test: `FeedivoTests/NativeArticleImageLoadGuardTests.swift`

**Interfaces:**
- Produziert: `NativeArticleImageLoadGuard.shouldApplyLoadedImage(requestedToken: Int, currentToken: Int) -> Bool`
- Wird konsumiert von: Task 3 (`NativeArticleRowCellView.configure(...)`).

- [ ] **Step 1: Schreibe den fehlschlagenden Test**

```swift
import Testing
@testable import Feedivo

@Suite("NativeArticleImageLoadGuard")
struct NativeArticleImageLoadGuardTests {
    @Test func erlaubtAnwendungBeiGleichemToken() {
        #expect(NativeArticleImageLoadGuard.shouldApplyLoadedImage(requestedToken: 3, currentToken: 3))
    }

    @Test func verwirftAnwendungBeiVeraltetemToken() {
        #expect(!NativeArticleImageLoadGuard.shouldApplyLoadedImage(requestedToken: 2, currentToken: 3))
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -scheme Feedivo -configuration Debug -destination 'platform=macOS' -only-testing:FeedivoTests/NativeArticleImageLoadGuardTests`
Expected: FAIL — Typ existiert noch nicht.

- [ ] **Step 3: Implementiere die reine Guard-Funktion**

```swift
#if DEBUG
/// Verhindert, dass ein asynchron geladenes Bild noch auf eine
/// `NativeArticleRowCellView` angewendet wird, die inzwischen (durch
/// `NSTableView`-Zellwiederverwendung) für eine andere Zeile/URL
/// wiederverwendet wurde. Analog zum bestehenden Stale-URL-Guard in
/// `CachedRemoteImageView.loadImage()` (SwiftUI-Seite), hier als reine,
/// isoliert testbare Funktion für die AppKit-Seite des Benchmarks.
enum NativeArticleImageLoadGuard {
    static func shouldApplyLoadedImage(requestedToken: Int, currentToken: Int) -> Bool {
        requestedToken == currentToken
    }
}
#endif
```

- [ ] **Step 4: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild test -scheme Feedivo -configuration Debug -destination 'platform=macOS' -only-testing:FeedivoTests/NativeArticleImageLoadGuardTests`
Expected: PASS, 2/2 Tests grün.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/ArticleList/RenderBenchmark/NativeArticleImageLoadGuard.swift FeedivoTests/NativeArticleImageLoadGuardTests.swift
git commit -m "feat: Stale-Load-Guard für native Artikel-Zellwiederverwendung"
```

---

### Task 3: Native AppKit-Zelle

**Files:**
- Create: `Feedivo/Views/ArticleList/RenderBenchmark/NativeArticleRowCellView.swift`

**Interfaces:**
- Konsumiert: `NativeArticleImageLoadGuard.shouldApplyLoadedImage(requestedToken:currentToken:)` (Task 2), `ArticleListSnapshot` (bestehend), `ImageCacheService.shared.image(for:targetPixelSize:)`/`.image(for:)` (bestehend, unverändert).
- Produziert: `final class NativeArticleRowCellView: NSTableCellView` mit `func configure(with snapshot: ArticleListSnapshot, onToggleStarred: @escaping () -> Void)`.

Kein dedizierter Unit-Test in diesem Task — reines AppKit-Layout ist ohne laufendes Fenster nicht sinnvoll isoliert testbar; die funktionale Absicherung (Zellwiederverwendung, Datenanzeige) läuft über Task 4s Coordinator-Tests und die manuelle Instruments-Verifikation. Verifikation hier ausschließlich über den Build.

- [ ] **Step 1: Implementiere die Zelle**

```swift
import AppKit

#if DEBUG
/// NetNewsWire-artige, rein native Artikel-Zeile für den Render-Benchmark —
/// bewusst OHNE `NSHostingView`/SwiftUI, um echte `NSTableView`-
/// Zellwiederverwendung zu ermöglichen (siehe Design-Doc, Abschnitt 3).
final class NativeArticleRowCellView: NSTableCellView {
    private let unreadIndicator = NSView()
    private let previewImageView = NSImageView()
    private let faviconImageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let metadataField = NSTextField(labelWithString: "")
    private let summaryField = NSTextField(labelWithString: "")
    private let starButton = NSButton(image: NSImage(), target: nil, action: nil)

    private lazy var metadataRow = NSStackView(views: [faviconImageView, metadataField])
    private lazy var textStack = NSStackView(views: [titleField, metadataRow, summaryField])
    private lazy var rootStack = NSStackView(views: [unreadIndicator, previewImageView, textStack, starButton])

    /// Erhöht sich bei jedem `configure(...)`-Aufruf — dient
    /// `NativeArticleImageLoadGuard` als "aktueller Stand dieser Zelle".
    private var currentLoadToken = 0
    private var starButtonAction: (() -> Void)?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayout()
    }

    private func configureLayout() {
        rootStack.orientation = .horizontal
        rootStack.alignment = .top
        rootStack.spacing = 8
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6)
        ])

        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        metadataRow.orientation = .horizontal
        metadataRow.alignment = .centerY
        metadataRow.spacing = 4

        unreadIndicator.wantsLayer = true
        unreadIndicator.layer?.cornerRadius = 4
        NSLayoutConstraint.activate([
            unreadIndicator.widthAnchor.constraint(equalToConstant: 8),
            unreadIndicator.heightAnchor.constraint(equalToConstant: 8)
        ])

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([
            previewImageView.widthAnchor.constraint(equalToConstant: 56),
            previewImageView.heightAnchor.constraint(equalToConstant: 56)
        ])

        faviconImageView.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([
            faviconImageView.widthAnchor.constraint(equalToConstant: 11),
            faviconImageView.heightAnchor.constraint(equalToConstant: 11)
        ])

        titleField.maximumNumberOfLines = 2
        titleField.lineBreakMode = .byTruncatingTail

        metadataField.font = .systemFont(ofSize: 11)
        metadataField.textColor = .secondaryLabelColor

        summaryField.font = .systemFont(ofSize: 13)
        summaryField.textColor = .secondaryLabelColor
        summaryField.lineBreakMode = .byTruncatingTail

        starButton.imagePosition = .imageOnly
        starButton.isBordered = false
        starButton.target = self
        starButton.action = #selector(starButtonTapped)
        NSLayoutConstraint.activate([
            starButton.widthAnchor.constraint(equalToConstant: 24),
            starButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    func configure(with snapshot: ArticleListSnapshot, onToggleStarred: @escaping () -> Void) {
        currentLoadToken += 1
        let loadToken = currentLoadToken
        starButtonAction = onToggleStarred

        unreadIndicator.layer?.backgroundColor = snapshot.isRead
            ? NSColor.clear.cgColor
            : NSColor.controlAccentColor.cgColor

        titleField.stringValue = snapshot.title
        titleField.font = .systemFont(ofSize: 14, weight: snapshot.isRead ? .regular : .semibold)
        titleField.textColor = snapshot.isRead ? .secondaryLabelColor : .labelColor

        metadataField.stringValue = [
            snapshot.feedTitle,
            snapshot.publishedAt.map(Self.dateFormatter.string)
        ]
        .compactMap { $0 }
        .joined(separator: " · ")

        summaryField.stringValue = snapshot.summary ?? ""
        summaryField.isHidden = snapshot.summary == nil

        starButton.image = NSImage(
            systemSymbolName: snapshot.isStarred ? "star.fill" : "star",
            accessibilityDescription: nil
        )

        previewImageView.image = nil
        faviconImageView.image = nil

        if let imageURLString = snapshot.imageURL, let imageURL = URL(string: imageURLString) {
            Task { [weak self] in
                let image = await ImageCacheService.shared.image(
                    for: imageURL,
                    targetPixelSize: CGSize(width: 112, height: 112)
                )
                guard let self,
                      NativeArticleImageLoadGuard.shouldApplyLoadedImage(
                          requestedToken: loadToken,
                          currentToken: self.currentLoadToken
                      )
                else { return }
                self.previewImageView.image = image
            }
        }

        if let faviconURLString = snapshot.faviconURL, let faviconURL = URL(string: faviconURLString) {
            Task { [weak self] in
                let image = await ImageCacheService.shared.image(for: faviconURL)
                guard let self,
                      NativeArticleImageLoadGuard.shouldApplyLoadedImage(
                          requestedToken: loadToken,
                          currentToken: self.currentLoadToken
                      )
                else { return }
                self.faviconImageView.image = image
            }
        }
    }

    @objc private func starButtonTapped() {
        starButtonAction?()
    }
}
#endif
```

- [ ] **Step 2: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Feedivo/Views/ArticleList/RenderBenchmark/NativeArticleRowCellView.swift
git commit -m "feat: native AppKit-Zelle für Artikel-Render-Benchmark"
```

---

### Task 4: NSTableView-Wrapper mit Coordinator

**Files:**
- Create: `Feedivo/Views/ArticleList/RenderBenchmark/NativeArticleTableView.swift`
- Test: `FeedivoTests/NativeArticleTableViewCoordinatorTests.swift`

**Interfaces:**
- Konsumiert: `NativeArticleRowCellView` (Task 3), `ArticleRowHeightMetrics.height(...)` (bestehend, unverändert), `ArticleListSummaryLineCount.defaultValue` (bestehend), `ArticleListSnapshot` (bestehend).
- Produziert: `struct NativeArticleTableView: NSViewRepresentable` mit `init(snapshots: [ArticleListSnapshot], selectedID: Binding<String?>, onToggleStarred: @escaping (String) -> Void)`; öffentlich erreichbare `final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate` mit `var snapshots: [ArticleListSnapshot]`, `var onSelectionChanged: ((String?) -> Void)?`, `var onToggleStarred: ((String) -> Void)?`.
- Wird konsumiert von: Task 5 (`ArticleListRenderBenchmarkView`), Task 7 (Proxy-Metrik-Test).

- [ ] **Step 1: Schreibe den fehlschlagenden Test**

```swift
import AppKit
import Testing
@testable import Feedivo

@Suite("NativeArticleTableViewCoordinator")
struct NativeArticleTableViewCoordinatorTests {
    @Test func numberOfRowsEntsprichtAnzahlSnapshots() {
        let coordinator = NativeArticleTableView.Coordinator()
        coordinator.snapshots = ArticleListRenderBenchmarkFixture.makeSnapshots(count: 42)

        #expect(coordinator.numberOfRows(in: NSTableView()) == 42)
    }

    @Test func tableViewSelectionDidChangeMeldetAusgewaehlteID() {
        let coordinator = NativeArticleTableView.Coordinator()
        coordinator.snapshots = ArticleListRenderBenchmarkFixture.makeSnapshots(count: 5)
        var reportedID: String?
        coordinator.onSelectionChanged = { reportedID = $0 }

        let tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
        tableView.dataSource = coordinator
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)

        coordinator.tableViewSelectionDidChange(
            Notification(name: NSTableView.selectionDidChangeNotification, object: tableView)
        )

        #expect(reportedID == coordinator.snapshots[2].id)
    }

    @Test func tableViewSelectionDidChangeMeldetNilBeiAbwahl() {
        let coordinator = NativeArticleTableView.Coordinator()
        coordinator.snapshots = ArticleListRenderBenchmarkFixture.makeSnapshots(count: 5)
        var reportedID: String? = "not-nil-initially"
        coordinator.onSelectionChanged = { reportedID = $0 }

        let tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
        tableView.dataSource = coordinator
        tableView.reloadData()
        tableView.deselectAll(nil)

        coordinator.tableViewSelectionDidChange(
            Notification(name: NSTableView.selectionDidChangeNotification, object: tableView)
        )

        #expect(reportedID == nil)
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag verifizieren**

Run: `xcodebuild test -scheme Feedivo -configuration Debug -destination 'platform=macOS' -only-testing:FeedivoTests/NativeArticleTableViewCoordinatorTests`
Expected: FAIL — `NativeArticleTableView` existiert noch nicht.

- [ ] **Step 3: Implementiere den Wrapper**

```swift
import AppKit
import SwiftUI

#if DEBUG
/// NSTableView-basierter Prototyp für den Render-Benchmark — Gegenstück zur
/// SwiftUI-`List`-Baseline (`ArticleListRenderBenchmarkBaselineView`). Rendert
/// dieselben Snapshots über echte `NSTableCellView`-Zellen statt gehosteter
/// SwiftUI-Views.
struct NativeArticleTableView: NSViewRepresentable {
    let snapshots: [ArticleListSnapshot]
    @Binding var selectedID: String?
    let onToggleStarred: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
        tableView.headerView = nil
        tableView.usesAutomaticRowHeights = false
        tableView.rowHeight = ArticleRowHeightMetrics.height(
            interfaceTextSize: .standard,
            imagePosition: .left,
            summaryLineCount: ArticleListSummaryLineCount.defaultValue
        )
        tableView.selectionHighlightStyle = .regular
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.snapshots = snapshots
        context.coordinator.onSelectionChanged = { selectedID = $0 }
        context.coordinator.onToggleStarred = onToggleStarred

        guard let tableView = nsView.documentView as? NSTableView else { return }
        tableView.reloadData()

        if let selectedID, let index = snapshots.firstIndex(where: { $0.id == selectedID }) {
            if tableView.selectedRow != index {
                tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            }
        } else if tableView.selectedRow != -1 {
            tableView.deselectAll(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var snapshots: [ArticleListSnapshot] = []
        var onSelectionChanged: ((String?) -> Void)?
        var onToggleStarred: ((String) -> Void)?

        func numberOfRows(in tableView: NSTableView) -> Int {
            snapshots.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("NativeArticleRowCellView")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NativeArticleRowCellView)
                ?? NativeArticleRowCellView(frame: .zero)
            cell.identifier = identifier

            let snapshot = snapshots[row]
            cell.configure(with: snapshot) { [weak self] in
                self?.onToggleStarred?(snapshot.id)
            }
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            let selectedRow = tableView.selectedRow
            let selectedID = (selectedRow >= 0 && selectedRow < snapshots.count) ? snapshots[selectedRow].id : nil
            onSelectionChanged?(selectedID)
        }
    }
}
#endif
```

- [ ] **Step 4: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild test -scheme Feedivo -configuration Debug -destination 'platform=macOS' -only-testing:FeedivoTests/NativeArticleTableViewCoordinatorTests`
Expected: PASS, 3/3 Tests grün.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/Views/ArticleList/RenderBenchmark/NativeArticleTableView.swift FeedivoTests/NativeArticleTableViewCoordinatorTests.swift
git commit -m "feat: NSTableView-Wrapper + Coordinator für Artikel-Render-Benchmark"
```

---

### Task 5: SwiftUI-Baseline und Umschalter-Container

**Files:**
- Create: `Feedivo/Views/ArticleList/RenderBenchmark/ArticleListRenderBenchmarkBaselineView.swift`
- Create: `Feedivo/Views/ArticleList/RenderBenchmark/ArticleListRenderBenchmarkView.swift`

**Interfaces:**
- Konsumiert: `ArticleRowView` (bestehend, unverändert), `ArticleListItemSnapshot(sqliteSnapshot:)` (bestehend), `ArticleListRenderBenchmarkFixture.makeSnapshots()` (Task 1), `NativeArticleTableView` (Task 4).
- Produziert: `struct ArticleListRenderBenchmarkBaselineView: View` mit `init(snapshots: [ArticleListSnapshot], selectedID: Binding<String?>)`; `struct ArticleListRenderBenchmarkView: View` mit `static let windowID: String`.
- Wird konsumiert von: Task 6 (`FeedivoApp.swift`).

Kein dedizierter Unit-Test — reine SwiftUI-Kompositionsviews ohne eigene Logik; Verifikation über Build + die manuelle Instruments-Live-Verifikation aus der Spec (Abschnitt 5).

- [ ] **Step 1: Implementiere die Baseline-View**

```swift
import SwiftUI

#if DEBUG
/// SwiftUI-`List`-Baseline für den Render-Benchmark — rendert dieselben
/// Snapshots wie `NativeArticleTableView`, aber über das unveränderte,
/// produktive `ArticleRowView`.
struct ArticleListRenderBenchmarkBaselineView: View {
    let snapshots: [ArticleListSnapshot]
    @Binding var selectedID: String?

    var body: some View {
        List(selection: $selectedID) {
            ForEach(snapshots) { snapshot in
                ArticleRowView(
                    snapshot: ArticleListItemSnapshot(sqliteSnapshot: snapshot),
                    hasAvailableTags: false,
                    onToggleRead: {},
                    onToggleStarred: {},
                    onToggleArchived: {},
                    onRequestAssignTag: {},
                    onCreateRule: {},
                    onCopyLink: {},
                    onOpenOriginal: {},
                    onShareOriginal: {},
                    onOpenInNewTab: {},
                    onOpenInWindow: {},
                    onExport: {},
                    onDelete: {},
                    onMarkAllRead: {}
                )
                .tag(snapshot.id)
            }
        }
    }
}
#endif
```

- [ ] **Step 2: Implementiere den Umschalter-Container**

```swift
import SwiftUI

#if DEBUG
/// Debug-only Fenster-Inhalt für den NSTableView-vs-List-Render-Benchmark
/// (docs/superpowers/specs/2026-08/2026-08-04-nstableview-vs-list-render-benchmark-design.md).
/// Erlaubt das Umschalten zwischen Baseline und Prototyp im laufenden
/// Debug-Build, ohne die App neu zu starten — gedacht für Instruments-Traces
/// gegen dieselben 1000 synthetischen Zeilen.
struct ArticleListRenderBenchmarkView: View {
    static let windowID = "render-benchmark"

    enum Variant: String, CaseIterable, Identifiable {
        case baseline
        case native

        var id: String { rawValue }

        var title: String {
            switch self {
            case .baseline: "SwiftUI List (Baseline)"
            case .native: "NSTableView (Prototyp)"
            }
        }
    }

    @State private var variant: Variant = .baseline
    @State private var selectedID: String?
    private let snapshots = ArticleListRenderBenchmarkFixture.makeSnapshots()

    var body: some View {
        VStack(spacing: 0) {
            Picker("Variante", selection: $variant) {
                ForEach(Variant.allCases) { variant in
                    Text(variant.title).tag(variant)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch variant {
            case .baseline:
                ArticleListRenderBenchmarkBaselineView(snapshots: snapshots, selectedID: $selectedID)
            case .native:
                NativeArticleTableView(
                    snapshots: snapshots,
                    selectedID: $selectedID,
                    onToggleStarred: { _ in }
                )
            }
        }
        .frame(minWidth: 420, minHeight: 500)
    }
}
#endif
```

- [ ] **Step 3: Build verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Feedivo/Views/ArticleList/RenderBenchmark/ArticleListRenderBenchmarkBaselineView.swift Feedivo/Views/ArticleList/RenderBenchmark/ArticleListRenderBenchmarkView.swift
git commit -m "feat: SwiftUI-Baseline + Umschalter-Container für Artikel-Render-Benchmark"
```

---

### Task 6: Debug-Fenster und Menüeintrag

**Files:**
- Modify: `Feedivo/App/FeedivoApp.swift`

**Interfaces:**
- Konsumiert: `ArticleListRenderBenchmarkView` (Task 5), `ArticleListRenderBenchmarkView.windowID` (Task 5), bestehendes `openWindow`-Environment-Value (bereits im Body verwendet, z. B. `openWindow(id: "main")`).

Kein Unit-Test möglich — reine SwiftUI-`Scene`/`Commands`-Verdrahtung auf App-Ebene. Verifikation über Build + manuellen Start des Debug-Builds (Öffnen des Fensters über den neuen Menüeintrag).

- [ ] **Step 1: Ergänze die Debug-only Window-Scene**

In `Feedivo/App/FeedivoApp.swift`, direkt nach dem bestehenden Block für `CleanupHistoryWindowView` (vor `WindowGroup(for: ArticleWindowRequest.self)`) einfügen:

```swift
#if DEBUG
Window("Render-Benchmark", id: ArticleListRenderBenchmarkView.windowID) {
    ArticleListRenderBenchmarkView()
        .environment(\.locale, appLanguage.locale)
        .environment(\.interfaceTextSize, interfaceTextSize)
        .environment(\.feedivoDatabase, feedivoDatabase)
        .dynamicTypeSize(interfaceTextSize.dynamicTypeSize)
        .preferredColorScheme(appAppearance.colorScheme)
}
.defaultSize(width: 480, height: 640)
#endif
```

- [ ] **Step 2: Ergänze den Debug-only Menüeintrag**

Innerhalb des bestehenden `.commands { ... }`-Blocks, direkt vor dem abschließenden `CommandGroup(replacing: .printItem) {}` einfügen:

```swift
#if DEBUG
CommandGroup(after: .toolbar) {
    Button("Render-Benchmark öffnen") {
        openWindow(id: ArticleListRenderBenchmarkView.windowID)
    }
}
#endif
```

- [ ] **Step 3: Debug-Build erzeugen und manuell verifizieren**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Expected: `BUILD SUCCEEDED`.

Danach manuell (nicht automatisierbar — kein computer-use für native macOS-Apps): App starten, Menüeintrag "Render-Benchmark öffnen" anklicken, prüfen dass sich das Fenster öffnet und der Segmented-Control zwischen Baseline und Prototyp umschaltet.

- [ ] **Step 4: Release-Build verifizieren, dass der Menüeintrag/das Fenster NICHT existiert**

Run: `xcodebuild build -scheme Feedivo -configuration Release`
Expected: `BUILD SUCCEEDED` — und per Grep-Kontrolle auf das erzeugte `.app`-Bundle (`strings` auf das Binary) sicherstellen, dass "Render-Benchmark" dort nicht auftaucht:

```bash
strings /Users/martinfelder/Library/Developer/Xcode/DerivedData/Feedivo-*/Build/Products/Release/Feedivo.app/Contents/MacOS/Feedivo | grep -c "Render-Benchmark"
```

Expected: `0`.

- [ ] **Step 5: Commit**

```bash
git add Feedivo/App/FeedivoApp.swift
git commit -m "feat: Debug-only Fenster + Menüeintrag für Artikel-Render-Benchmark"
```

---

### Task 7: Automatisierte Proxy-Metrik und Abschlussverifikation

**Files:**
- Create: `FeedivoTests/ArticleListRenderBenchmarkTests.swift`
- Modify: `CLAUDE.md` (Abschnitt "Aktuell in Arbeit")

**Interfaces:**
- Konsumiert: `ArticleListRenderBenchmarkFixture.makeSnapshots(count:)` (Task 1), `NativeArticleTableView.Coordinator` (Task 4), `ArticleRowHeightMetrics.height(...)` (bestehend).

- [ ] **Step 1: Schreibe den Proxy-Metrik-Test**

```swift
import AppKit
import Testing
@testable import Feedivo

private func measureMilliseconds<T>(
    _ name: String,
    _ block: () -> T
) -> (value: T, milliseconds: Double) {
    let start = ProcessInfo.processInfo.systemUptime
    let result = block()
    let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1_000
    print(String(format: "PERF_METRIC %@ %.3f ms", name, elapsed))
    return (result, elapsed)
}

@Suite("ArticleListRenderBenchmark")
struct ArticleListRenderBenchmarkTests {
    // Bewusst nur eine Proxy-Metrik für die AppKit-Seite (siehe Design-Doc,
    // Abschnitt 5): eine vergleichbar faire, headless Messung für die
    // SwiftUI-`List`-Seite ist technisch nicht zuverlässig möglich, da `List`
    // ihren internen Render-Server erst mit einem echten Fenster/Compositor
    // aufbaut. Diese Zahl ist ein Regressions-Wächter für den Prototyp
    // selbst, kein A/B-Beweis gegen die Baseline — der eigentliche Vergleich
    // läuft über die manuelle Instruments-Messung.
    @Test func nativeTableViewLayoutMitTausendZeilenBleibtSchnell() {
        let snapshots = ArticleListRenderBenchmarkFixture.makeSnapshots(count: 1_000)
        let coordinator = NativeArticleTableView.Coordinator()
        coordinator.snapshots = snapshots

        let measurement = measureMilliseconds("native_table_view_layout_1000_rows") {
            let tableView = NSTableView()
            tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
            tableView.headerView = nil
            tableView.rowHeight = ArticleRowHeightMetrics.height(
                interfaceTextSize: .standard,
                imagePosition: .left,
                summaryLineCount: ArticleListSummaryLineCount.defaultValue
            )
            tableView.dataSource = coordinator
            tableView.delegate = coordinator

            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 800))
            scrollView.documentView = tableView

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 800),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = scrollView
            tableView.reloadData()
            window.contentView?.layoutSubtreeIfNeeded()
        }

        #expect(measurement.milliseconds < 2_000)
    }
}
```

- [ ] **Step 2: Test ausführen, Erfolg verifizieren**

Run: `xcodebuild test -scheme Feedivo -configuration Debug -destination 'platform=macOS' -only-testing:FeedivoTests/ArticleListRenderBenchmarkTests`
Expected: PASS. Notiere den ausgegebenen `PERF_METRIC`-Wert für die Doku in Step 5.

- [ ] **Step 3: Vollen Debug-Build + alle neuen Testsuiten gebündelt ausführen**

Run:
```bash
xcodebuild test -scheme Feedivo -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:FeedivoTests/ArticleListRenderBenchmarkFixtureTests \
  -only-testing:FeedivoTests/NativeArticleImageLoadGuardTests \
  -only-testing:FeedivoTests/NativeArticleTableViewCoordinatorTests \
  -only-testing:FeedivoTests/ArticleListRenderBenchmarkTests \
  -parallel-testing-enabled NO
```
Expected: alle Tests grün (14/14 über die vier neuen Suiten).

- [ ] **Step 4: Vollen Debug- und Release-Build ausführen**

Run: `xcodebuild build -scheme Feedivo -configuration Debug`
Run: `xcodebuild build -scheme Feedivo -configuration Release`
Expected: beide `BUILD SUCCEEDED`.

- [ ] **Step 5: CLAUDE.md ergänzen**

Unter "Aktuell in Arbeit" einen neuen Eintrag ergänzen (Datum, Kurzbeschreibung des Spikes, Pfad zu Spec/Plan, Hinweis dass die manuelle Instruments-Live-Verifikation durch den Nutzer noch aussteht, gemessener `PERF_METRIC`-Wert aus Step 2 als Referenz). Kein Code-Snippet nötig — reiner Dokumentationstext nach dem etablierten Muster der anderen Einträge in diesem Abschnitt.

- [ ] **Step 6: Commit**

```bash
git add FeedivoTests/ArticleListRenderBenchmarkTests.swift CLAUDE.md
git commit -m "test: Proxy-Metrik für nativen Artikel-Render-Benchmark + Doku-Nachtrag"
```
