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
}
