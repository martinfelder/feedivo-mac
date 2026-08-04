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
