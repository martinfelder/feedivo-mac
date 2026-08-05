import AppKit
import SwiftUI

/// `NSViewRepresentable`-Wrapper für die native Hauptartikelliste — ersetzt
/// `SQLiteFeedArticleListView.articleList` bei aktiviertem
/// `NativeArticleListSettings.isEnabledKey`-Schalter. Die komplette
/// State-/Sticky-Row-/Filter-/Sortier-Logik bleibt unverändert in
/// `SQLiteFeedArticleListView`/`SQLiteArticleListDisplayState` — dieser
/// Wrapper bekommt nur das bereits fertig aufbereitete `rows`-Array.
struct NativeArticleListTableView: NSViewRepresentable {
    let rows: [ArticleListSnapshot]
    let hasMore: Bool
    let hiddenReadRowCount: Int
    let showsReadArticles: Bool
    @Binding var selectedArticleID: String?
    let hasAvailableTags: Bool
    let onToggleRead: (String) -> Void
    let onToggleStarred: (String) -> Void
    let onToggleArchived: (String) -> Void
    let onRequestAssignTag: (String) -> Void
    let onCreateRule: (ArticleListSnapshot) -> Void
    let onCopyLink: (ArticleListSnapshot) -> Void
    let onOpenOriginal: (ArticleListSnapshot) -> Void
    let onShareOriginal: (ArticleListSnapshot) -> Void
    let onOpenInNewTab: (String) -> Void
    let onOpenInWindow: (String) -> Void
    let onExport: (String) -> Void
    let onDelete: (ArticleListSnapshot) -> Void
    let onMarkAllRead: () -> Void
    let onLoadMore: () -> Void
    let onShowReadArticles: () -> Void

    @Environment(\.interfaceTextSize) private var interfaceTextSize

    @AppStorage(ArticleListImagePosition.storageKey)
    private var imagePositionRawValue = ArticleListImagePosition.defaultPosition.rawValue

    @AppStorage(ArticleListFeedNameVisibilitySettings.showsFeedNameKey)
    private var showsFeedName = ArticleListFeedNameVisibilitySettings.defaultShowsFeedName

    @AppStorage(ArticleListFeedNamePosition.storageKey)
    private var feedNamePositionRawValue = ArticleListFeedNamePosition.defaultPosition.rawValue

    @AppStorage(ArticleListSummaryLineCount.storageKey)
    private var summaryLineCountRawValue = ArticleListSummaryLineCount.defaultValue

    @AppStorage(ArticleDateDisplayMode.storageKey)
    private var dateDisplayModeRawValue = ArticleDateDisplayMode.defaultMode.rawValue

    /// Reine Vergleichsfunktion: entscheidet, ob `reloadData()` nötig ist.
    /// `ArticleListSnapshot` ist `Equatable` — ein Array-Vergleich reicht,
    /// identisch zum bereits reviewten Spike-Muster in
    /// `NativeArticleTableView.updateNSView`.
    static func needsReload(current: [ArticleListSnapshot], previous: [ArticleListSnapshot]) -> Bool {
        current != previous
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
        tableView.headerView = nil
        tableView.usesAutomaticRowHeights = false
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = false
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.menu = NSMenu()
        tableView.menu?.delegate = context.coordinator
        context.coordinator.weakTableView = tableView

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelectionChanged = { selectedArticleID = $0 }
        coordinator.onToggleRead = onToggleRead
        coordinator.onToggleStarred = onToggleStarred
        coordinator.onToggleArchived = onToggleArchived
        coordinator.onRequestAssignTag = onRequestAssignTag
        coordinator.onCreateRule = onCreateRule
        coordinator.onCopyLink = onCopyLink
        coordinator.onOpenOriginal = onOpenOriginal
        coordinator.onShareOriginal = onShareOriginal
        coordinator.onOpenInNewTab = onOpenInNewTab
        coordinator.onOpenInWindow = onOpenInWindow
        coordinator.onExport = onExport
        coordinator.onDelete = onDelete
        coordinator.onMarkAllRead = onMarkAllRead
        coordinator.onLoadMore = onLoadMore
        coordinator.onShowReadArticles = onShowReadArticles

        coordinator.hasAvailableTags = hasAvailableTags
        coordinator.interfaceTextSize = interfaceTextSize
        coordinator.imagePosition = ArticleListImagePosition.resolved(from: imagePositionRawValue)
        coordinator.feedNamePosition = ArticleListFeedNamePosition.resolved(from: feedNamePositionRawValue)
        coordinator.showsFeedName = showsFeedName
        coordinator.summaryLineCount = ArticleListSummaryLineCount.resolved(from: summaryLineCountRawValue)
        coordinator.dateDisplayMode = ArticleDateDisplayMode.resolved(from: dateDisplayModeRawValue)
        coordinator.hasMoreIndicatorVisible = hasMore
        coordinator.showReadArticlesButtonCount = (!showsReadArticles && hiddenReadRowCount > 0) ? hiddenReadRowCount : nil

        guard let tableView = nsView.documentView as? NSTableView else { return }

        tableView.rowHeight = ArticleRowHeightMetrics.height(
            interfaceTextSize: interfaceTextSize,
            imagePosition: coordinator.imagePosition,
            summaryLineCount: coordinator.summaryLineCount
        )

        if Self.needsReload(current: rows, previous: coordinator.rows) {
            coordinator.rows = rows
            tableView.reloadData()
        } else {
            coordinator.rows = rows
        }

        if let selectedArticleID, let index = rows.firstIndex(where: { $0.id == selectedArticleID }) {
            if tableView.selectedRow != index {
                tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            }
        } else if tableView.selectedRow != -1 {
            tableView.deselectAll(nil)
        }
    }

    func makeCoordinator() -> NativeArticleListCoordinator {
        NativeArticleListCoordinator()
    }
}
