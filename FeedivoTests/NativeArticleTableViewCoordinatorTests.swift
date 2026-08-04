import AppKit
import Testing
@testable import Feedivo

// @MainActor ist hier zwingend nötig, nicht nur Stil: Swift Testing führt
// @Test-Funktionen standardmäßig auf einem Hintergrund-Thread des
// kooperativen Executors aus (anders als das alte XCTest, das immer auf dem
// Main Thread lief) — das App-Target setzt zwar projektweit
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor (siehe CLAUDE.md-Gotcha), aber
// NICHT das FeedivoTests-Target selbst. Diese Suite konstruiert echte
// `NSTableView`-Instanzen und ruft `reloadData()`/`selectRowIndexes`/
// `deselectAll` auf — ohne diese Annotation stirbt das reproduzierbar mit
// einem vom Main Thread Checker erzwungenen SIGABRT ("UI API called on a
// background thread"), exakt wie bei `ArticleListRenderBenchmarkTests`
// (siehe dortiger, identischer Kommentar).
@Suite("NativeArticleTableViewCoordinator")
@MainActor
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
