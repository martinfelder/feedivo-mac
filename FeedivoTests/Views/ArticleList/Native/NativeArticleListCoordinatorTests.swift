import AppKit
import Testing
@testable import Feedivo

// @MainActor zwingend nötig — echte NSTableView-Instanzen, siehe Global Constraints.
@Suite("NativeArticleListCoordinator")
@MainActor
struct NativeArticleListCoordinatorTests {
    private func makeSnapshot(id: String = "a1", link: String? = "https://example.com", isRead: Bool = false, isStarred: Bool = false, isArchived: Bool = false) -> ArticleListSnapshot {
        ArticleListSnapshot(
            id: id, feedID: "f1", feedTitle: "Feed", title: "Titel \(id)",
            summary: nil, link: link, imageURL: nil, publishedAt: nil,
            arrivedAt: Date(), estimatedReadingMinutes: nil,
            isRead: isRead, isStarred: isStarred, isArchived: isArchived,
            isHidden: false, faviconURL: nil
        )
    }

    @Test func numberOfRowsZaehltInhaltUndTrailingRowsZusammen() {
        let coordinator = NativeArticleListCoordinator()
        coordinator.rows = [makeSnapshot(id: "a1"), makeSnapshot(id: "a2")]
        coordinator.hasMoreIndicatorVisible = true
        coordinator.showReadArticlesButtonCount = 5

        #expect(coordinator.numberOfRows(in: NSTableView()) == 4)
    }

    @Test func rowKindLiefertContentFuerInhaltsZeilen() {
        let coordinator = NativeArticleListCoordinator()
        let snapshot = makeSnapshot(id: "a1")
        coordinator.rows = [snapshot]

        #expect(coordinator.rowKind(atRow: 0) == .content(snapshot))
    }

    @Test func rowKindLiefertLoadMoreVorShowReadButton() {
        let coordinator = NativeArticleListCoordinator()
        coordinator.rows = [makeSnapshot(id: "a1")]
        coordinator.hasMoreIndicatorVisible = true
        coordinator.showReadArticlesButtonCount = 3

        #expect(coordinator.rowKind(atRow: 1) == .trailing(.loadMoreIndicator))
        #expect(coordinator.rowKind(atRow: 2) == .trailing(.showReadArticlesButton(count: 3)))
    }

    @Test func rowKindOhneTrailingRowsIstNilAusserhalbDerRows() {
        let coordinator = NativeArticleListCoordinator()
        coordinator.rows = [makeSnapshot(id: "a1")]

        #expect(coordinator.rowKind(atRow: 1) == nil)
    }

    @Test func tableViewSelectionDidChangeMeldetAusgewaehlteID() {
        let coordinator = NativeArticleListCoordinator()
        let snapshots = [makeSnapshot(id: "a1"), makeSnapshot(id: "a2"), makeSnapshot(id: "a3")]
        coordinator.rows = snapshots
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

    @Test func tableViewSelectionDidChangeIgnoriertAuswahlAufTrailingRow() {
        let coordinator = NativeArticleListCoordinator()
        coordinator.rows = [makeSnapshot(id: "a1")]
        coordinator.hasMoreIndicatorVisible = true
        var reportedID: String? = "vorher-gesetzt"
        coordinator.onSelectionChanged = { reportedID = $0 }

        let tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
        tableView.dataSource = coordinator
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)

        coordinator.tableViewSelectionDidChange(
            Notification(name: NSTableView.selectionDidChangeNotification, object: tableView)
        )

        #expect(reportedID == nil)
    }

    @Test func buildContextMenuHatZwoelfEintraegePlusDreiTrenner() {
        let coordinator = NativeArticleListCoordinator()
        coordinator.hasAvailableTags = true
        let menu = coordinator.buildContextMenu(for: makeSnapshot())

        #expect(menu.items.count == 16)
        #expect(menu.items.filter(\.isSeparatorItem).count == 3)
    }

    @Test func buildContextMenuZeigtGelesenMarkierenBeiUngelesenemArtikel() {
        let coordinator = NativeArticleListCoordinator()
        let menu = coordinator.buildContextMenu(for: makeSnapshot(isRead: false))

        #expect(menu.items[0].title == L10n.articleRowMarkRead)
    }

    @Test func buildContextMenuZeigtUngelesenMarkierenBeiGelesenemArtikel() {
        let coordinator = NativeArticleListCoordinator()
        let menu = coordinator.buildContextMenu(for: makeSnapshot(isRead: true))

        #expect(menu.items[0].title == L10n.articleRowMarkUnread)
    }

    @Test func buildContextMenuDeaktiviertTagZuweisenOhneVerfuegbareTags() {
        let coordinator = NativeArticleListCoordinator()
        coordinator.hasAvailableTags = false
        let menu = coordinator.buildContextMenu(for: makeSnapshot())

        let tagItem = menu.items.first { $0.title == L10n.articleAssignTagCommand }
        #expect(tagItem?.isEnabled == false)
    }

    @Test func buildContextMenuDeaktiviertLinkAktionenOhneOriginalURL() {
        let coordinator = NativeArticleListCoordinator()
        let menu = coordinator.buildContextMenu(for: makeSnapshot(link: nil))

        let copyLinkItem = menu.items.first { $0.title == L10n.articleCopyLinkCommand }
        let openOriginalItem = menu.items.first { $0.title == L10n.articleOpenOriginalCommand }
        let shareItem = menu.items.first { $0.title == L10n.articleShareCommand }
        #expect(copyLinkItem?.isEnabled == false)
        #expect(openOriginalItem?.isEnabled == false)
        #expect(shareItem?.isEnabled == false)
    }

    @Test func buildContextMenuAktionenRufenDieRichtigenClosuresAuf() {
        let coordinator = NativeArticleListCoordinator()
        let snapshot = makeSnapshot(id: "a1")
        var toggledReadID: String?
        coordinator.onToggleRead = { toggledReadID = $0 }
        let menu = coordinator.buildContextMenu(for: snapshot)

        let readItem = menu.items[0]
        _ = readItem.target?.perform(readItem.action, with: readItem)

        #expect(toggledReadID == "a1")
    }
}
