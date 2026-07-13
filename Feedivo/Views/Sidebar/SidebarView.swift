import SwiftUI

struct SidebarView: View {
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    @Binding var selection: SidebarSelection?
    let onRequestAddFeed: () -> Void
    let onRequestRefreshAllFeeds: () -> Void
    let onRequestDeleteFeed: (String) -> Void
    // Bump bei direkter Artikel→Tag-Zuweisung (siehe SidebarBadgeInvalidation).
    // Status-Toggles, Artikel-Zahl und Feed/Tag-Struktur werden automatisch über
    // die Signatur bzw. die SQLite-Snapshots erfasst.
    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey)
    private var directTagVersion = 0
    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersion = 0
    init(
        selection: Binding<SidebarSelection?>,
        onRequestAddFeed: @escaping () -> Void,
        onRequestRefreshAllFeeds: @escaping () -> Void,
        onRequestDeleteFeed: @escaping (String) -> Void
    ) {
        self._selection = selection
        self.onRequestAddFeed = onRequestAddFeed
        self.onRequestRefreshAllFeeds = onRequestRefreshAllFeeds
        self.onRequestDeleteFeed = onRequestDeleteFeed
    }
    @AppStorage(SidebarSectionCollapseState.Section.tags.storageKey)
    private var isTagsCollapsed = false
    @AppStorage(SidebarSectionCollapseState.Section.folders.storageKey)
    private var isFoldersCollapsed = false
    @AppStorage(SidebarSectionCollapseState.Section.smartFolders.storageKey)
    private var isSmartFoldersCollapsed = false
    @AppStorage(SidebarSectionCollapseState.Section.customSmartFolders.storageKey)
    private var isCustomSmartFoldersCollapsed = false
    @AppStorage(SidebarFeedVisibilitySettings.showsReadFeedsKey)
    private var showsReadFeedsInSidebar = SidebarFeedVisibilitySettings.defaultShowsReadFeeds
    @State private var feedShowingProperties: FeedSidebarSnapshot?
    @State private var feedRenaming: FeedSidebarSnapshot?
    @State private var isShowingAddFolderSheet = false
    @State private var isShowingTagManager = false
    @State private var smartFolderEditing: SmartFolderRecord?
    @State private var smartFolderPendingDeletion: SQLiteSmartFolderSnapshot?
    @State private var feedFolderPendingDeletion: FeedFolderRecord?
    @State private var isCreatingSmartFolder = false
    @State private var sqliteSidebarState = SQLiteSidebarState()
    @State private var collapsedFolderNames: Set<String> = []
    @State private var sidebarDefinitionVersion = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sidebarActionRow

                    if let errorMessage = sqliteSidebarState.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }

                    defaultSmartFoldersSection(
                        badgeSnapshot: sqliteSidebarState.smartFolderBadgeSnapshot,
                        mixedCountsByDefaultKey: sqliteSidebarState.mixedCountsByDefaultKey
                    )
                    customSmartFoldersSection(
                        badgeSnapshot: sqliteSidebarState.smartFolderBadgeSnapshot,
                        mixedCountsByDefaultKey: sqliteSidebarState.mixedCountsByDefaultKey
                    )
                    tagsSection
                    foldersSection
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .scrollContentBackground(.hidden)
        }
        .background(SidebarStyle.background)
        .sheet(item: $feedShowingProperties) { snapshot in
            FeedPropertiesView(feedID: snapshot.id)
        }
        .sheet(item: $feedRenaming) { snapshot in
            FeedRenameView(feedID: snapshot.id)
        }
        .sheet(isPresented: $isShowingAddFolderSheet) {
            AddFolderSheet(
                existingFolderNames: FeedFolderOrganizer.folderNames(
                    feedFolderNames: sqliteSidebarState.snapshots.map(\.folderName),
                    explicitFolderNames: sqliteSidebarState.feedFolders.map(\.name)
                ),
                onFolderAdded: {
                    sidebarDefinitionVersion += 1
                }
            )
        }
        .sheet(isPresented: $isShowingTagManager) {
            TagManagerView { tagID in
                selection = .tag(tagID)
            }
        }
        .sheet(isPresented: $isCreatingSmartFolder) {
            SmartFolderEditorView(existingFolders: sqliteSmartFolderRecords())
        }
        .sheet(item: $smartFolderEditing) { smartFolder in
            SmartFolderEditorView(folder: smartFolder, existingFolders: sqliteSmartFolderRecords())
        }
        .confirmationDialog(
            L10n.sidebarSmartFolderDelete,
            isPresented: Binding(
                get: { smartFolderPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        smartFolderPendingDeletion = nil
                    }
                }
            ),
            presenting: smartFolderPendingDeletion
        ) { smartFolder in
            Button(L10n.commonDelete, role: .destructive) {
                deleteSmartFolder(smartFolder)
                if selection == .smartFolder(smartFolder.id) {
                    selection = defaultSmartFolderSelection(excluding: smartFolder)
                }
                smartFolderPendingDeletion = nil
            }
            Button(L10n.commonCancel, role: .cancel) {
                smartFolderPendingDeletion = nil
            }
        }
        .confirmationDialog(
            L10n.commonDelete,
            isPresented: Binding(
                get: { feedFolderPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        feedFolderPendingDeletion = nil
                    }
                }
            ),
            presenting: feedFolderPendingDeletion
        ) { folder in
            Button(L10n.commonDelete, role: .destructive) {
                deleteFeedFolder(folder)
                feedFolderPendingDeletion = nil
            }
            Button(L10n.commonCancel, role: .cancel) {
                feedFolderPendingDeletion = nil
            }
        }
        .task(id: sqliteSidebarReloadToken) {
            sqliteSidebarState.load(database: feedivoDatabase, showsReadFeeds: showsReadFeedsInSidebar)
        }
    }

    private var sidebarActionRow: some View {
        HStack(spacing: 10) {
            Button {
                onRequestRefreshAllFeeds()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(sqliteSidebarState.snapshots.isEmpty)
            .help(L10n.feedRefreshAllCommand)

            createSidebarItemMenu
                .buttonStyle(.borderless)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 2)
    }

    private var createSidebarItemMenu: some View {
        Menu {
            Button {
                onRequestAddFeed()
            } label: {
                Label {
                    Text(L10n.feedAddCommand)
                } icon: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                }
            }

            Button {
                isShowingAddFolderSheet = true
            } label: {
                Label {
                    Text(L10n.sidebarAddFolderButton)
                } icon: {
                    Image(systemName: "folder.badge.plus")
                }
            }
        } label: {
            Image(systemName: "plus")
        }
        .help(L10n.sidebarAddFeedButton)
    }

    private var tagsSection: some View {
        CollapsibleSidebarSection(
            title: L10n.sidebarTagsSection,
            isCollapsed: $isTagsCollapsed,
            actionSystemImage: "tag",
            actionHelp: String(localized: "tagManager.manage.button")
        ) {
            isShowingTagManager = true
        } content: {
            if !sqliteSidebarState.tagSnapshots.isEmpty {
                tagRows(sqliteSidebarState.tagSnapshots)
            }
        }
    }

    private var foldersSection: some View {
        CollapsibleSidebarSection(
            title: L10n.sidebarFoldersSection,
            isCollapsed: $isFoldersCollapsed
        ) {
            // Snapshots sind bereits beim Laden via showsReadFeeds gefiltert.
            let visibleSnapshots = sqliteSidebarState.snapshots

            if visibleSnapshots.isEmpty && sqliteSidebarState.feedFolders.isEmpty {
                Text(L10n.sidebarEmptyTitle)
                    .font(interfaceTextSize.font(size: 13))
                    .foregroundStyle(SidebarStyle.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                let feedsWithoutFolder = FeedFolderOrganizer.feedsWithoutFolder(from: visibleSnapshots)
                if !feedsWithoutFolder.isEmpty {
                    feedRows(feedsWithoutFolder)
                }

                // M9: Feeds einmal pro Ordner gruppieren statt pro Ordnername
                // neu zu filtern (O(Folders·F) → O(F)).
                ForEach(
                    FeedFolderOrganizer.feedsByFolderName(
                        in: visibleSnapshots,
                        folders: sqliteSidebarState.feedFolders
                    ),
                    id: \.folderName
                ) { entry in
                    let isExpanded = !collapsedFolderNames.contains(entry.folderName)
                    let explicitFolder = explicitFeedFolder(named: entry.folderName)
                    SidebarFolderSection(
                        title: entry.folderName,
                        isExpanded: isExpanded,
                        deleteEmptyFolder: entry.snapshots.isEmpty && explicitFolder != nil
                            ? { feedFolderPendingDeletion = explicitFolder }
                            : nil,
                        renameFolder: { newName in
                            try renameFolder(from: entry.folderName, to: newName)
                        }
                    ) {
                        toggleFolder(named: entry.folderName)
                    } content: {
                        if isExpanded {
                            feedRows(
                                entry.snapshots,
                                isIndented: true
                            )
                        }
                    }
                }
            }
        }
    }

    private func defaultSmartFoldersSection(
        badgeSnapshot: SmartFolderSidebarBadgeSnapshot,
        mixedCountsByDefaultKey: [String: SmartFolderMixedCounts]
    ) -> some View {
        CollapsibleSidebarSection(
            title: L10n.sidebarSmartFoldersSection,
            isCollapsed: $isSmartFoldersCollapsed
        ) {
            let folders = SmartFolderSidebarGrouping.defaultFolders(from: sqliteSidebarState.smartFolderSnapshots)

            if folders.isEmpty {
                Text(L10n.sidebarSmartFoldersEmpty)
                    .font(interfaceTextSize.font(size: 13))
                    .foregroundStyle(SidebarStyle.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                smartFolderRows(folders, badgeSnapshot: badgeSnapshot, mixedCountsByDefaultKey: mixedCountsByDefaultKey)
            }
        }
    }

    private func customSmartFoldersSection(
        badgeSnapshot: SmartFolderSidebarBadgeSnapshot,
        mixedCountsByDefaultKey: [String: SmartFolderMixedCounts]
    ) -> some View {
        CollapsibleSidebarSection(
            title: L10n.sidebarSmartFoldersCustomSection,
            isCollapsed: $isCustomSmartFoldersCollapsed,
            actionSystemImage: "plus",
            actionHelp: String(localized: "sidebar.smartFolder.create")
        ) {
            isCreatingSmartFolder = true
        } content: {
            let folders = SmartFolderSidebarGrouping.customFolders(from: sqliteSidebarState.smartFolderSnapshots)

            if folders.isEmpty {
                Text(L10n.sidebarSmartFoldersCustomEmpty)
                    .font(interfaceTextSize.font(size: 13))
                    .foregroundStyle(SidebarStyle.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                smartFolderRows(folders, badgeSnapshot: badgeSnapshot, mixedCountsByDefaultKey: mixedCountsByDefaultKey)
            }
        }
    }

    @ViewBuilder
    private func smartFolderRows(
        _ folders: [SQLiteSmartFolderSnapshot],
        badgeSnapshot: SmartFolderSidebarBadgeSnapshot,
        mixedCountsByDefaultKey: [String: SmartFolderMixedCounts]
    ) -> some View {
        ForEach(folders) { smartFolder in
            Button {
                selection = .smartFolder(smartFolder.id)
            } label: {
                SmartFolderSidebarRow(
                    smartFolder: smartFolder,
                    badgeSnapshot: badgeSnapshot,
                    mixedCounts: smartFolder.defaultKey.flatMap { mixedCountsByDefaultKey[$0] }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(
                SidebarRowButtonStyle(
                    isSelected: selection == .smartFolder(smartFolder.id),
                    leadingIndent: 6,
                    rowHeight: 30
                )
            )
            .contextMenu {
                Button {
                    smartFolderEditing = sqliteSmartFolderRecord(id: smartFolder.id)
                } label: {
                    Label(L10n.ruleEditButton, systemImage: "pencil")
                }

                Button {
                    duplicateSmartFolder(smartFolder)
                } label: {
                    Label(L10n.commonDuplicate, systemImage: "plus.square.on.square")
                }

                Divider()

                Button(role: .destructive) {
                    smartFolderPendingDeletion = smartFolder
                } label: {
                    Label(L10n.ruleDeleteButton, systemImage: "trash")
                }
            }
        }
    }

    private func defaultSmartFolderSelection(excluding deletedFolder: SQLiteSmartFolderSnapshot? = nil) -> SidebarSelection? {
        sqliteSidebarState.smartFolderSnapshots
            .first { folder in
                deletedFolder?.id != folder.id
            }
            .map { folder in
                .smartFolder(folder.id)
            }
    }

    private func feedRows(_ snapshots: [FeedSidebarSnapshot], isIndented: Bool = false) -> some View {
        ForEach(snapshots) { snapshot in
            Button {
                selection = .feed(snapshot.id)
            } label: {
                FeedRowView(
                    snapshot: snapshot,
                    displayStyle: isIndented ? .folderChild : .regular
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(
                SidebarRowButtonStyle(
                    isSelected: selection == .feed(snapshot.id),
                    leadingIndent: isIndented ? 46 : 0,
                    rowHeight: isIndented ? 28 : 30
                )
            )
            .contextMenu {
                Button {
                    feedRenaming = snapshot
                } label: {
                    Label(L10n.feedRenameCommand, systemImage: "pencil")
                }

                Button {
                    feedShowingProperties = snapshot
                } label: {
                    Label(L10n.feedPropertiesCommand, systemImage: "info.circle")
                }

                Divider()

                Button(role: .destructive) {
                    onRequestDeleteFeed(snapshot.id)
                } label: {
                    Label(L10n.feedDeleteCommand, systemImage: "trash")
                }
            }
        }
    }

    private func tagRows(_ tags: [TagSidebarSnapshot]) -> some View {
        ForEach(tags) { tag in
            Button {
                selection = .tag(tag.id)
            } label: {
                TagSidebarRow(
                    tag: tag,
                    badgeText: SidebarUnreadCount.badgeText(for: tag.articleCount)
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(
                SidebarRowButtonStyle(
                    isSelected: selection == .tag(tag.id),
                    leadingIndent: 6,
                    rowHeight: 30
                )
            )
        }
    }

    private func toggleFolder(named folderName: String) {
        withAnimation(.easeInOut(duration: 0.16)) {
            if collapsedFolderNames.contains(folderName) {
                collapsedFolderNames.remove(folderName)
            } else {
                collapsedFolderNames.insert(folderName)
            }
        }
    }

    private func duplicateSmartFolder(_ smartFolder: SQLiteSmartFolderSnapshot) {
        guard let database = feedivoDatabase else {
            return
        }

        _ = try? SQLiteSmartFolderStore(database: database).duplicate(
            id: smartFolder.id,
            copyName: "\(smartFolder.name) Kopie"
        )
        SQLiteDataInvalidation.bumpStatusVersion()
        sidebarDefinitionVersion += 1
    }

    private func deleteSmartFolder(_ smartFolder: SQLiteSmartFolderSnapshot) {
        guard let database = feedivoDatabase else {
            return
        }

        try? SQLiteSmartFolderStore(database: database).delete(id: smartFolder.id)
        SQLiteDataInvalidation.bumpStatusVersion()
        sidebarDefinitionVersion += 1
    }

    private func explicitFeedFolder(named folderName: String) -> FeedFolderRecord? {
        sqliteSidebarState.feedFolders.first { folder in
            folder.name.caseInsensitiveCompare(folderName) == .orderedSame
        }
    }

    private func deleteFeedFolder(_ folder: FeedFolderRecord) {
        guard let database = feedivoDatabase else {
            return
        }

        try? FeedFolderStore(database: database).delete(id: folder.id)
        collapsedFolderNames.remove(folder.name)
        SQLiteDataInvalidation.bumpStatusVersion()
        sidebarDefinitionVersion += 1
    }

    private func renameFolder(from oldName: String, to newName: String) throws {
        guard let database = feedivoDatabase else {
            throw FeedFolderRenameError.databaseUnavailable
        }

        try FeedFolderStore(database: database).renameFolder(from: oldName, to: newName)

        // Ein-/Ausklapp-Zustand ist über collapsedFolderNames am alten Namen
        // festgemacht — beim Umbenennen migrieren, damit ein zuvor eingeklappter
        // Ordner nach der Umbenennung nicht überraschend wieder aufklappt.
        if collapsedFolderNames.remove(oldName) != nil {
            collapsedFolderNames.insert(newName)
        }

        SQLiteDataInvalidation.bumpStatusVersion()
        sidebarDefinitionVersion += 1
    }

    private func sqliteSmartFolderRecord(id: String) -> SmartFolderRecord? {
        guard let database = feedivoDatabase else {
            return nil
        }

        return try? SQLiteSmartFolderStore(database: database).folder(id: id)
    }

    private func sqliteSmartFolderRecords() -> [SmartFolderRecord] {
        guard let database = feedivoDatabase else {
            return []
        }

        return (try? SQLiteSmartFolderStore(database: database).folders()) ?? []
    }

    private var sqliteSidebarReloadToken: String {
        // Feed-Anzahl als Strukturtrigger reicht; inhaltliche Änderungen
        // (Unread-Counts, Titel) werden über sqliteStatusVersion erfasst. Die
        // SQLite-Feed-IDs stehen vor dem ersten Laden noch nicht zur Verfügung,
        // deshalb wird hier nicht auf Snapshots zurückgegriffen.
        return "\(sqliteStatusVersion)#\(directTagVersion)#\(showsReadFeedsInSidebar)#\(sidebarDefinitionVersion)#\(sqliteSidebarState.snapshots.count)"
    }
}

private struct SmartFolderSidebarRow: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let smartFolder: SQLiteSmartFolderSnapshot
    let badgeSnapshot: SmartFolderSidebarBadgeSnapshot
    let mixedCounts: SmartFolderMixedCounts?

    // Badge bewusst aus dem SQLite-Snapshot berechnen: Die Sidebar muss dafür
    // keine Artikel-Query beobachten.
    private var badgeText: String? {
        SmartFolderSidebarBadge.badgeText(for: smartFolder, snapshot: badgeSnapshot)
    }

    private var isUnreadBadge: Bool {
        SmartFolderSidebarBadgeKind(folder: smartFolder) == .unread
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: smartFolder.iconName ?? SmartFolderAppearance.defaultIconName)
                .font(interfaceTextSize.font(size: 14, weight: .semibold))
                .foregroundStyle(TagColorPalette.color(for: smartFolder.colorHex ?? SmartFolderAppearance.defaultColorHex).opacity(SidebarStyle.iconOpacity))
                .frame(width: interfaceTextSize.scaled(20))

            Text(smartFolder.name)
                .font(interfaceTextSize.font(size: 13, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let mixedCounts {
                if mixedCounts.read > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "circle")
                            .font(.system(size: 8, weight: .semibold))
                        Text("\(mixedCounts.read)")
                            .font(interfaceTextSize.font(size: 11, weight: .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.gray)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(SidebarStyle.activeSelectionOpacity), in: Capsule())
                }

                if mixedCounts.unread > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8, weight: .semibold))
                        Text("\(mixedCounts.unread)")
                            .font(interfaceTextSize.font(size: 11, weight: .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(SidebarStyle.activeSelection, in: Capsule())
                }
            } else if let badgeText {
                HStack(spacing: 3) {
                    if isUnreadBadge {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    Text(badgeText)
                        .font(interfaceTextSize.font(size: 11, weight: .semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(isUnreadBadge ? Color.accentColor : SidebarStyle.secondaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(SidebarStyle.activeSelection, in: Capsule())
            }
        }
    }
}

private struct TagSidebarRow: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let tag: TagSidebarSnapshot
    let badgeText: String?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(TagColorPalette.color(for: tag.colorHex))
                .frame(
                    width: interfaceTextSize.scaled(9),
                    height: interfaceTextSize.scaled(9)
                )
                .frame(width: interfaceTextSize.scaled(20))

            Text(tag.name)
                .font(interfaceTextSize.font(size: 13, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let badgeText {
                Text(badgeText)
                    .font(interfaceTextSize.font(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(SidebarStyle.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(SidebarStyle.activeSelection, in: Capsule())
            }
        }
    }
}

private struct CollapsibleSidebarSection<Content: View>: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let title: LocalizedStringKey
    @Binding var isCollapsed: Bool
    var actionSystemImage: String?
    var actionHelp: String?
    var isActionDisabled = false
    var action: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isCollapsed.toggle()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(interfaceTextSize.font(size: 10, weight: .bold))
                            .frame(width: interfaceTextSize.scaled(12))

                        Text(title)
                            .font(interfaceTextSize.font(size: 11, weight: .bold))
                            .fontWeight(.bold)
                            .textCase(.uppercase)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if let actionSystemImage, let action {
                    Button(action: action) {
                        Image(systemName: actionSystemImage)
                            .font(interfaceTextSize.font(size: 12, weight: .bold))
                            .frame(
                                width: interfaceTextSize.scaled(22),
                                height: interfaceTextSize.scaled(22)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(actionHelp ?? "")
                    .disabled(isActionDisabled)
                }
            }
            .foregroundStyle(SidebarStyle.sectionText)
            .padding(.horizontal, 10)

            if !isCollapsed {
                content
            }
        }
    }
}

private struct SidebarFolderSection<Content: View>: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize
    @FocusState private var isNameFieldFocused: Bool

    let title: String
    let isExpanded: Bool
    let deleteEmptyFolder: (() -> Void)?
    let renameFolder: (String) throws -> Void
    let toggle: () -> Void
    @ViewBuilder let content: Content

    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var renameErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Button(action: toggle) {
                    HStack(spacing: 9) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(interfaceTextSize.font(size: 10, weight: .bold))
                            .foregroundStyle(SidebarStyle.secondaryText)
                            .frame(width: interfaceTextSize.scaled(12))

                        Image(systemName: "folder")
                            .font(interfaceTextSize.font(size: 16, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: interfaceTextSize.scaled(20))
                    }
                }
                .buttonStyle(.plain)

                if isEditingName {
                    TextField(title, text: $editedName)
                        .textFieldStyle(.plain)
                        .font(interfaceTextSize.font(size: 13, weight: .medium))
                        .focused($isNameFieldFocused)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(renameErrorMessage != nil ? Color.red : Color.clear, lineWidth: 1)
                        }
                        .onSubmit {
                            commitOrShowError()
                        }
                        .onExitCommand {
                            cancelEditing()
                        }
                        .onChange(of: isNameFieldFocused) { wasFocused, isFocused in
                            // Fokusverlust (z. B. Klick woanders hin) verhält sich wie
                            // Enter. Die Guard-Bedingung verhindert ein doppeltes
                            // Auslösen, wenn commitOrShowError()/cancelEditing() den
                            // Bearbeitungsmodus bereits beendet haben, bevor der Fokus
                            // tatsächlich wechselt.
                            if wasFocused, !isFocused, isEditingName {
                                commitOrShowError()
                            }
                        }
                } else {
                    Text(title)
                        .font(interfaceTextSize.font(size: 13, weight: .medium))
                        .foregroundStyle(SidebarStyle.primaryText.opacity(0.82))
                        .lineLimit(1)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            beginEditing()
                        }
                        .onTapGesture(count: 1) {
                            toggle()
                        }
                }

                Spacer(minLength: 0)
            }
            .frame(height: interfaceTextSize.scaled(24))
            .contentShape(Rectangle())
            .onTapGesture {
                // Fängt Klicks auf den leeren Bereich rechts vom Namen ab, damit die
                // gesamte Zeile weiterhin wie vor dieser Änderung klickbar bleibt.
                // Klicks auf Chevron/Icon (eigener Button) und auf den Namen (eigene
                // Tap-Gesten oben) werden von SwiftUI vorrangig an die jeweils
                // spezifischere View vergeben und lösen diesen Handler nicht zusätzlich aus.
                // Während der Bearbeitung (isEditingName) ist dieser Handler bewusst ein
                // No-op, damit ein Klick ins TextField (Fokussieren/Cursor positionieren)
                // nicht stattdessen den Ordner ein-/ausklappt.
                if !isEditingName {
                    toggle()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .contextMenu {
                Button {
                    beginEditing()
                } label: {
                    Label(L10n.sidebarFolderRenameCommand, systemImage: "pencil")
                }

                if let deleteEmptyFolder {
                    Button(role: .destructive) {
                        deleteEmptyFolder()
                    } label: {
                        Label(L10n.commonDelete, systemImage: "trash")
                    }
                }
            }

            if let renameErrorMessage {
                Text(renameErrorMessage)
                    .font(interfaceTextSize.font(size: 11))
                    .foregroundStyle(.red)
                    .padding(.leading, 16 + 12 + 9 + 20 + 9)
                    .padding(.trailing, 16)
            }

            content
        }
    }

    private func beginEditing() {
        editedName = title
        renameErrorMessage = nil
        isEditingName = true
        isNameFieldFocused = true
    }

    private func cancelEditing() {
        editedName = title
        renameErrorMessage = nil
        isEditingName = false
    }

    private func commitOrShowError() {
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedName != title else {
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

private struct SidebarRowButtonStyle: ButtonStyle {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let isSelected: Bool
    var leadingIndent: CGFloat = 0
    var rowHeight: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(interfaceTextSize.font(size: 13, weight: .semibold))
            .fontWeight(.semibold)
            .foregroundStyle(
                isSelected ? SidebarStyle.primaryText : SidebarStyle.primaryText.opacity(0.82)
            )
            .padding(.horizontal, 10)
            .frame(height: interfaceTextSize.scaled(rowHeight))
            .padding(.leading, leadingIndent)
            .background(rowBackground(configuration: configuration))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func rowBackground(configuration: Configuration) -> some View {
        let backgroundColor: Color = if isSelected {
            SidebarStyle.activeSelection
        } else if configuration.isPressed {
            SidebarStyle.rowHover
        } else {
            Color.clear
        }

        RoundedRectangle(cornerRadius: 8)
            .fill(backgroundColor)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? SidebarStyle.activeBorder : Color.clear,
                        lineWidth: 1
                    )
            }
    }
}

struct AddFeedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.feedivoDatabase) private var feedivoDatabase

    // Datum-Format der Feed-Vorschau folgt derselben Nutzereinstellung wie Artikelliste/
    // Sidebar/Reader-Inspector (Feature 19.1) — keine anderen @AppStorage-Properties in
    // diesem Struct vorhanden, daher direkt nach den @Environment-Properties platziert.
    @AppStorage(ArticleDateDisplayMode.storageKey)
    private var dateDisplayModeRawValue = ArticleDateDisplayMode.defaultMode.rawValue

    @State private var viewModel = FeedViewModel()
    @State private var urlString: String
    @State private var discoveryResults: [FeedDiscoveryResult] = []
    @State private var selectedFeedURL: String?
    @State private var discoveryErrorMessage: String?
    @State private var isDiscovering = false
    @State private var selectedFolderName: String?
    @State private var isCreatingNewFolder = false
    @State private var newFolderName = ""
    @State private var availableFolderNames: [String] = []
    private let discoveryService = FeedDiscoveryService()

    // Aktiviert von einem feedivo://add?url=...-Deep-Link (Feature 23.2):
    // startet die Vorschau automatisch, ohne dass der Nutzer erneut auf
    // "Suchen" klicken muss. Beim normalen, manuellen Öffnen (Sidebar-Button)
    // bleibt der Ablauf unverändert (false).
    private let shouldAutoStartDiscovery: Bool

    init(initialURLString: String? = nil) {
        self._urlString = State(initialValue: initialURLString ?? "")
        self.shouldAutoStartDiscovery = !(initialURLString ?? "").isEmpty
    }

    // Sentinel-Tag fuer die "Neuer Ordner..."-Menueauswahl. Ein Zeichen, das in
    // normalisierten Ordnernamen nicht vorkommen kann, vermeidet Kollisionen.
    private static let newFolderSentinel = "\u{0}__new_folder__"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.sidebarAddFeedTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Text(L10n.sidebarAddFeedDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(L10n.sidebarAddFeedURLPlaceholder, text: $urlString)
                .textFieldStyle(.roundedBorder)
                .disabled(isBusy)

            if !discoveryResults.isEmpty {
                discoveryResultList
            }

            if let selectedFeedPreview {
                feedPreview(for: selectedFeedPreview)
            }

            if selectedFeedURL != nil {
                folderSelectionRow
            }

            if let errorMessage = discoveryErrorMessage ?? viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Spacer()

                Button(L10n.commonCancel) {
                    dismiss()
                }
                .disabled(isBusy)

                Button {
                    Task {
                        await performPrimaryAction()
                    }
                } label: {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(primaryButtonTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onChange(of: urlString) {
            resetDiscovery()
        }
        .onAppear {
            loadAvailableFolderNames()

            if shouldAutoStartDiscovery {
                Task {
                    await performPrimaryAction()
                }
            }
        }
    }

    private var folderSelectionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(L10n.feedPropertiesFolder)
                    .frame(width: 80, alignment: .leading)

                Picker(L10n.feedPropertiesFolder, selection: folderPickerSelection) {
                    Text(L10n.feedPropertiesNoFolder).tag(String?.none)

                    ForEach(availableFolderNames, id: \.self) { name in
                        Text(name).tag(String?.some(name))
                    }

                    Divider()

                    Text(L10n.sidebarAddFeedNewFolder).tag(String?.some(Self.newFolderSentinel))
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Spacer()
            }

            if isCreatingNewFolder {
                TextField(L10n.sidebarAddFeedNewFolder, text: $newFolderName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isBusy)
            }
        }
    }

    // Binding, das die Sentinel-Auswahl in den "Neuer Ordner..."-Modus uebersetzt
    // und sonst den gewaehlten Ordnernamen (bzw. nil) haelt.
    private var folderPickerSelection: Binding<String?> {
        Binding(
            get: {
                isCreatingNewFolder ? Self.newFolderSentinel : selectedFolderName
            },
            set: { newValue in
                if newValue == Self.newFolderSentinel {
                    isCreatingNewFolder = true
                    selectedFolderName = nil
                } else {
                    isCreatingNewFolder = false
                    newFolderName = ""
                    selectedFolderName = newValue
                }
            }
        )
    }

    // Effektiver Ordnername fuer das Abonnieren: im Neu-Modus der getippte Name,
    // sonst der ausgewaehlte. Normalisierung (leer -> nil) uebernimmt der Service.
    private var effectiveFolderName: String? {
        isCreatingNewFolder ? newFolderName : selectedFolderName
    }

    private func loadAvailableFolderNames() {
        guard let feedivoDatabase else {
            return
        }

        do {
            let folders = try FeedFolderStore(database: feedivoDatabase).folders()
            let feeds = try FeedStore(database: feedivoDatabase).feeds()
            availableFolderNames = FeedFolderOrganizer.folderNames(
                feedFolderNames: feeds.map(\.folderName),
                explicitFolderNames: folders.map { $0.name }
            )
        } catch {
            availableFolderNames = []
        }
    }

    private var discoveryResultList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.feedDiscoveryResultsTitle)
                .font(.headline)

            ForEach(discoveryResults) { result in
                Button {
                    selectedFeedURL = result.feedURL
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selectedFeedURL == result.feedURL ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedFeedURL == result.feedURL ? Color.accentColor : Color.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(result.feedURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(10)
                .background(
                    selectedFeedURL == result.feedURL ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
        }
    }

    private var selectedFeedPreview: FeedDiscoveryResult? {
        guard let selectedFeedURL else {
            return nil
        }

        return discoveryResults.first { $0.feedURL == selectedFeedURL }
    }

    private func feedPreview(for result: FeedDiscoveryResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                feedPreviewIcon(urlString: result.faviconURL)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.headline)
                        .lineLimit(1)

                    if let siteURL = result.siteURL {
                        Text(siteURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }

            if result.previewArticles.isEmpty {
                Text(L10n.sidebarFeedPreviewEmpty)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.sidebarFeedPreviewRecent)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(result.previewArticles) { article in
                        feedPreviewArticleRow(article)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func feedPreviewIcon(urlString: String?) -> some View {
        let url = urlString.flatMap(URL.init(string:))

        return CachedRemoteImageView(url: url) { image in
            image
                .resizable()
                .scaledToFit()
        } placeholder: {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 34, height: 34)
        .padding(7)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func feedPreviewArticleRow(_ article: FeedDiscoveryPreviewArticle) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(article.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let publishedAt = article.publishedAt {
                    Text(publishedAt.feedivoDisplay(mode: ArticleDateDisplayMode.resolved(from: dateDisplayModeRawValue)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let summary = article.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
               !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var isBusy: Bool {
        isDiscovering || viewModel.isLoading
    }

    private var primaryButtonTitle: LocalizedStringKey {
        selectedFeedURL == nil ? L10n.feedDiscoverySearchButton : L10n.sidebarSubscribe
    }

    private func performPrimaryAction() async {
        if let selectedFeedURL {
            await addFeed(urlString: selectedFeedURL)
        } else {
            await discoverFeeds()
        }
    }

    private func discoverFeeds() async {
        isDiscovering = true
        discoveryErrorMessage = nil
        viewModel.errorMessage = nil

        do {
            let results = try await discoveryService.discoverFeeds(from: urlString)
            discoveryResults = results
            selectedFeedURL = results.first?.feedURL
        } catch let error as LocalizedError {
            discoveryErrorMessage = error.errorDescription ?? L10n.feedDiscoveryErrorNoFeedsFound
        } catch {
            discoveryErrorMessage = L10n.feedDiscoveryErrorNoFeedsFound
        }

        isDiscovering = false
    }

    private func addFeed(urlString: String) async {
        await viewModel.addFeed(
            urlString: urlString,
            sqliteDatabase: feedivoDatabase,
            folderName: effectiveFolderName
        )
        if viewModel.errorMessage == nil {
            dismiss()
        }
    }

    private func resetDiscovery() {
        discoveryResults = []
        selectedFeedURL = nil
        discoveryErrorMessage = nil
    }
}

struct AddFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.feedivoDatabase) private var feedivoDatabase

    let existingFolderNames: [String]
    let onFolderAdded: () -> Void

    @State private var folderName = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.sidebarAddFolderTitle)
                .font(.title2)
                .fontWeight(.semibold)

            TextField(L10n.sidebarAddFolderNamePlaceholder, text: $folderName)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Spacer()

                Button(L10n.commonCancel) {
                    dismiss()
                }

                Button {
                    addFolder()
                } label: {
                    Text(L10n.commonAdd)
                }
                .buttonStyle(.borderedProminent)
                .disabled(FeedFolderOrganizer.normalizedFolderName(folderName) == nil)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func addFolder() {
        guard let normalizedName = FeedFolderOrganizer.normalizedFolderName(folderName) else {
            return
        }

        let alreadyExists = existingFolderNames.contains {
            $0.caseInsensitiveCompare(normalizedName) == .orderedSame
        }

        guard !alreadyExists else {
            errorMessage = L10n.sidebarAddFolderDuplicateError
            return
        }

        guard let database = feedivoDatabase else {
            errorMessage = L10n.feedPropertiesUnavailable
            return
        }

        do {
            try FeedFolderStore(database: database).save(
                FeedFolderRecord(name: normalizedName)
            )
            onFolderAdded()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
