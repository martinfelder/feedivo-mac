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
