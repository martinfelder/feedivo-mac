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
        // `NSTableView.clickedRow` liefert -1, wenn ein Rechtsklick keine
        // Zeile trifft (z. B. leerer Bereich unterhalb der letzten Zeile oder
        // eine komplett leere Liste) — ohne diese Guard würde `row < rows.count`
        // für -1 immer zutreffen und `rows[-1]` abstürzen.
        guard row >= 0 else {
            return nil
        }
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
            // `.onAppear`-Trigger für `state.loadMore()`. Wichtig: `viewFor` läuft
            // während `reloadData()`/Layout, was wiederum innerhalb von SwiftUIs
            // `updateNSView`-Aufruf (also innerhalb von SwiftUIs eigenem
            // View-Update-Durchlauf) passiert — `onLoadMore` mutiert am Ende
            // `@Observable`-Zustand (`state.loadMore()` setzt u. a.
            // `isLoadingMore`), ein synchroner Aufruf hier wäre also "State
            // während eines View-Updates ändern", was SwiftUI explizit als
            // undefiniertes Verhalten dokumentiert. Deshalb um einen
            // Runloop-Durchlauf verzögert auslösen, statt direkt hier.
            Task { @MainActor [weak self] in
                self?.onLoadMore?()
            }
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

    /// Wird von `NativeArticleListTableView.updateNSView` rund um jeden
    /// programmatischen `selectRowIndexes`/`deselectAll`-Aufruf gesetzt (State-
    /// Sync SwiftUI → NSTableView). Verhindert, dass diese rein synchronisierenden
    /// Aufrufe über `tableViewSelectionDidChange` erneut `onSelectionChanged`
    /// feuern und damit den gerade gesetzten SwiftUI-Zustand mit `nil`
    /// überschreiben — betrifft konkret den "zum nächsten Feed mit ungelesenen
    /// Artikeln springen"-Fall: `selectedArticleID` wird dort bewusst VOR dem
    /// Laden der neuen Feed-Zeilen gesetzt, `updateNSView` sieht dann kurzzeitig
    /// noch die alten `rows` und würde ohne diese Sperre `deselectAll` auslösen.
    var isApplyingProgrammaticSelection = false

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingProgrammaticSelection else { return }
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
        for item in contextMenuItems(for: snapshot) {
            menu.addItem(item)
        }
    }

    // MARK: Kontextmenü (pure, direkt testbar)

    /// Baut die rohen Menüeinträge — OHNE sie in ein `NSMenu` zu verpacken.
    /// Wichtig: `NSMenuItem` kann immer nur einem einzigen `NSMenu` gleichzeitig
    /// gehören. `menuNeedsUpdate(_:)` fügt diese Items direkt in das vom System
    /// übergebene `menu` ein — würde stattdessen `buildContextMenu(for:).items`
    /// (Items, die bereits einem frisch gebauten `NSMenu` gehören) erneut in ein
    /// zweites Menü eingefügt, wirft AppKit
    /// `NSInternalInconsistencyException: "Item to be inserted into menu already
    /// is in another menu"` — reproduzierbar bei jedem Rechtsklick.
    func contextMenuItems(for snapshot: ArticleListSnapshot) -> [NSMenuItem] {
        let hasOriginalURL = ArticleOriginalURLResolver.hasUsableWebLink(snapshot.link)

        var items: [NSMenuItem] = []

        items.append(makeItem(
            title: snapshot.isRead ? L10n.articleRowMarkUnread : L10n.articleRowMarkRead
        ) { [weak self] in self?.onToggleRead?(snapshot.id) })

        items.append(makeItem(
            title: snapshot.isStarred ? L10n.articleRowStarRemove : L10n.articleRowStarAdd
        ) { [weak self] in self?.onToggleStarred?(snapshot.id) })

        items.append(.separator())

        items.append(makeItem(
            title: snapshot.isArchived ? L10n.articleUnarchiveCommand : L10n.articleArchiveCommand
        ) { [weak self] in self?.onToggleArchived?(snapshot.id) })

        items.append(makeItem(
            title: L10n.articleAssignTagCommand,
            isEnabled: hasAvailableTags
        ) { [weak self] in self?.onRequestAssignTag?(snapshot.id) })

        items.append(makeItem(title: L10n.articleCreateRuleCommand) { [weak self] in
            self?.onCreateRule?(snapshot)
        })

        items.append(.separator())

        items.append(makeItem(title: L10n.articleOpenInNewTabCommand) { [weak self] in
            self?.onOpenInNewTab?(snapshot.id)
        })

        items.append(makeItem(title: L10n.articleOpenInWindowCommand) { [weak self] in
            self?.onOpenInWindow?(snapshot.id)
        })

        items.append(makeItem(
            title: L10n.articleCopyLinkCommand,
            isEnabled: hasOriginalURL
        ) { [weak self] in self?.onCopyLink?(snapshot) })

        items.append(makeItem(
            title: L10n.articleOpenOriginalCommand,
            isEnabled: hasOriginalURL
        ) { [weak self] in self?.onOpenOriginal?(snapshot) })

        items.append(makeItem(
            title: L10n.articleShareCommand,
            isEnabled: hasOriginalURL
        ) { [weak self] in self?.onShareOriginal?(snapshot) })

        items.append(makeItem(title: L10n.articleExportCommand) { [weak self] in
            self?.onExport?(snapshot.id)
        })

        items.append(makeItem(title: L10n.articleDeleteCommand) { [weak self] in
            self?.onDelete?(snapshot)
        })

        items.append(.separator())

        items.append(makeItem(title: L10n.articleMarkAllReadCommand) { [weak self] in
            self?.onMarkAllRead?()
        })

        return items
    }

    /// Dünner Wrapper um `contextMenuItems(for:)`, der die Items in ein neues
    /// `NSMenu` verpackt — bleibt aus Kompatibilitätsgründen für bestehende
    /// Tests bestehen, die direkt gegen ein `NSMenu` prüfen. Wird von
    /// `menuNeedsUpdate(_:)` selbst NICHT mehr verwendet (siehe Kommentar dort).
    func buildContextMenu(for snapshot: ArticleListSnapshot) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in contextMenuItems(for: snapshot) {
            menu.addItem(item)
        }
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
