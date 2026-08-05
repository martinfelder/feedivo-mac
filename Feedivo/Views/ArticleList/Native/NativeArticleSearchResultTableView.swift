import AppKit
import SwiftUI

/// `NSTableView`-Subklasse nur für die Return-Taste — löst einen EIGENEN,
/// von `doubleAction` unabhängigen Callback aus, reicht alle anderen Tasten
/// unverändert an `super.keyDown` weiter (u. a. die Pfeiltasten, die
/// `NSTableView` bereits nativ für die Zeilennavigation nutzt).
///
/// Bewusst NICHT `doubleAction`/`target.perform(doubleAction:)` wiederverwendet:
/// `NSTableView.clickedRow` ist "die Zeile unter der Maus beim letzten Klick"
/// und wird NICHT auf -1 zurückgesetzt, nachdem dieser Klick vorbei ist — nach
/// Klick auf Zeile 2 (clickedRow=2) und anschließender Pfeiltasten-Navigation
/// zu Zeile 4 (ändert nur selectedRow, NICHT clickedRow) hätte Return über
/// `handleDoubleClick` fälschlich Zeile 2 statt der aktuell ausgewählten
/// Zeile 4 geöffnet. `returnAction` zeigt stattdessen auf
/// `Coordinator.handleReturnKey(_:)`, das ausschließlich `selectedRow` liest.
private final class ReturnKeyOpensTableView: NSTableView {
    var returnAction: Selector?

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 36 /* Return */ else {
            super.keyDown(with: event)
            return
        }
        guard let action = returnAction, let target else {
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
        tableView.returnAction = #selector(Coordinator.handleReturnKey(_:))

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

        // Siehe ausführlicher Kommentar zu `isApplyingProgrammaticSelection` in
        // `NativeArticleListCoordinator.swift`/`NativeArticleListTableView.swift`
        // — identisches Muster: verhindert, dass diese rein synchronisierenden
        // Aufrufe über `tableViewSelectionDidChange` den SwiftUI-Zustand
        // `selectedID` mit `nil` überschreiben.
        if let selectedID, let index = snapshots.firstIndex(where: { $0.id == selectedID }) {
            if tableView.selectedRow != index {
                coordinator.isApplyingProgrammaticSelection = true
                tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                coordinator.isApplyingProgrammaticSelection = false
            }
        } else if tableView.selectedRow != -1 {
            coordinator.isApplyingProgrammaticSelection = true
            tableView.deselectAll(nil)
            coordinator.isApplyingProgrammaticSelection = false
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

        /// Siehe `NativeArticleListCoordinator.isApplyingProgrammaticSelection`
        /// für die volle Begründung — identisches Muster hier für die
        /// Suchergebnisliste.
        var isApplyingProgrammaticSelection = false

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
            guard !isApplyingProgrammaticSelection else { return }
            guard let tableView = notification.object as? NSTableView else { return }
            onSelectionChanged?(snapshot(atRow: tableView.selectedRow)?.id)
        }

        /// Echter Doppelklick — `clickedRow` ist hier korrekt, da AppKit es
        /// exakt für den auslösenden Klick setzt.
        @objc func handleDoubleClick(_ sender: NSTableView) {
            guard let snapshot = snapshot(atRow: sender.clickedRow >= 0 ? sender.clickedRow : sender.selectedRow) else {
                return
            }
            onOpenInReader?(snapshot)
        }

        /// Return-Taste — nutzt bewusst NUR `selectedRow`, nie `clickedRow`
        /// (siehe Kommentar an `ReturnKeyOpensTableView`).
        @objc func handleReturnKey(_ sender: NSTableView) {
            guard let snapshot = snapshot(atRow: sender.selectedRow) else { return }
            onOpenInReader?(snapshot)
        }
    }
}
