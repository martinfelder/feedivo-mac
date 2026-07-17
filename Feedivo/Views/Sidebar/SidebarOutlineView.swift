import AppKit
import SwiftUI

enum SidebarFeedContextAction {
    case rename
    case showProperties
    case delete
}

enum SidebarFolderContextAction {
    case delete
}

enum SidebarSmartFolderContextAction {
    case edit
    case duplicate
    case delete
}

/// NSOutlineView zeichnet für jedes Element mit isItemExpandable == true
/// automatisch ein eigenes natives Disclosure-Dreieck im outlineTableColumn
/// — unabhängig von indentationPerLevel/style, die nur Einrückung bzw.
/// Zeilen-Chrome betreffen, nicht dieses Dreieck selbst. Da jede Zeile
/// bereits ihren eigenen SwiftUI-Chevron mitbringt (siehe rowContent),
/// führte die native Zeichnung zu einem sichtbar doppelten Pfeil pro
/// Zeile (Nutzer-Report per Screenshot, 2026-07-15, unmittelbar bei der
/// ersten Live-Verifikation nach der NSOutlineView-Migration gefunden).
/// Der Standard-AppKit-Weg, das native Dreieck zu unterdrücken OHNE
/// programmatisches expandItem/collapseItem zu beeinträchtigen (worauf
/// unser SwiftUI-gesteuerter Expand/Collapse-Zustand angewiesen ist):
/// frameOfOutlineCell(atRow:) auf .zero überschreiben — isItemExpandable
/// bleibt unverändert true, AppKit zeichnet das Dreieck nur nicht mehr,
/// weil ihm dafür kein Platz gemeldet wird.
// Nicht mehr `private`: FeedJumpKeyMonitor.swift muss diese konkrete Klasse
// von SwiftUIs eigener, intern ebenfalls NSOutlineView-basierter List-
// Implementierung (SwiftUIOutlineListView) unterscheiden können — ein reiner
// `is NSOutlineView`-Check würde sonst auch die Artikelliste selbst
// fälschlich als "Sidebar" ausschließen (live per TEMP-DEBUG gefunden,
// 2026-07-17).
final class SidebarOutlineViewControl: NSOutlineView {
    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        .zero
    }

    /// Sicherheitsnetz für die Ordner-Drop-Hervorhebung (siehe Coordinator.
    /// setHighlightedFolder): validateDrop/acceptDrop decken alle Fälle ab,
    /// bei denen der Drag über der Outline endet — verlässt der Drag die
    /// Sidebar komplett (Drop außerhalb, Abbruch per Escape), feuert weder
    /// validateDrop noch acceptDrop erneut, die Hervorhebung würde sonst
    /// hängen bleiben.
    var onDraggingExited: (() -> Void)?

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDraggingExited?()
        super.draggingExited(sender)
    }
}

/// NSViewRepresentable-Bridge, die die komplette Sidebar (Smart Folders,
/// Tags, Ordner/Feeds) als einzelne NSOutlineView rendert. Zeilen werden per
/// NSHostingView aus den unveränderten bestehenden SwiftUI-Row-Views gebaut
/// (FeedRowView, SidebarOutlineFolderRow, SmartFolderSidebarRow,
/// TagSidebarRow) — siehe Design-Spec „Zeilen-Rendering & Interaktion".
struct SidebarOutlineView: NSViewRepresentable {
    let rootNodes: [SidebarOutlineNode]

    @Binding var selection: SidebarSelection?
    @Binding var collapsedFolderNames: Set<String>
    @Binding var isSmartFoldersCollapsed: Bool
    @Binding var isCustomSmartFoldersCollapsed: Bool
    @Binding var isTagsCollapsed: Bool
    @Binding var isFoldersCollapsed: Bool

    let badgeSnapshot: SmartFolderSidebarBadgeSnapshot
    let mixedCountsByDefaultKey: [String: SmartFolderMixedCounts]

    let renameFeed: (_ id: String, _ newTitle: String) throws -> Void
    let renameFolder: (_ oldName: String, _ newName: String) throws -> Void
    let onFeedContextAction: (SidebarFeedContextAction, FeedSidebarSnapshot) -> Void
    let onFolderContextAction: (SidebarFolderContextAction, String) -> Void
    let onSmartFolderContextAction: (SidebarSmartFolderContextAction, SQLiteSmartFolderSnapshot) -> Void
    let onTagsManageRequested: () -> Void
    let onCreateSmartFolderRequested: () -> Void
    let onSortFoldersAlphabetically: () -> Void

