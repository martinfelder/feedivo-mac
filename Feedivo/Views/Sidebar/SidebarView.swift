import SwiftUI
import OSLog

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
            VStack(alignment: .leading, spacing: 8) {
                sidebarActionRow

                if let errorMessage = sqliteSidebarState.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Bewusst NICHT innerhalb einer SwiftUI-ScrollView — SidebarOutlineView
            // bringt über die NSScrollView in makeNSView() bereits ihr eigenes
            // Scrolling mit. Eine verschachtelte ScrollView würde die
            // NSOutlineView nur auf eine kleine, intern scrollende Box begrenzen
            // statt die gesamte verbleibende Sidebar-Höhe einzunehmen (siehe
            // Whole-Branch-Review-Fix 2).
            SidebarOutlineView(
                rootNodes: SidebarOutlineNode.buildTree(
                    feedSnapshots: sqliteSidebarState.snapshots,
                    feedFolders: sqliteSidebarState.feedFolders,
                    tagSnapshots: sqliteSidebarState.tagSnapshots,
                    smartFolderSnapshots: sqliteSidebarState.smartFolderSnapshots
                ),
                selection: $selection,
                collapsedFolderNames: $collapsedFolderNames,
                isSmartFoldersCollapsed: $isSmartFoldersCollapsed,
                isCustomSmartFoldersCollapsed: $isCustomSmartFoldersCollapsed,
                isTagsCollapsed: $isTagsCollapsed,
                isFoldersCollapsed: $isFoldersCollapsed,
                badgeSnapshot: sqliteSidebarState.smartFolderBadgeSnapshot,
                mixedCountsByDefaultKey: sqliteSidebarState.mixedCountsByDefaultKey,
                renameFeed: { id, newName in try renameFeed(id: id, to: newName) },
                renameFolder: { oldName, newName in try renameFolder(from: oldName, to: newName) },
                onFeedContextAction: { action, snapshot in
                    switch action {
                    case .rename: feedRenaming = snapshot
                    case .showProperties: feedShowingProperties = snapshot
                    case .delete: onRequestDeleteFeed(snapshot.id)
                    }
                },
                onFolderContextAction: { action, name in
                    switch action {
                    case .delete:
                        if let folder = explicitFeedFolder(named: name) {
                            feedFolderPendingDeletion = folder
                        }
                    }
                },
                onSmartFolderContextAction: { action, smartFolder in
                    switch action {
                    case .edit: smartFolderEditing = sqliteSmartFolderRecord(id: smartFolder.id)
                    case .duplicate: duplicateSmartFolder(smartFolder)
                    case .delete: smartFolderPendingDeletion = smartFolder
                    }
                },
                onTagsManageRequested: { isShowingTagManager = true },
                onCreateSmartFolderRequested: { isCreatingSmartFolder = true },
                onSortFoldersAlphabetically: { sortFoldersAlphabetically() },
                moveFeed: { id, folderName, targetIndex in moveFeed(id: id, toFolderName: folderName, targetIndex: targetIndex) },
                moveFolder: { name, targetIndex in moveFolder(name: name, targetIndex: targetIndex) },
                moveTag: { id, targetIndex in moveTag(id: id, targetIndex: targetIndex) },
                moveSmartFolder: { id, targetIndex, isDefault in moveSmartFolder(id: id, targetIndex: targetIndex, isDefault: isDefault) }
            )
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
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

    private func defaultSmartFolderSelection(excluding deletedFolder: SQLiteSmartFolderSnapshot? = nil) -> SidebarSelection? {
        sqliteSidebarState.smartFolderSnapshots
            .first { folder in
                deletedFolder?.id != folder.id
            }
            .map { folder in
                .smartFolder(folder.id)
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

    private func renameFeed(id: String, to newTitle: String) throws {
        guard let database = feedivoDatabase else {
            throw FeedStoreError.databaseUnavailable
        }

        try FeedStore(database: database).renameFeed(id: id, displayTitle: newTitle)
        SQLiteDataInvalidation.bumpStatusVersion()
    }

    private func moveFeed(id: String, toFolderName: String?, targetIndex: Int) {
        guard let database = feedivoDatabase else {
            AppLogger.dataAccess.fault("TEMPDEBUG moveFeed: feedivoDatabase ist nil")
            return
        }

        do {
            try FeedStore(database: database).moveFeed(id: id, toFolderName: toFolderName, targetIndex: targetIndex)
            AppLogger.dataAccess.fault("TEMPDEBUG moveFeed OK id=\(id, privacy: .public) toFolderName=\(toFolderName ?? "nil", privacy: .public) targetIndex=\(targetIndex, privacy: .public)")
        } catch {
            AppLogger.dataAccess.fault("TEMPDEBUG moveFeed FEHLER \(error.localizedDescription, privacy: .public)")
        }
        SQLiteDataInvalidation.bumpStatusVersion()
    }

    private func moveFolder(name: String, targetIndex: Int) {
        guard let database = feedivoDatabase else {
            AppLogger.dataAccess.fault("TEMPDEBUG moveFolder: feedivoDatabase ist nil")
            return
        }

        do {
            try FeedFolderStore(database: database).moveFolder(name: name, targetIndex: targetIndex)
        } catch {
            AppLogger.dataAccess.error("moveFolder fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
        sidebarDefinitionVersion += 1
    }

    private func sortFoldersAlphabetically() {
        guard let database = feedivoDatabase else { return }

        do {
            try FeedFolderStore(database: database).sortAlphabetically()
        } catch {
            AppLogger.dataAccess.error("sortFoldersAlphabetically fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
        sidebarDefinitionVersion += 1
    }

    private func moveTag(id: String, targetIndex: Int) {
        guard let database = feedivoDatabase else { return }
        try? TagStore(database: database).move(id: id, targetIndex: targetIndex)
        SQLiteDataInvalidation.bumpStatusVersion()
    }

    private func moveSmartFolder(id: String, targetIndex: Int, isDefault: Bool) {
        guard let database = feedivoDatabase else { return }

        do {
            let folders = isDefault
                ? SmartFolderSidebarGrouping.defaultFolders(from: sqliteSidebarState.smartFolderSnapshots)
                : SmartFolderSidebarGrouping.customFolders(from: sqliteSidebarState.smartFolderSnapshots)
            let clampedIndex = min(max(targetIndex, 0), max(folders.count - 1, 0))
            guard clampedIndex >= 0, clampedIndex < folders.count else { return }
            let targetFolder = folders[clampedIndex]
            guard targetFolder.id != id else { return }
            try SQLiteSmartFolderStore(database: database).move(id: id, toPositionOf: targetFolder.id)
        } catch {
            AppLogger.dataAccess.error("moveSmartFolder fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
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

struct SmartFolderSidebarRow: View {
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

struct TagSidebarRow: View {
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

struct SidebarRowButtonStyle: ButtonStyle {
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
