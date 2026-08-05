import AppKit
import Testing
@testable import Feedivo

// @MainActor zwingend nötig — echte NSTableView-Instanzen, siehe Global Constraints.
@Suite("NativeArticleSearchResultTableView")
@MainActor
struct NativeArticleSearchResultTableViewTests {
    private func makeSnapshot(id: String) -> ArticleListSnapshot {
        ArticleListSnapshot(
            id: id, feedID: "f1", feedTitle: "Feed", title: "Titel \(id)",
            summary: nil, link: nil, imageURL: nil, publishedAt: nil,
            arrivedAt: Date(), estimatedReadingMinutes: nil,
            isRead: false, isStarred: false, isArchived: false,
            isHidden: false, faviconURL: nil
        )
    }

    @Test func numberOfRowsEntsprichtAnzahlSnapshots() {
        let coordinator = NativeArticleSearchResultTableView.Coordinator()
        coordinator.snapshots = [makeSnapshot(id: "a1"), makeSnapshot(id: "a2")]

        #expect(coordinator.numberOfRows(in: NSTableView()) == 2)
    }

    @Test func snapshotAtRowLiefertNilAusserhalbDesBereichs() {
        let coordinator = NativeArticleSearchResultTableView.Coordinator()
        coordinator.snapshots = [makeSnapshot(id: "a1")]

        #expect(coordinator.snapshot(atRow: 1) == nil)
        #expect(coordinator.snapshot(atRow: 0) == coordinator.snapshots[0])
    }

    @Test func tableViewSelectionDidChangeMeldetAusgewaehlteID() {
        let coordinator = NativeArticleSearchResultTableView.Coordinator()
        coordinator.snapshots = [makeSnapshot(id: "a1"), makeSnapshot(id: "a2")]
        var reportedID: String?
        coordinator.onSelectionChanged = { reportedID = $0 }

        let tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
        tableView.dataSource = coordinator
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)

        coordinator.tableViewSelectionDidChange(
            Notification(name: NSTableView.selectionDidChangeNotification, object: tableView)
        )

        #expect(reportedID == "a2")
    }

    @Test func doubleActionRuftOnOpenInReaderMitAngeklickterZeileAuf() {
        let coordinator = NativeArticleSearchResultTableView.Coordinator()
        let snapshot = makeSnapshot(id: "a1")
        coordinator.snapshots = [snapshot]
        var openedSnapshot: ArticleListSnapshot?
        coordinator.onOpenInReader = { openedSnapshot = $0 }

        let tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
        tableView.dataSource = coordinator
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        coordinator.handleDoubleClick(tableView)

        #expect(openedSnapshot == snapshot)
    }

    // Regressionstest für den IMPORTANT-Fund des finalen Whole-Branch-Reviews:
    // `NSTableView.clickedRow` bleibt nach einem Klick auf ihrem Wert stehen,
    // auch wenn die Auswahl danach per Pfeiltaste weiterbewegt wird (nur
    // `selectedRow` ändert sich). Der Return-Tasten-Pfad rief früher denselben
    // `handleDoubleClick` auf, der `clickedRow` bevorzugt — nach Klick auf
    // Zeile 0 (setzt clickedRow=0) und Pfeiltasten-Navigation zu Zeile 1
    // (ändert nur selectedRow) hätte Return fälschlich Zeile 0 statt der
    // aktuell ausgewählten Zeile 1 geöffnet. `handleReturnKey` muss
    // AUSSCHLIESSLICH `selectedRow` lesen — dieser Test setzt `clickedRow`
    // bewusst auf eine ANDERE Zeile als `selectedRow`, um zu beweisen, dass
    // das Ergebnis nicht von `clickedRow` abhängt.
    @Test func handleReturnKeyNutztImmerSelectedRowNichtClickedRow() {
        let coordinator = NativeArticleSearchResultTableView.Coordinator()
        let snapshotA = makeSnapshot(id: "a1")
        let snapshotB = makeSnapshot(id: "a2")
        coordinator.snapshots = [snapshotA, snapshotB]
        var openedSnapshot: ArticleListSnapshot?
        coordinator.onOpenInReader = { openedSnapshot = $0 }

        let tableView = FakeClickedRowTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
        tableView.dataSource = coordinator
        tableView.reloadData()
        tableView.fakeClickedRow = 0
        tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)

        coordinator.handleReturnKey(tableView)

        #expect(openedSnapshot == snapshotB)
    }
}

/// Test-Double für `NSTableView.clickedRow` — siehe ausführliche Begründung an
/// der gleichnamigen Klasse in `NativeArticleListCoordinatorTests.swift`.
private final class FakeClickedRowTableView: NSTableView {
    var fakeClickedRow: Int = -1
    override var clickedRow: Int { fakeClickedRow }
}