    let moveFeed: (_ id: String, _ toFolderName: String?, _ targetIndex: Int) -> Void
    let moveFolder: (_ name: String, _ targetIndex: Int) -> Void
    let moveTag: (_ id: String, _ targetIndex: Int) -> Void
    let moveSmartFolder: (_ id: String, _ targetIndex: Int, _ isDefault: Bool) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let outlineView = SidebarOutlineViewControl()
        outlineView.headerView = nil
        outlineView.style = .plain
        // Eigenes SwiftUI-gesteuertes Auswahl-Highlighting (siehe FeedRowView/
        // SidebarRowButtonStyle) — NSOutlineView verwaltet bewusst KEINE eigene
        // Zeilenauswahl, siehe Design-Spec „Zeilen-Rendering & Interaktion".
        outlineView.selectionHighlightStyle = .none
        outlineView.indentationPerLevel = 0
        outlineView.rowSizeStyle = .custom
        outlineView.backgroundColor = .clear
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        outlineView.registerForDraggedTypes([
            .feedivoFeedDragItem,
            .feedivoFolderDragItem,
            .feedivoTagDragItem,
            .feedivoSmartFolderDragItem
        ])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)

        let column = NSTableColumn(identifier: .init("SidebarColumn"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = true

        context.coordinator.outlineView = outlineView
        outlineView.onDraggingExited = { [weak coordinator = context.coordinator] in
            coordinator?.setHighlightedFolder(name: nil)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.reload()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: SidebarOutlineView
        weak var outlineView: NSOutlineView?

        /// Name des Ordners, der gerade als Ziel eines laufenden Feed-Drags
        /// hervorgehoben werden soll (eigene SwiftUI-Hervorhebung statt
        /// nativer AppKit-Drop-Optik, siehe SidebarOutlineFolderRow). Von
        /// validateDrop gepflegt, in acceptDrop/draggingExited zurückgesetzt.
        private var highlightedFolderName: String?

        /// Flache ID-Sequenz (Pre-Order) des zuletzt aufgebauten Baums —
        /// erfasst Knotenanzahl, -reihenfolge und Eltern-Kind-Zuordnung
        /// (nicht aber Zähler/Titel/Badges, die nicht Teil der ID sind, siehe
        /// SidebarOutlineNode.buildTree). Dient reload() dazu, reine Inhalts-
        /// Änderungen (z. B. Ungelesen-Zähler nach jedem Artikel-Lesen) von
        /// echten Struktur-Änderungen (neuer/entfernter/verschobener Feed,
        /// Tag, Ordner, Smart Folder) zu unterscheiden.
        private var lastNodeSignature: [String]?

        init(parent: SidebarOutlineView) {
            self.parent = parent
        }

        /// Aktualisiert die Drop-Ziel-Hervorhebung, falls sich der Ordnername
        /// geändert hat, und rendert nur die betroffene(n) sichtbare(n)
        /// Zeile(n) neu (kein vollständiges reloadData() bei jedem
        /// Mausbewegungs-Event während des Drags).
        fileprivate func setHighlightedFolder(name: String?) {
            guard name != highlightedFolderName else { return }

            let previousName = highlightedFolderName
            highlightedFolderName = name

            if let previousName {
                refreshFolderRow(named: previousName)
            }
            if let name {
                refreshFolderRow(named: name)
            }
        }

        private func refreshFolderRow(named name: String) {
            guard let outlineView,
                  let node = SidebarOutlineNode.find(id: "folder:\(name)", in: parent.rootNodes)
            else {
                return
            }

            let row = outlineView.row(forItem: node)
            guard row >= 0,
                  let cellView = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
                  let hostingView = cellView.subviews.first as? NSHostingView<AnyView>
            else {
                return
            }

            hostingView.rootView = AnyView(rowContent(for: node))
        }

        /// Baut die Outline neu auf und stellt danach den Expansion-Zustand
        /// aus den @AppStorage-gespiegelten Bindings wieder her. Selektion
        /// bleibt unberührt — sie wird ausschließlich von den select()-
        /// Closures innerhalb der gehosteten SwiftUI-Row-Views gesetzt, nie
        /// von NSOutlineView selbst.
        ///
        /// Performance: `SidebarView` baut `rootNodes` bei jedem Re-Render
        /// komplett neu auf (siehe `SidebarOutlineNode.buildTree`) — auch
        /// dann, wenn sich nur Zähler/Titel/Badges geändert haben, z. B.
        /// nach jedem einzelnen Artikel-Lesen (`sqliteStatusVersion` bumpt).
        /// Ein bedingungsloses `reloadData()` würde in diesem sehr
        /// häufigen Fall die komplette Outline (alle Feed-/Ordner-/Tag-/
        /// Smart-Folder-Zeilen) neu aufbauen, obwohl sich die Baumstruktur
        /// gar nicht geändert hat. Da `SidebarOutlineNode`s ID stabil ist
        /// und ausschließlich die Entität identifiziert, nicht deren
        /// veränderliche Felder (siehe SidebarOutlineNode.buildTree), lässt
        /// sich anhand einer flachen ID-Sequenz zuverlässig erkennen, ob
        /// sich die Struktur überhaupt verändert hat. Ist das nicht der
        /// Fall, wird nur der gehostete SwiftUI-Inhalt der aktuell
        /// sichtbaren Zeilen aktualisiert (siehe refreshAllVisibleRowContents),
        /// ohne reloadData() — echte Struktur-Änderungen (neuer/entfernter/
        /// verschobener Feed, Tag, Ordner, Smart Folder) lösen weiterhin ein
        /// vollständiges reloadData() aus.
        func reload() {
            guard let outlineView else { return }

            let newSignature = Self.nodeIdentitySignature(parent.rootNodes)
            if newSignature == lastNodeSignature {
                refreshAllVisibleRowContents()
            } else {
                lastNodeSignature = newSignature
                outlineView.reloadData()
            }
            restoreExpansionState()
        }

        private static func nodeIdentitySignature(_ nodes: [SidebarOutlineNode]) -> [String] {
            nodes.flatMap { [$0.id] + nodeIdentitySignature($0.children) }
        }

        /// Aktualisiert für alle aktuell sichtbaren (bereits materialisierten)
        /// Zeilen nur den gehosteten SwiftUI-Inhalt neu (analog zu
        /// refreshFolderRow), ohne reloadData() — für den häufigen Fall, dass
        /// sich nur Zähler/Titel/Badges geändert haben, siehe reload().
        /// Zeilen außerhalb des sichtbaren Bereichs werden hier bewusst nicht
        /// angefasst (makeIfNecessary: false erzwingt keine Instanziierung);
        /// sie zeigen beim Scrollen trotzdem sofort den aktuellen Stand, weil
        /// outlineView(_:viewFor:item:) den Knoten grundsätzlich frisch per
        /// ID nachschlägt statt dem ggf. veralteten `item`-Objekt zu
        /// vertrauen (siehe dort).
        private func refreshAllVisibleRowContents() {
            guard let outlineView else { return }

            for row in 0..<outlineView.numberOfRows {
                guard let cachedNode = outlineView.item(atRow: row) as? SidebarOutlineNode,
                      let node = SidebarOutlineNode.find(id: cachedNode.id, in: parent.rootNodes),
                      let cellView = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
                      let hostingView = cellView.subviews.first as? NSHostingView<AnyView>
                else {
                    continue
                }

                hostingView.rootView = AnyView(rowContent(for: node))
            }
        }

        private func restoreExpansionState() {
            guard let outlineView else { return }

            for header in parent.rootNodes {
                let shouldExpand: Bool
                switch header.payload {
                case .smartFoldersHeader(isDefault: true):
                    shouldExpand = !parent.isSmartFoldersCollapsed
                case .smartFoldersHeader(isDefault: false):
                    shouldExpand = !parent.isCustomSmartFoldersCollapsed
                case .tagsHeader:
                    shouldExpand = !parent.isTagsCollapsed
                case .foldersHeader:
                    shouldExpand = !parent.isFoldersCollapsed
                default:
                    shouldExpand = true
                }

                if shouldExpand {
                    outlineView.expandItem(header)
                } else {
                    outlineView.collapseItem(header)
                }

                if case .foldersHeader = header.payload {
                    for child in header.children {
                        guard case .folder(let name) = child.payload else { continue }
                        if parent.collapsedFolderNames.contains(name) {
                            outlineView.collapseItem(child)
                        } else {
                            outlineView.expandItem(child)
                        }
                    }
                }
            }
        }

        // MARK: - NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let item else { return parent.rootNodes.count }
            return (item as? SidebarOutlineNode)?.children.count ?? 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let item else { return parent.rootNodes[index] }
            guard let node = item as? SidebarOutlineNode else {
                preconditionFailure("Unerwarteter Item-Typ in SidebarOutlineView")
            }
            return node.children[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? SidebarOutlineNode else { return false }
            return !node.children.isEmpty
        }

        // MARK: - NSOutlineViewDelegate

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            // NSOutlineView verwaltet bewusst keine eigene Auswahl — siehe
            // Design-Spec „Zeilen-Rendering & Interaktion".
            false
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            guard let node = item as? SidebarOutlineNode else { return 30 }
            switch node.payload {
            case .feed:
                return 30
            case .smartFoldersHeader, .tagsHeader, .foldersHeader:
                return 36
            case .folder:
                // 24pt (wie die reinen Text-Header) erwies sich beim Live-
                // Testen als zu kleine Drop-Zone für Feed-Drops auf Ordner —
                // 30pt (wie Feed-/Tag-/Smart-Folder-Zeilen) angeglichen,
                // 2026-07-15 Nutzer-Report nach Log-Analyse.
                return 30
            case .smartFolder:
                return 34
            case .tag:
                return 30
            case .emptyPlaceholder:
                return 28
            }
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let cachedNode = item as? SidebarOutlineNode else { return nil }
            // `item` kann nach einer inhaltsbedingten Aktualisierung ohne
            // reloadData() (siehe reload()/refreshAllVisibleRowContents) noch
            // die alte Knoteninstanz sein — per ID immer den aktuellsten
            // Stand aus rootNodes nachschlagen, damit neu ins Bild
            // gescrollte Zeilen nie veraltete Zähler/Titel/Badges zeigen.
            let node = SidebarOutlineNode.find(id: cachedNode.id, in: parent.rootNodes) ?? cachedNode

            let identifier = NSUserInterfaceItemIdentifier("SidebarOutlineCell")
            let cellView: NSTableCellView
            let hostingView: NSHostingView<AnyView>

            if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView,
               let reusedHosting = reused.subviews.first as? NSHostingView<AnyView> {
                cellView = reused
                hostingView = reusedHosting
            } else {
                cellView = NSTableCellView()
                cellView.identifier = identifier
                hostingView = NSHostingView(rootView: AnyView(EmptyView()))
                hostingView.translatesAutoresizingMaskIntoConstraints = false
                cellView.addSubview(hostingView)
                NSLayoutConstraint.activate([
                    hostingView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor),
                    hostingView.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
                    hostingView.topAnchor.constraint(equalTo: cellView.topAnchor),
                    hostingView.bottomAnchor.constraint(equalTo: cellView.bottomAnchor)
                ])

                // NSOutlineViews eigene, automatische Drag-Erkennung basiert auf
                // mouseDown(with:), das nie ausgelöst wird, wenn die Zeile
                // vollständig interaktiven SwiftUI-Inhalt hostet (Button/
                // .onTapGesture übersetzen sich intern in eigene AppKit-Gesture-
                // Recognizer, die das Event am Blattelement abfangen, bevor es je
                // bei einem mouseDown-Override eines Vorfahren ankommt — per
                // temporärem Diagnose-Override auf der NSOutlineView verifiziert:
                // feuerte beim Ziehen NIE, 2026-07-15 Nutzer-Report "kein Drag-
                // Vorschaubild"). Fix: ein eigener NSPanGestureRecognizer, der auf
                // derselben Event-Sequenz parallel zu SwiftUIs Recognizern
                // mitläuft (Gesture-Recognizer blockieren sich in AppKit nicht
                // gegenseitig, außer bei explizit gesetzter Exklusivität/
                // Fehlschlag-Abhängigkeit) und erst bei tatsächlicher Zugbewegung
                // (State .began, NSPanGestureRecognizer hat eine eingebaute
                // Mindestbewegung) selbst eine Drag-Session startet — ein reiner
                // Klick unterschreitet diese Schwelle und bleibt unberührt.
                let dragRecognizer = NSPanGestureRecognizer(
                    target: self,
                    action: #selector(handleRowDragGesture(_:))
                )
                cellView.addGestureRecognizer(dragRecognizer)
            }

            hostingView.rootView = AnyView(rowContent(for: node))
            return cellView
        }

        @ViewBuilder
        private func rowContent(for node: SidebarOutlineNode) -> some View {
            // Lokale Kopie: `parent` innerhalb dieser Methode direkt (ohne
            // "self.") aus verschachtelten SwiftUI-Closures (Button-Actions,
            // contextMenu, ...) heraus zu referenzieren, verlangt der
            // Compiler explizites "self." (escaping-Closure-Regel). Eine
            // lokale Konstante umgeht das, ohne jede Stelle einzeln mit
            // "self." zu versehen.
            let parent = self.parent
            switch node.payload {
            case .smartFoldersHeader(let isDefault):
                sectionHeaderRow(
                    title: isDefault ? L10n.sidebarSmartFoldersSection : L10n.sidebarSmartFoldersCustomSection,
                    isCollapsed: isDefault ? parent.isSmartFoldersCollapsed : parent.isCustomSmartFoldersCollapsed,
                    actionSystemImage: isDefault ? nil : "plus",
                    action: isDefault ? nil : parent.onCreateSmartFolderRequested,
                    toggle: {
                        if isDefault {
                            parent.isSmartFoldersCollapsed.toggle()
                        } else {
                            parent.isCustomSmartFoldersCollapsed.toggle()
                        }
                    }
                )
            case .smartFolder(let smartFolder):
                Button {
                    parent.selection = .smartFolder(smartFolder.id)
                } label: {
                    SmartFolderSidebarRow(
                        smartFolder: smartFolder,
                        badgeSnapshot: parent.badgeSnapshot,
                        mixedCounts: smartFolder.defaultKey.flatMap { parent.mixedCountsByDefaultKey[$0] }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(
                    SidebarRowButtonStyle(
                        isSelected: parent.selection == .smartFolder(smartFolder.id),
                        leadingIndent: 6,
                        rowHeight: 34
                    )
                )
                .contextMenu {
                    Button {
                        parent.onSmartFolderContextAction(.edit, smartFolder)
                    } label: {
                        Label(L10n.ruleEditButton, systemImage: "pencil")
                    }
                    Button {
                        parent.onSmartFolderContextAction(.duplicate, smartFolder)
                    } label: {
                        Label(L10n.commonDuplicate, systemImage: "plus.square.on.square")
                    }
                    Divider()
                    Button(role: .destructive) {
                        parent.onSmartFolderContextAction(.delete, smartFolder)
                    } label: {
                        Label(L10n.ruleDeleteButton, systemImage: "trash")
                    }
                }
            case .tagsHeader:
                let tagCount = node.children.reduce(into: 0) { count, child in
                    if case .tag = child.payload { count += 1 }
                }
                sectionHeaderRow(
                    title: L10n.sidebarTagsSection,
                    count: tagCount,
                    isCollapsed: parent.isTagsCollapsed,
                    actionSystemImage: "tag",
                    action: parent.onTagsManageRequested,
                    toggle: { parent.isTagsCollapsed.toggle() }
                )
            case .tag(let tag):
                Button {
                    parent.selection = .tag(tag.id)
                } label: {
                    TagSidebarRow(tag: tag, badgeText: SidebarUnreadCount.badgeText(for: tag.articleCount))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(
                    SidebarRowButtonStyle(
                        isSelected: parent.selection == .tag(tag.id),
                        leadingIndent: 6,
                        rowHeight: 30
                    )
                )
            case .foldersHeader:
                let folderCount = node.children.reduce(into: 0) { count, child in
                    if case .folder = child.payload { count += 1 }
                }
                HStack {
                    Button {
                        parent.isFoldersCollapsed.toggle()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: parent.isFoldersCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 12)
                            HStack(spacing: 4) {
                                Text(L10n.sidebarFoldersSection)
                                    .textCase(.uppercase)
                                if folderCount > 0 {
                                    Text("(\(folderCount))")
                                }
                            }
                            .font(.system(size: 14, weight: .bold))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Ermöglicht, eine versehentliche manuelle Umsortierung
                    // per Drag & Drop wieder rückgängig zu machen — Nutzer-
                    // Wunsch nach der Live-Verifikation der Drag&Drop-
                    // Migration, 2026-07-15.
                    Menu {
                        Button {
                            parent.onSortFoldersAlphabetically()
                        } label: {
                            Label(L10n.sidebarFoldersSortAlphabetically, systemImage: "textformat.abc")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 22, height: 22)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                .foregroundStyle(SidebarStyle.sectionText)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
                .frame(maxHeight: .infinity, alignment: .bottom)
            case .folder(let name):
                SidebarOutlineFolderRow(
                    name: name,
                    isCollapsed: parent.collapsedFolderNames.contains(name),
                    isEmpty: node.children.isEmpty,
                    isDropTarget: highlightedFolderName == name,
                    toggle: { parent.collapsedFolderNames.formSymmetricDifference([name]) },
                    renameFolder: { newName in try parent.renameFolder(name, newName) },
                    deleteFolder: { parent.onFolderContextAction(.delete, name) }
                )
            case .feed(let snapshot):
                feedRow(snapshot: snapshot, isIndented: snapshot.folderName != nil)
            case .emptyPlaceholder(let text):
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(SidebarStyle.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
        }

        @ViewBuilder
        private func sectionHeaderRow(
            title: LocalizedStringKey,
            count: Int? = nil,
            isCollapsed: Bool,
            actionSystemImage: String?,
            action: (() -> Void)?,
            toggle: @escaping () -> Void
        ) -> some View {
            HStack {
                Button(action: toggle) {
                    HStack(spacing: 7) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 12)
                        HStack(spacing: 4) {
                            Text(title)
                                .textCase(.uppercase)
                            if let count, count > 0 {
                                Text("(\(count))")
                            }
                        }
                        .font(.system(size: 14, weight: .bold))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if let actionSystemImage, let action {
                    Button(action: action) {
                        Image(systemName: actionSystemImage)
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(SidebarStyle.sectionText)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }

        @ViewBuilder
        private func feedRow(snapshot: FeedSidebarSnapshot, isIndented: Bool) -> some View {
            // Siehe Kommentar in rowContent(for:) — lokale Kopie, damit
            // "parent" ohne explizites "self." in den verschachtelten
            // Closures unten (select/renameFeed/contextMenu) referenziert
            // werden kann.
            let parent = self.parent
            FeedRowView(
                snapshot: snapshot,
                displayStyle: isIndented ? .folderChild : .regular,
                isSelected: parent.selection == .feed(snapshot.id),
                select: { parent.selection = .feed(snapshot.id) },
                renameFeed: { newName in
                    try parent.renameFeed(snapshot.id, newName)
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                Button {
                    parent.onFeedContextAction(.rename, snapshot)
                } label: {
                    Label(L10n.feedRenameCommand, systemImage: "pencil")
                }
                Button {
                    parent.onFeedContextAction(.showProperties, snapshot)
                } label: {
                    Label(L10n.feedPropertiesCommand, systemImage: "info.circle")
                }
                Divider()
                Button(role: .destructive) {
                    parent.onFeedContextAction(.delete, snapshot)
                } label: {
                    Label(L10n.feedDeleteCommand, systemImage: "trash")
                }
            }
        }

        // MARK: - Drag & Drop

        /// Startet manuell eine Drag-Session, sobald der NSPanGestureRecognizer
        /// (angehängt an jede frisch erzeugte Zeile in viewFor:item:) eine
        /// tatsächliche Zugbewegung erkennt — siehe Erklärung dort. Nutzt
        /// denselben NSPasteboardWriting-Aufbau wie pasteboardWriterForItem, das
        /// bei gehostetem interaktivem SwiftUI-Inhalt nie von NSOutlineViews
        /// eigener automatischer Drag-Erkennung erreicht wird.
        @objc private func handleRowDragGesture(_ recognizer: NSPanGestureRecognizer) {
            guard recognizer.state == .began else { return }
            guard let outlineView, let cellView = recognizer.view else { return }

            let row = outlineView.row(for: cellView)
            guard row >= 0,
                  let node = outlineView.item(atRow: row) as? SidebarOutlineNode,
                  let writer = self.outlineView(outlineView, pasteboardWriterForItem: node),
                  let event = NSApp.currentEvent
            else {
                return
            }

            let draggingItem = NSDraggingItem(pasteboardWriter: writer)
            // setDraggingFrame erwartet die Frame-Angabe im Koordinatensystem
            // der Quell-View (outlineView), NICHT im lokalen Koordinatensystem
            // der Zeile selbst — sonst erscheint das Vorschaubild am oberen
            // Rand der Outline statt am tatsächlichen Mauszeiger (gefunden
            // 2026-07-15 per Nutzer-Report: Zielen beim Drop war ungenau,
            // sichtbare Rückmeldung entsprach nicht der echten Zeigerposition).
            let frameInOutlineView = cellView.convert(cellView.bounds, to: outlineView)
            draggingItem.setDraggingFrame(frameInOutlineView, contents: Self.dragImage(for: cellView))
            outlineView.beginDraggingSession(with: [draggingItem], event: event, source: outlineView)
        }

        private static func dragImage(for view: NSView) -> NSImage {
            guard view.bounds.width > 0, view.bounds.height > 0,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else {
                return NSImage(size: view.bounds.size)
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            let image = NSImage(size: view.bounds.size)
            image.addRepresentation(rep)
            return image
        }

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let node = item as? SidebarOutlineNode else { return nil }
            guard node.isDraggable else { return nil }

            switch node.payload {
            case .feed(let snapshot):
                return SidebarFeedPasteboardItem(feedID: snapshot.id)
            case .folder(let name):
                return SidebarFolderPasteboardItem(folderName: name)
            case .tag(let tag):
                return SidebarTagPasteboardItem(tagID: tag.id)
            case .smartFolder(let folder):
                return SidebarSmartFolderPasteboardItem(smartFolderID: folder.id)
            default:
                return nil
            }
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            validateDrop info: NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex index: Int
        ) -> NSDragOperation {
            let target = resolveDropTarget(info: info, proposedItem: item, proposedChildIndex: index)

            if case .feedDrop(let folderName, _)? = target {
                setHighlightedFolder(name: folderName)
            } else {
                setHighlightedFolder(name: nil)
            }

            return target == nil ? [] : .move
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            acceptDrop info: NSDraggingInfo,
            item: Any?,
            childIndex index: Int
        ) -> Bool {
            setHighlightedFolder(name: nil)
            guard let target = resolveDropTarget(info: info, proposedItem: item, proposedChildIndex: index) else {
                return false
            }

            switch target {
            case .feedDrop(let folderName, let targetIndex):
                guard let feedID = draggedID(from: info, type: .feedivoFeedDragItem) else { return false }
                parent.moveFeed(feedID, folderName, targetIndex)
            case .folderReorder(let targetIndex):
                guard let folderName = draggedID(from: info, type: .feedivoFolderDragItem) else { return false }
                parent.moveFolder(folderName, targetIndex)
            case .tagReorder(let targetIndex):
                guard let tagID = draggedID(from: info, type: .feedivoTagDragItem) else { return false }
                parent.moveTag(tagID, targetIndex)
            case .smartFolderReorder(let isDefault, let targetIndex):
                guard let smartFolderID = draggedID(from: info, type: .feedivoSmartFolderDragItem) else { return false }
                parent.moveSmartFolder(smartFolderID, targetIndex, isDefault)
            }
            return true
        }

        private func draggedID(from info: NSDraggingInfo, type: NSPasteboard.PasteboardType) -> String? {
            info.draggingPasteboard.string(forType: type)
        }

        private func resolveDropTarget(
            info: NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex index: Int
        ) -> SidebarOutlineDropTarget? {
            let proposedParent = item as? SidebarOutlineNode

            let draggedNodeID: String?
            if let feedID = draggedID(from: info, type: .feedivoFeedDragItem) {
                draggedNodeID = "feed:\(feedID)"
            } else if let folderName = draggedID(from: info, type: .feedivoFolderDragItem) {
                draggedNodeID = "folder:\(folderName)"
            } else if let tagID = draggedID(from: info, type: .feedivoTagDragItem) {
                draggedNodeID = "tag:\(tagID)"
            } else if let smartFolderID = draggedID(from: info, type: .feedivoSmartFolderDragItem) {
                draggedNodeID = "smartFolder:\(smartFolderID)"
            } else {
                draggedNodeID = nil
            }

            guard let draggedNodeID else { return nil }

            return SidebarOutlineDropPolicy.resolve(
                draggedNodeID: draggedNodeID,
                proposedParent: proposedParent,
                proposedChildIndex: index,
                rootNodes: parent.rootNodes
            )
        }
    }
}

/// Eigenständige View statt reiner @ViewBuilder-Methode, da Inline-Rename
/// lokalen @State/@FocusState braucht — analog zu FeedRowView.
private struct SidebarOutlineFolderRow: View {
    let name: String
    let isCollapsed: Bool
    /// Ob der Ordner aktuell keine Feeds enthält — Löschen wird (wie in der
    /// alten SwiftUI-Implementierung) nur für leere Ordner angeboten (siehe
    /// Whole-Branch-Review-Fix 3).
    let isEmpty: Bool
    /// Ob dieser Ordner aktuell das Ziel eines laufenden Feed-Drags ist —
    /// eigene, SwiftUI-gezeichnete Hervorhebung, weil NSOutlineViews native
    /// Drop-Hervorhebung vom gehosteten SwiftUI-Inhalt der Zeile überdeckt
    /// wird (Nutzer sah beim Hovern nur eine dünne Einfüge-Linie statt einer
    /// Box, 2026-07-15). Wird vom Coordinator in validateDrop/acceptDrop
    /// gepflegt, siehe dort.
    let isDropTarget: Bool
    let toggle: () -> Void
    let renameFolder: (String) throws -> Void
    let deleteFolder: () -> Void

    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var renameErrorMessage: String?
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                Button(action: toggle) {
                    HStack(spacing: 9) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(SidebarStyle.secondaryText)
                            .frame(width: 12)
                        Image(systemName: "folder")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 20)
                    }
                }
                .buttonStyle(.plain)

                if isEditingName {
                    TextField(name, text: $editedName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, weight: .medium))
                        .focused($isNameFieldFocused)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(renameErrorMessage != nil ? Color.red : Color.clear, lineWidth: 1)
                        }
                        .onSubmit { commitOrShowError() }
                        .onExitCommand { cancelEditing() }
                        .onChange(of: isNameFieldFocused) { wasFocused, isFocused in
                            if wasFocused, !isFocused, isEditingName {
                                commitOrShowError()
                            }
                        }
                } else {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isDropTarget ? .white : SidebarStyle.primaryText.opacity(0.82))
                        .lineLimit(1)
                        .padding(.horizontal, isDropTarget ? 7 : 0)
                        .padding(.vertical, isDropTarget ? 2 : 0)
                        .background {
                            if isDropTarget {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { beginEditing() }
                        .onTapGesture(count: 1) { toggle() }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .contextMenu {
                Button {
                    beginEditing()
                } label: {
                    Label(L10n.sidebarFolderRenameCommand, systemImage: "pencil")
                }
                if isEmpty {
                    Button(role: .destructive) {
                        deleteFolder()
                    } label: {
                        Label(L10n.commonDelete, systemImage: "trash")
                    }
                }
            }

            if let renameErrorMessage {
                Text(renameErrorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.leading, 16 + 12 + 9 + 20 + 9)
                    .padding(.trailing, 16)
            }
        }
    }

    private func beginEditing() {
        editedName = name
        renameErrorMessage = nil
        isEditingName = true
        isNameFieldFocused = true
    }

    private func cancelEditing() {
        editedName = name
        renameErrorMessage = nil
        isEditingName = false
    }

    private func commitOrShowError() {
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName != name else {
            isEditingName = false
            renameErrorMessage = nil
            return
        }
        do {
            try renameFolder(trimmedName)
            isEditingName = false
            renameErrorMessage = nil
        } catch {
            renameErrorMessage = error.localizedDescription
        }
    }
}

enum SidebarOutlineDropTarget: Equatable {
    case feedDrop(folderName: String?, targetIndex: Int)
    case folderReorder(targetIndex: Int)
    case tagReorder(targetIndex: Int)
    case smartFolderReorder(isDefault: Bool, targetIndex: Int)
}

/// Reine, AppKit-unabhängige Entscheidungslogik: übersetzt einen
/// vorgeschlagenen Drop (gezogener Knoten + Zielelternknoten + Zielindex)
/// in eine der vier erlaubten Aktionen — oder nil, falls der Drop laut den
/// Scoping-Regeln aus der Design-Spec nicht erlaubt ist. Die eigentlichen
/// NSOutlineViewDelegate-Methoden (validateDrop/acceptDrop) sind dünne
/// Wrapper darum, die nur zwischen NSOutlineView-Typen und diesen reinen
/// Swift-Werten übersetzen.
enum SidebarOutlineDropPolicy {
    static func resolve(
        draggedNodeID: String,
        proposedParent: SidebarOutlineNode?,
        proposedChildIndex: Int,
        rootNodes: [SidebarOutlineNode]
    ) -> SidebarOutlineDropTarget? {
        guard let draggedNode = SidebarOutlineNode.find(id: draggedNodeID, in: rootNodes) else {
            return nil
        }

        switch draggedNode.payload {
        case .feed:
            return resolveFeedDrop(
                draggedNode: draggedNode,
                proposedParent: proposedParent,
                proposedChildIndex: proposedChildIndex
            )
        case .folder:
            guard let foldersHeader = rootNodes.first(where: { $0.id == "header.folders" }),
                  proposedParent?.id == "header.folders"
            else {
                return nil
            }
            let index = clampedIndex(proposedChildIndex, siblingCount: foldersHeader.children.count, draggedID: draggedNode.id, siblings: foldersHeader.children)
            return .folderReorder(targetIndex: index)
        case .tag:
            guard let tagsHeader = rootNodes.first(where: { $0.id == "header.tags" }),
                  proposedParent?.id == "header.tags"
            else {
                return nil
            }
            let index = clampedIndex(proposedChildIndex, siblingCount: tagsHeader.children.count, draggedID: draggedNode.id, siblings: tagsHeader.children)
            return .tagReorder(targetIndex: index)
        case .smartFolder:
            guard let proposedParent,
                  proposedParent.id == "header.smartFolders.default" || proposedParent.id == "header.smartFolders.custom"
            else {
                return nil
            }
            // Ein Standard-Smart-Folder darf nur innerhalb der Standard-
            // Gruppe bleiben, ein eigener nur innerhalb der Eigene-Gruppe —
            // ermittelt über den Elternknoten, in dem der gezogene Knoten
            // tatsächlich aktuell steckt.
            guard let currentParent = parent(of: draggedNode, in: rootNodes),
                  currentParent.id == proposedParent.id
            else {
                return nil
            }
            let isDefault = proposedParent.id == "header.smartFolders.default"
            let index = clampedIndex(proposedChildIndex, siblingCount: proposedParent.children.count, draggedID: draggedNode.id, siblings: proposedParent.children)
            return .smartFolderReorder(isDefault: isDefault, targetIndex: index)
        default:
            return nil
        }
    }

    private static func resolveFeedDrop(
        draggedNode: SidebarOutlineNode,
        proposedParent: SidebarOutlineNode?,
        proposedChildIndex: Int
    ) -> SidebarOutlineDropTarget? {
        guard let proposedParent else { return nil }

        // Drop "auf" einen Ordner-Knoten (NSOutlineViewDropOnItemIndex): ans
        // Ende des Ordners anhängen.
        if case .folder(let name) = proposedParent.payload, proposedChildIndex == NSOutlineViewDropOnItemIndex {
            return .feedDrop(folderName: name, targetIndex: proposedParent.children.count)
        }

        // Drop innerhalb des ordnerlosen Bereichs (proposedParent ==
        // foldersHeader) oder innerhalb eines Ordners (proposedParent ist
        // die Ordner-Zeile selbst) an einem konkreten Index.
        if proposedParent.id == "header.folders" {
            let index = clampedIndex(proposedChildIndex, siblingCount: proposedParent.children.count, draggedID: draggedNode.id, siblings: proposedParent.children)
            return .feedDrop(folderName: nil, targetIndex: index)
        }
        if case .folder(let name) = proposedParent.payload {
            let index = clampedIndex(proposedChildIndex, siblingCount: proposedParent.children.count, draggedID: draggedNode.id, siblings: proposedParent.children)
            return .feedDrop(folderName: name, targetIndex: index)
        }

        return nil
    }

    /// Findet den direkten Elternknoten von `target` im Baum (nil, falls
    /// `target` ein Wurzelknoten ist oder nicht gefunden wurde).
    private static func parent(of target: SidebarOutlineNode, in nodes: [SidebarOutlineNode]) -> SidebarOutlineNode? {
        for node in nodes {
            if node.children.contains(where: { $0.id == target.id }) {
                return node
            }
            if let found = parent(of: target, in: node.children) {
                return found
            }
        }
        return nil
    }

    /// Klemmt den vorgeschlagenen Index auf den gültigen Bereich und
    /// korrigiert ihn um eins, falls der gezogene Knoten selbst vor dem
    /// Zielindex in derselben Geschwisterliste steht (analog zur
    /// bestehenden Logik in SidebarView.swift vor dieser Migration).
    private static func clampedIndex(
        _ proposedIndex: Int,
        siblingCount: Int,
        draggedID: String,
        siblings: [SidebarOutlineNode]
    ) -> Int {
        var index = proposedIndex == NSOutlineViewDropOnItemIndex ? siblingCount : proposedIndex
        index = min(max(index, 0), siblingCount)
        if let draggedIndex = siblings.firstIndex(where: { $0.id == draggedID }), draggedIndex < index {
            index -= 1
        }
        return index
    }
}
