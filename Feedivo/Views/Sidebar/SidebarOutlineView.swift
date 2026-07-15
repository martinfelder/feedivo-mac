import AppKit
import SwiftUI

enum SidebarFeedContextAction {
    case rename
    case showProperties
    case delete
}

enum SidebarFolderContextAction {
    case rename
    case delete
}

enum SidebarSmartFolderContextAction {
    case edit
    case duplicate
    case delete
}

/// NSViewRepresentable-Bridge, die die komplette Sidebar (Smart Folders,
/// Tags, Ordner/Feeds) als einzelne NSOutlineView rendert. Zeilen werden per
/// NSHostingView aus den unveränderten bestehenden SwiftUI-Row-Views gebaut
/// (FeedRowView, SidebarFolderSection-Header, CollapsibleSidebarSection-
/// Header, SmartFolderSidebarRow, TagSidebarRow) — siehe Design-Spec
/// „Zeilen-Rendering & Interaktion".
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
    let onCreateFolderRequested: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let outlineView = NSOutlineView()
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
        private var previousRootNodeIDs: [String] = []

        init(parent: SidebarOutlineView) {
            self.parent = parent
        }

        /// Baut die Outline neu auf und stellt danach den Expansion-Zustand
        /// aus den @AppStorage-gespiegelten Bindings wieder her. Selektion
        /// bleibt unberührt — sie wird ausschließlich von den select()-
        /// Closures innerhalb der gehosteten SwiftUI-Row-Views gesetzt, nie
        /// von NSOutlineView selbst.
        func reload() {
            guard let outlineView else { return }

            outlineView.reloadData()
            restoreExpansionState()
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
                return 24
            case .folder:
                return 24
            case .smartFolder, .tag:
                return 30
            case .emptyPlaceholder:
                return 28
            }
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? SidebarOutlineNode else { return nil }

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
                        rowHeight: 30
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
                sectionHeaderRow(
                    title: L10n.sidebarTagsSection,
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
                sectionHeaderRow(
                    title: L10n.sidebarFoldersSection,
                    isCollapsed: parent.isFoldersCollapsed,
                    actionSystemImage: nil,
                    action: nil,
                    toggle: { parent.isFoldersCollapsed.toggle() }
                )
            case .folder(let name):
                SidebarOutlineFolderRow(
                    name: name,
                    isCollapsed: parent.collapsedFolderNames.contains(name),
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
            isCollapsed: Bool,
            actionSystemImage: String?,
            action: (() -> Void)?,
            toggle: @escaping () -> Void
        ) -> some View {
            HStack {
                Button(action: toggle) {
                    HStack(spacing: 7) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 12)
                        Text(title)
                            .font(.system(size: 11, weight: .bold))
                            .textCase(.uppercase)
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
    }
}

/// Eigenständige View statt reiner @ViewBuilder-Methode, da Inline-Rename
/// lokalen @State/@FocusState braucht — analog zu FeedRowView.
private struct SidebarOutlineFolderRow: View {
    let name: String
    let isCollapsed: Bool
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
                        .foregroundStyle(SidebarStyle.primaryText.opacity(0.82))
                        .lineLimit(1)
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
                Button(role: .destructive) {
                    deleteFolder()
                } label: {
                    Label(L10n.commonDelete, systemImage: "trash")
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
