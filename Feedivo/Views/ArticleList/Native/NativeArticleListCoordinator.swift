import AppKit

/// `NSTableViewDataSource`/`NSTableViewDelegate`/`NSMenuDelegate` für die
/// native Hauptartikelliste — treibt sowohl Inhalts-Zeilen
/// (`NativeArticleListRowCellView`) als auch die beiden Trailing-Row-Typen
/// (Pagination-Indikator, "N gelesene Artikel anzeigen"-Button). Task 4
/// (`NativeArticleListTableView`) setzt nur die öffentlichen Properties und
/// liest `numberOfRows(in:)`/`tableView(_:viewFor:row:)` über die
/// Standard-Delegate-Protokolle — kein direkter Zugriff auf `rowKind`/
/// `buildContextMenu` von dort nötig.
final class NativeArticleListCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    enum TrailingRowKind: Equatable {
        case loadMoreIndicator
        case showReadArticlesButton(count: Int)
    }

    enum RowKind: Equatable {
        case content(ArticleListSnapshot)
        case trailing(TrailingRowKind)
    }

    private static let contentIdentifier = NSUserInterfaceItemIdentifier("NativeArticleListRowCellView")
    private static let loadMoreIdentifier = NSUserInterfaceItemIdentifier("NativeArticleListLoadMoreCellView")
    private static let showReadButtonIdentifier = NSUserInterfaceItemIdentifier("NativeArticleListShowReadButtonCellView")

    var rows: [ArticleListSnapshot] = []
    var hasMoreIndicatorVisible = false
    var showReadArticlesButtonCount: Int?
    var hasAvailableTags = false
    var interfaceTextSize: InterfaceTextSize = .standard
    var imagePosition: ArticleListImagePosition = .left
    var feedNamePosition: ArticleListFeedNamePosition = .afterTitle
    var showsFeedName = true
    var summaryLineCount = ArticleListSummaryLineCount.defaultValue
    var dateDisplayMode: ArticleDateDisplayMode = .relative

    var onSelectionChanged: ((String?) -> Void)?
    var onToggleRead: ((String) -> Void)?
    var onToggleStarred: ((String) -> Void)?
    var onToggleArchived: ((String) -> Void)?
    var onRequestAssignTag: ((String) -> Void)?
    var onCreateRule: ((ArticleListSnapshot) -> Void)?
    var onCopyLink: ((ArticleListSnapshot) -> Void)?
    var onOpenOriginal: ((ArticleListSnapshot) -> Void)?
    var onShareOriginal: ((ArticleListSnapshot) -> Void)?
    var onOpenInNewTab: ((String) -> Void)?
    var onOpenInWindow: ((String) -> Void)?
    var onExport: ((String) -> Void)?
    var onDelete: ((ArticleListSnapshot) -> Void)?
    var onMarkAllRead: (() -> Void)?
    var onLoadMore: (() -> Void)?
    var onShowReadArticles: (() -> Void)?

    private var trailingRowKinds: [TrailingRowKind] {
        var kinds: [TrailingRowKind] = []
        if hasMoreIndicatorVisible {
            kinds.append(.loadMoreIndicator)
        }
        if let count = showReadArticlesButtonCount {
            kinds.append(.showReadArticlesButton(count: count))
        }
        return kinds
    }

    func rowKind(atRow row: Int) -> RowKind? {
        if row < rows.count {
            return .content(rows[row])
        }
        let trailingIndex = row - rows.count
        let kinds = trailingRowKinds
        guard trailingIndex >= 0, trailingIndex < kinds.count else {
            return nil
        }
        return .trailing(kinds[trailingIndex])
    }

    // MARK: NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count + trailingRowKinds.count
    }

    // MARK: NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rowKind(atRow: row) {
        case let .content(snapshot):
            let cell = (tableView.makeView(withIdentifier: Self.contentIdentifier, owner: self) as? NativeArticleListRowCellView)
                ?? NativeArticleListRowCellView(frame: .zero)
            cell.identifier = Self.contentIdentifier
            cell.configure(
                with: snapshot,
                interfaceTextSize: interfaceTextSize,
                imagePosition: imagePosition,
                feedNamePosition: feedNamePosition,
                showsFeedName: showsFeedName,
                summaryLineCount: summaryLineCount,
                dateDisplayMode: dateDisplayMode
            ) { [weak self] in
                self?.onToggleStarred?(snapshot.id)
            }
            return cell

        case .trailing(.loadMoreIndicator):
            // Diese Zeile wird nur angefragt, wenn sie tatsächlich sichtbar wird
            // (NSTableView ruft `viewFor` ausschließlich für sichtbare/bald
            // sichtbare Zeilen auf) — genau das ersetzt SwiftUIs
            // `.onAppear`-Trigger für `state.loadMore()`.
            onLoadMore?()
            let cell = (tableView.makeView(withIdentifier: Self.loadMoreIdentifier, owner: self) as? NativeArticleListLoadMoreCellView)
                ?? NativeArticleListLoadMoreCellView(frame: .zero)
            cell.identifier = Self.loadMoreIdentifier
            return cell

        case let .trailing(.showReadArticlesButton(count)):
            let cell = (tableView.makeView(withIdentifier: Self.showReadButtonIdentifier, owner: self) as? NativeArticleListShowReadButtonCellView)
                ?? NativeArticleListShowReadButtonCellView(frame: .zero)
            cell.identifier = Self.showReadButtonIdentifier
            cell.configure(count: count) { [weak self] in
                self?.onShowReadArticles?()
            }
            return cell

        case nil:
            return nil
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rowKind(atRow: row) {
        case .content:
            ArticleRowHeightMetrics.height(
                interfaceTextSize: interfaceTextSize,
                imagePosition: imagePosition,
                summaryLineCount: summaryLineCount
            )
        case .trailing, nil:
            NativeArticleListTrailingRowMetrics.height
        }
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        // Trailing-Rows sind nicht selektierbar — kein Artikel dahinter.
        if case .content = rowKind(atRow: row) {
            return true
        }
        return false
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, case let .content(snapshot) = rowKind(atRow: selectedRow) else {
            onSelectionChanged?(nil)
            return
        }
        onSelectionChanged?(snapshot.id)
    }

    // MARK: NSMenuDelegate

    /// Vom `NSViewRepresentable`-Wrapper (Task 4) gesetzt — `NSMenuDelegate`
    /// selbst hat keinen direkten Zugriff auf die zugehörige `NSTableView`.
    weak var weakTableView: NSTableView?

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let tableView = weakTableView,
              case let .content(snapshot) = rowKind(atRow: tableView.clickedRow)
        else {
            return
        }
        for item in buildContextMenu(for: snapshot).items {
            menu.addItem(item)
        }
    }

    // MARK: Kontextmenü (pure, direkt testbar)

    func buildContextMenu(for snapshot: ArticleListSnapshot) -> NSMenu {
        let menu = NSMenu()
        let hasOriginalURL = ArticleOriginalURLResolver.hasUsableWebLink(snapshot.link)

        menu.addItem(makeItem(
            title: snapshot.isRead ? L10n.articleRowMarkUnread : L10n.articleRowMarkRead
        ) { [weak self] in self?.onToggleRead?(snapshot.id) })

        menu.addItem(makeItem(
            title: snapshot.isStarred ? L10n.articleRowStarRemove : L10n.articleRowStarAdd
        ) { [weak self] in self?.onToggleStarred?(snapshot.id) })

        menu.addItem(.separator())

        menu.addItem(makeItem(
            title: snapshot.isArchived ? L10n.articleUnarchiveCommand : L10n.articleArchiveCommand
        ) { [weak self] in self?.onToggleArchived?(snapshot.id) })

        menu.addItem(makeItem(
            title: L10n.articleAssignTagCommand,
            isEnabled: hasAvailableTags
        ) { [weak self] in self?.onRequestAssignTag?(snapshot.id) })

        menu.addItem(makeItem(title: L10n.articleCreateRuleCommand) { [weak self] in
            self?.onCreateRule?(snapshot)
        })

        menu.addItem(.separator())

        menu.addItem(makeItem(title: L10n.articleOpenInNewTabCommand) { [weak self] in
            self?.onOpenInNewTab?(snapshot.id)
        })

        menu.addItem(makeItem(title: L10n.articleOpenInWindowCommand) { [weak self] in
            self?.onOpenInWindow?(snapshot.id)
        })

        menu.addItem(makeItem(
            title: L10n.articleCopyLinkCommand,
            isEnabled: hasOriginalURL
        ) { [weak self] in self?.onCopyLink?(snapshot) })

        menu.addItem(makeItem(
            title: L10n.articleOpenOriginalCommand,
            isEnabled: hasOriginalURL
        ) { [weak self] in self?.onOpenOriginal?(snapshot) })

        menu.addItem(makeItem(
            title: L10n.articleShareCommand,
            isEnabled: hasOriginalURL
        ) { [weak self] in self?.onShareOriginal?(snapshot) })

        menu.addItem(makeItem(title: L10n.articleExportCommand) { [weak self] in
            self?.onExport?(snapshot.id)
        })

        menu.addItem(makeItem(title: L10n.articleDeleteCommand) { [weak self] in
            self?.onDelete?(snapshot)
        })

        menu.addItem(.separator())

        menu.addItem(makeItem(title: L10n.articleMarkAllReadCommand) { [weak self] in
            self?.onMarkAllRead?()
        })

        return menu
    }

    private func makeItem(title: String, isEnabled: Bool = true, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, action: action)
        item.isEnabled = isEnabled
        return item
    }
}

/// `NSMenuItem`-Subklasse, die ihre Aktion als Closure statt als
/// Target/Selector-Paar trägt — vermeidet einen separaten `@objc`-Handler
/// pro Menüeintrag (13 Aktions-Einträge).
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        self.target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) wird nicht unterstützt")
    }

    @objc private func invoke() {
        handler()
    }
}
