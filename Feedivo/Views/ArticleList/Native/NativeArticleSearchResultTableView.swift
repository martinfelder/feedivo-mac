import AppKit
import SwiftUI

/// `NSTableView`-Subklasse nur für die Return-Taste — löst denselben
/// Öffnen-Callback wie ein Doppelklick aus (`doubleAction`), reicht alle
/// anderen Tasten unverändert an `super.keyDown` weiter (u. a. die
/// Pfeiltasten, die `NSTableView` bereits nativ für die Zeilennavigation
/// nutzt).
private final class ReturnKeyOpensTableView: NSTableView {
    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 36 /* Return */ else {
            super.keyDown(with: event)
            return
        }
        guard let action = doubleAction, let target else {
            super.keyDown(with: event)
            return
        }
        _ = target.perform(action, with: self)
    }
}

/// `NSViewRepresentable`-Wrapper für die native Suchfenster-Ergebnisliste —
/// ersetzt `ArticleSearchWindowView.resultList` bei aktiviertem
/// `NativeArticleListSettings.isEnabledKey`-Schalter. Kein Kontextmenü, keine
/// Pagination (Suchergebnisse werden komplett auf einmal geladen).
struct NativeArticleSearchResultTableView: NSViewRepresentable {
    let snapshots: [ArticleListSnapshot]
    @Binding var selectedID: String?
    let onOpenOriginal: (ArticleListSnapshot) -> Void
    let onOpenInReader: (ArticleListSnapshot) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = ReturnKeyOpensTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
        tableView.headerView = nil
        tableView.usesAutomaticRowHeights = true
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = false
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelectionChanged = { selectedID = $0 }
        coordinator.onOpenOriginal = onOpenOriginal
        coordinator.onOpenInReader = onOpenInReader

        guard let tableView = nsView.documentView as? NSTableView else { return }

        if coordinator.snapshots.map(\.id) != snapshots.map(\.id) {
            coordinator.snapshots = snapshots
            tableView.reloadData()
        } else {
            coordinator.snapshots = snapshots
        }

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
        private static let identifier = NSUserInterfaceItemIdentifier("NativeArticleSearchResultCellView")

        var snapshots: [ArticleListSnapshot] = []
        var onSelectionChanged: ((String?) -> Void)?
        var onOpenOriginal: ((ArticleListSnapshot) -> Void)?
        var onOpenInReader: ((ArticleListSnapshot) -> Void)?

        func snapshot(atRow row: Int) -> ArticleListSnapshot? {
            guard row >= 0, row < snapshots.count else { return nil }
            return snapshots[row]
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            snapshots.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let snapshot = snapshot(atRow: row) else { return nil }
            let cell = (tableView.makeView(withIdentifier: Self.identifier, owner: self) as? NativeArticleSearchResultCellView)
                ?? NativeArticleSearchResultCellView(frame: .zero)
            cell.identifier = Self.identifier
            cell.configure(with: snapshot) { [weak self] in
                self?.onOpenOriginal?(snapshot)
            }
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            onSelectionChanged?(snapshot(atRow: tableView.selectedRow)?.id)
        }

        @objc func handleDoubleClick(_ sender: NSTableView) {
            guard let snapshot = snapshot(atRow: sender.clickedRow >= 0 ? sender.clickedRow : sender.selectedRow) else {
                return
            }
            onOpenInReader?(snapshot)
        }
    }
}
