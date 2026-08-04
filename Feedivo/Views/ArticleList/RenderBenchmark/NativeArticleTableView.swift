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

    // Whole-Branch-Review-Fund: diese View liest jetzt dieselben echten
    // Anzeige-Einstellungen wie die SwiftUI-Baseline (`ArticleRowView`),
    // statt Textgröße/Bildposition/Zusammenfassungszeilen hartzukodieren —
    // sonst rendern beide Benchmark-Varianten unterschiedlich, sobald die
    // Einstellungen nicht auf den Standardwerten stehen. `interfaceTextSize`
    // kommt aus der SwiftUI-Umgebung, die Task 6 bereits auf das
    // Render-Benchmark-Fenster injiziert.
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    @AppStorage(ArticleListImagePosition.storageKey)
    private var imagePositionRawValue = ArticleListImagePosition.defaultPosition.rawValue

    @AppStorage(ArticleListSummaryLineCount.storageKey)
    private var summaryLineCountRawValue = ArticleListSummaryLineCount.defaultValue

    private var imagePosition: ArticleListImagePosition {
        ArticleListImagePosition.resolved(from: imagePositionRawValue)
    }

    private var resolvedSummaryLineCount: Int {
        ArticleListSummaryLineCount.resolved(from: summaryLineCountRawValue)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
        tableView.headerView = nil
        tableView.usesAutomaticRowHeights = false
        tableView.rowHeight = ArticleRowHeightMetrics.height(
            interfaceTextSize: interfaceTextSize,
            imagePosition: imagePosition,
            summaryLineCount: resolvedSummaryLineCount
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
        context.coordinator.onSelectionChanged = { selectedID = $0 }
        context.coordinator.onToggleStarred = onToggleStarred
        context.coordinator.interfaceTextSize = interfaceTextSize

        guard let tableView = nsView.documentView as? NSTableView else { return }

        // Muss bei JEDEM Aufruf neu gesetzt werden, nicht nur in
        // `makeNSView` — sonst reagiert eine Live-Änderung der
        // Anzeige-Einstellungen (Textgröße/Bildposition/Zusammenfassungs-
        // zeilen) bei offenem Benchmark-Fenster nicht, obwohl `ArticleRowView`
        // auf der Baseline-Seite sofort reagieren würde.
        tableView.rowHeight = ArticleRowHeightMetrics.height(
            interfaceTextSize: interfaceTextSize,
            imagePosition: imagePosition,
            summaryLineCount: resolvedSummaryLineCount
        )

        // Whole-Branch-Review-Fund: `reloadData()` unconditional bei jedem
        // Aufruf (auch bei einer reinen Selektionsänderung) hätte für jede
        // sichtbare Zelle frische Bild-Ladevorgänge ausgelöst — bei jedem
        // Klick auf einen anderen Artikel, unabhängig davon, ob sich die
        // Daten selbst geändert haben. Nur bei tatsächlich geänderten
        // Snapshots neu laden.
        if context.coordinator.snapshots != snapshots {
            context.coordinator.snapshots = snapshots
            tableView.reloadData()
        } else {
            context.coordinator.snapshots = snapshots
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
        var snapshots: [ArticleListSnapshot] = []
        var onSelectionChanged: ((String?) -> Void)?
        var onToggleStarred: ((String) -> Void)?
        var interfaceTextSize: InterfaceTextSize = .standard

        func numberOfRows(in tableView: NSTableView) -> Int {
            snapshots.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("NativeArticleRowCellView")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NativeArticleRowCellView)
                ?? NativeArticleRowCellView(frame: .zero)
            cell.identifier = identifier

            let snapshot = snapshots[row]
            cell.configure(with: snapshot, interfaceTextSize: interfaceTextSize) { [weak self] in
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
