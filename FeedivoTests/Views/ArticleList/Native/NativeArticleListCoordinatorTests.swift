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

    // Regressionstest: `NSTableView.clickedRow` liefert -1, wenn ein
    // Rechtsklick keine Zeile trifft (z. B. leerer Bereich unterhalb der
    // letzten Zeile oder eine komplett leere Liste). `rowKind(atRow:)` muss
    // dafür nil liefern statt `rows[-1]` abstürzen zu lassen — sowohl bei
    // einem leeren Coordinator als auch bei einem mit Inhalts-/Trailing-Rows.
    @Test func rowKindLiefertNilBeiNegativemRowIndex() {
        let leererCoordinator = NativeArticleListCoordinator()
        #expect(leererCoordinator.rowKind(atRow: -1) == nil)

        let coordinator = NativeArticleListCoordinator()
        coordinator.rows = [makeSnapshot(id: "a1")]
        coordinator.hasMoreIndicatorVisible = true
        coordinator.showReadArticlesButtonCount = 3
        #expect(coordinator.rowKind(atRow: -1) == nil)
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

    @Test func buildContextMenuHatDreizehnEintraegePlusDreiTrenner() {
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

    // Regressionstest für den CRITICAL-Fund des finalen Whole-Branch-Reviews:
    // `menuNeedsUpdate(_:)` rief früher `buildContextMenu(for:).items` auf und
    // fügte diese — bereits einem ANDEREN, intern von `buildContextMenu`
    // gebauten `NSMenu` gehörenden — Items erneut in das vom System übergebene
    // `menu` ein. `NSMenuItem` kann aber nur einem einzigen `NSMenu`
    // gleichzeitig gehören, AppKit wirft dafür
    // `NSInternalInconsistencyException: "Item to be inserted into menu already
    // is in another menu"` — das feuerte bei JEDEM Rechtsklick auf eine Zeile.
    // Dieser Test konstruiert eine ECHTE `NSTableView` + ein ECHTES `NSMenu`
    // (nicht nur `buildContextMenu(for:)` isoliert) und ruft `menuNeedsUpdate`
    // exakt so auf, wie es AppKit vor dem Öffnen eines Kontextmenüs tut — vor
    // dem Fix hätte bereits der erste Aufruf abgestürzt.
    @Test func menuNeedsUpdateBefuelltEinEchtesMenuOhneAbsturz() {
        let coordinator = NativeArticleListCoordinator()
        coordinator.hasAvailableTags = true
        let snapshot = makeSnapshot(id: "a1", link: nil)
        coordinator.rows = [snapshot]

        let tableView = FakeClickedRowTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
        tableView.dataSource = coordinator
        tableView.reloadData()
        tableView.fakeClickedRow = 0
        coordinator.weakTableView = tableView

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = coordinator

        coordinator.menuNeedsUpdate(menu)

        #expect(menu.items.count == 16)
        #expect(menu.items.filter(\.isSeparatorItem).count == 3)

        // Ein zweiter Aufruf (z. B. zweiter Rechtsklick auf dieselbe oder eine
        // andere Zeile) darf ebenfalls nicht abstürzen — `menuNeedsUpdate` baut
        // die Items bei jedem Aufruf neu aus `contextMenuItems(for:)`.
        coordinator.menuNeedsUpdate(menu)
        #expect(menu.items.count == 16)
    }

    // Regressionstest für den zweiten (IMPORTANT-)Fund: `NSMenu.autoenablesItems`
    // defaultet auf `true` — ohne `autoenablesItems = false` würde AppKit jeden
    // Eintrag mit gültigem Target/Action (jeder `ClosureMenuItem` ist sein
    // eigenes Target) beim `-update`-Durchlauf automatisch wieder aktivieren,
    // unabhängig vom manuell gesetzten `isEnabled` — ein deaktiviertes
    // "Tag zuweisen" ohne Tags wäre dadurch trotzdem klickbar.
    @Test func menuNeedsUpdateBleibtNachMenuUpdateDeaktiviertWennAutoenablesItemsAus() {
        let coordinator = NativeArticleListCoordinator()
        coordinator.hasAvailableTags = false
        let snapshot = makeSnapshot(id: "a1", link: nil)
        coordinator.rows = [snapshot]

        let tableView = FakeClickedRowTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main")))
        tableView.dataSource = coordinator
        tableView.reloadData()
        tableView.fakeClickedRow = 0
        coordinator.weakTableView = tableView

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = coordinator

        coordinator.menuNeedsUpdate(menu)
        menu.update()

        let tagItem = menu.items.first { $0.title == L10n.articleAssignTagCommand }
        let copyLinkItem = menu.items.first { $0.title == L10n.articleCopyLinkCommand }
        #expect(tagItem?.isEnabled == false)
        #expect(copyLinkItem?.isEnabled == false)
    }
}

/// Test-Double für `NSTableView.clickedRow` — die echte Property ist
/// read-only und lässt sich nicht per KVC oder Event-Synthese ohne echtes
/// Fenster zuverlässig setzen. `clickedRow` ist als ObjC-`dynamic`-Property
/// deklariert und damit überschreibbar.
private final class FakeClickedRowTableView: NSTableView {
    var fakeClickedRow: Int = -1
    override var clickedRow: Int { fakeClickedRow }
}
