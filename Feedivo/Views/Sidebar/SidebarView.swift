import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query(sort: \FeedFolder.name) private var folders: [FeedFolder]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(sort: \SmartFolder.sortOrder) private var smartFolders: [SmartFolder]
    // Nur Artikel, die für Status-Badges relevant sind. Eine globale Artikel-
    // Query in der Sidebar hat beim Lesen jeden isRead-Wechsel beobachtet und
    // dadurch SwiftData/CoreData-Faulting auf dem Main-Thread ausgelöst.
    @Query private var statusBadgeArticles: [Article]
    @Binding var selection: SidebarSelection?
    let onRequestAddFeed: () -> Void
    let onRequestRefreshAllFeeds: () -> Void
    let onRequestDeleteFeed: (Feed) -> Void
    // Bump bei direkter Artikel→Tag-Zuweisung (siehe SidebarBadgeInvalidation).
    // Status-Toggles, Artikel-Zahl und Feed/Tag-Struktur werden automatisch über
    // die Signatur bzw. die beobachteten @Querys erfasst.
    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey)
    private var directTagVersion = 0
    @AppStorage(SQLiteDataInvalidation.statusVersionKey)
    private var sqliteStatusVersion = 0
    // Cache für Tag-Badge-Zähler: nur bei Tag-relevanter Signaturänderung neu
    // berechnet. Statusänderungen wie Stern/Archiv aktualisieren nur die
    // günstigen Status-Badges und faulten keine Artikel→Tag-Relationships.
    @State private var cachedTagCounts: [PersistentIdentifier: Int]?
    @State private var cachedTagSignature: SidebarTagBadgeSignature?

    init(
        selection: Binding<SidebarSelection?>,
        onRequestAddFeed: @escaping () -> Void,
        onRequestRefreshAllFeeds: @escaping () -> Void,
        onRequestDeleteFeed: @escaping (Feed) -> Void
    ) {
        self._selection = selection
        self.onRequestAddFeed = onRequestAddFeed
        self.onRequestRefreshAllFeeds = onRequestRefreshAllFeeds
        self.onRequestDeleteFeed = onRequestDeleteFeed

        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.isStarred || article.isArchived || article.isHidden
            }
        )
        descriptor.propertiesToFetch = [
            \.id, \.isStarred, \.isArchived, \.isHidden
        ]
        _statusBadgeArticles = Query(descriptor)
    }
    @AppStorage(SidebarSectionCollapseState.Section.tags.storageKey)
    private var isTagsCollapsed = false
    @AppStorage(SidebarSectionCollapseState.Section.folders.storageKey)
    private var isFoldersCollapsed = false
    @AppStorage(SidebarSectionCollapseState.Section.smartFolders.storageKey)
    private var isSmartFoldersCollapsed = false
    @AppStorage(SidebarFeedVisibilitySettings.showsReadFeedsKey)
    private var showsReadFeedsInSidebar = SidebarFeedVisibilitySettings.defaultShowsReadFeeds
    @State private var feedShowingProperties: Feed?
    @State private var feedRenaming: Feed?
    @State private var isShowingAddFolderSheet = false
    @State private var isShowingTagManager = false
    @State private var smartFolderEditing: SmartFolder?
    @State private var smartFolderPendingDeletion: SmartFolder?
    @State private var isCreatingSmartFolder = false
    @State private var smartFolderViewModel = SmartFolderViewModel()
    @State private var sqliteSidebarState = SQLiteSidebarState()
    @State private var collapsedFolderNames: Set<String> = []

    var body: some View {
        let statusSignature = sidebarStatusBadgeSignature
        let tagSignature = sidebarTagBadgeSignature
        let badgeCounts = badgeCounts(
            statusSignature: statusSignature,
            tagSignature: tagSignature
        )

        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    smartFoldersSection(badgeCounts: badgeCounts)
                    tagsSection(badgeCounts: badgeCounts)
                    foldersSection
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .scrollContentBackground(.hidden)
        }
        .background(SidebarStyle.background)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    onRequestRefreshAllFeeds()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(feeds.isEmpty)
                .help(L10n.feedRefreshAllCommand)

                createSidebarItemMenu
            }
        }
        .sheet(item: $feedShowingProperties) { feed in
            FeedPropertiesView(feed: feed)
        }
        .sheet(item: $feedRenaming) { feed in
            FeedRenameView(feed: feed)
        }
        .sheet(isPresented: $isShowingAddFolderSheet) {
            AddFolderSheet(
                existingFolderNames: FeedFolderOrganizer.folderNames(
                    in: feeds,
                    folders: folders
                )
            )
        }
        .sheet(isPresented: $isShowingTagManager) {
            TagManagerView { tag in
                selection = .tag(tag.persistentModelID)
            }
        }
        .sheet(isPresented: $isCreatingSmartFolder) {
            SmartFolderEditorView(existingFolders: smartFolders)
        }
        .sheet(item: $smartFolderEditing) { smartFolder in
            SmartFolderEditorView(folder: smartFolder, existingFolders: smartFolders)
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
                smartFolderViewModel.deleteFolder(smartFolder, context: modelContext)
                if selection == .smartFolder(smartFolder.persistentModelID) {
                    selection = defaultSmartFolderSelection(excluding: smartFolder)
                }
                smartFolderPendingDeletion = nil
            }
            Button(L10n.commonCancel, role: .cancel) {
                smartFolderPendingDeletion = nil
            }
        }
        .task(id: tagSignature) {
            // Cache asynchron befüllen, nachdem der Body mit der neuen Tag-
            // Signatur gerendert wurde. Reine Status- oder Selektionswechsel
            // starten diese Task nicht neu → keine Artikel-/Tag-Faults im
            // schnellen Lesepfad.
            cachedTagCounts = computeSidebarTagCounts()
            cachedTagSignature = tagSignature
        }
        .task(id: sqliteSidebarReloadToken) {
            sqliteSidebarState.load(database: feedivoDatabase, showsReadFeeds: showsReadFeedsInSidebar)
        }
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

    private func tagsSection(badgeCounts: SidebarBadgeCounts) -> some View {
        CollapsibleSidebarSection(
            title: L10n.sidebarTagsSection,
            isCollapsed: $isTagsCollapsed,
            actionSystemImage: "tag",
            actionHelp: String(localized: "tagManager.manage.button")
        ) {
            isShowingTagManager = true
        } content: {
            if !tags.isEmpty {
                tagRows(tags, badgeCounts: badgeCounts)
            }
        }
    }

    private var foldersSection: some View {
        CollapsibleSidebarSection(
            title: L10n.sidebarFoldersSection,
            isCollapsed: $isFoldersCollapsed
        ) {
            let visibleFeeds = sqliteSidebarState.visibleFeeds(
                from: feeds,
                showsReadFeeds: showsReadFeedsInSidebar
            )

            if visibleFeeds.isEmpty && folders.isEmpty {
                Text(L10n.sidebarEmptyTitle)
                    .font(interfaceTextSize.font(size: 13))
                    .foregroundStyle(SidebarStyle.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                let feedsWithoutFolder = FeedFolderOrganizer.feedsWithoutFolder(from: visibleFeeds)
                if !feedsWithoutFolder.isEmpty {
                    feedRows(feedsWithoutFolder)
                }

                // M9: Feeds einmal pro Ordner gruppieren statt pro Ordnername
                // neu zu filtern (O(Folders·F) → O(F)).
                ForEach(FeedFolderOrganizer.feedsByFolderName(in: visibleFeeds, folders: folders), id: \.folderName) { entry in
                    let isExpanded = !collapsedFolderNames.contains(entry.folderName)
                    SidebarFolderSection(
                        title: entry.folderName,
                        isExpanded: isExpanded
                    ) {
                        toggleFolder(named: entry.folderName)
                    } content: {
                        if isExpanded {
                            feedRows(
                                entry.feeds,
                                isIndented: true
                            )
                        }
                    }
                }
            }
        }
    }

    private func smartFoldersSection(badgeCounts: SidebarBadgeCounts) -> some View {
        CollapsibleSidebarSection(
            title: L10n.sidebarSmartFoldersSection,
            isCollapsed: $isSmartFoldersCollapsed,
            actionSystemImage: "plus",
            actionHelp: String(localized: "sidebar.smartFolder.create")
        ) {
            isCreatingSmartFolder = true
        } content: {
            let visibleSmartFolders = SmartFolderViewModel.sortedFolders(smartFolders)
                .filter(\.isShownInSidebar)

            if visibleSmartFolders.isEmpty {
                Text(L10n.sidebarSmartFoldersEmpty)
                    .font(interfaceTextSize.font(size: 13))
                    .foregroundStyle(SidebarStyle.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                ForEach(visibleSmartFolders) { smartFolder in
                    Button {
                        selection = .smartFolder(smartFolder.persistentModelID)
                    } label: {
                        SmartFolderSidebarRow(
                            smartFolder: smartFolder,
                            feeds: feeds,
                            counts: badgeCounts
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(
                        SidebarRowButtonStyle(
                            isSelected: selection == .smartFolder(smartFolder.persistentModelID)
                        )
                    )
                    .contextMenu {
                        Button {
                            smartFolderEditing = smartFolder
                        } label: {
                            Label(L10n.ruleEditButton, systemImage: "pencil")
                        }

                        Button {
                            smartFolderViewModel.duplicateFolder(
                                smartFolder,
                                existingFolders: smartFolders,
                                context: modelContext
                            )
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
        }
    }

    private func defaultSmartFolderSelection(excluding deletedFolder: SmartFolder? = nil) -> SidebarSelection? {
        SmartFolderViewModel.sortedFolders(smartFolders)
            .filter(\.isShownInSidebar)
            .first { folder in
                deletedFolder?.persistentModelID != folder.persistentModelID
            }
            .map { folder in
                .smartFolder(folder.persistentModelID)
            }
    }

    private func feedRows(_ feeds: [Feed], isIndented: Bool = false) -> some View {
        ForEach(feeds) { feed in
            Button {
                selection = .feed(feed.persistentModelID)
            } label: {
                FeedRowView(
                    feed: feed,
                    sqliteSnapshot: sqliteSidebarState.snapshot(for: feed),
                    displayStyle: isIndented ? .folderChild : .regular
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(
                SidebarRowButtonStyle(
                    isSelected: selection == .feed(feed.persistentModelID),
                    leadingIndent: isIndented ? 34 : 0,
                    rowHeight: isIndented ? 28 : 30
                )
            )
            .contextMenu {
                Button {
                    feedRenaming = feed
                } label: {
                    Label(L10n.feedRenameCommand, systemImage: "pencil")
                }

                Button {
                    feedShowingProperties = feed
                } label: {
                    Label(L10n.feedPropertiesCommand, systemImage: "info.circle")
                }

                Divider()

                Button(role: .destructive) {
                    onRequestDeleteFeed(feed)
                } label: {
                    Label(L10n.feedDeleteCommand, systemImage: "trash")
                }
            }
        }
    }

    private func tagRows(_ tags: [Tag], badgeCounts: SidebarBadgeCounts) -> some View {
        ForEach(tags) { tag in
            Button {
                selection = .tag(tag.persistentModelID)
            } label: {
                TagSidebarRow(
                    tag: tag,
                    badgeText: SidebarUnreadCount.badgeText(
                        for: badgeCounts.tagCounts[tag.persistentModelID] ?? 0
                    )
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(
                SidebarRowButtonStyle(
                    isSelected: selection == .tag(tag.persistentModelID)
                )
            )
        }
    }

    /// Status-Signatur läuft pro Body-Eval über Skalar-Attribute. Sie ist billig
    /// und hält Stern/Versteckt/Gespeichert-Badges ohne Relationship-Faulting
    /// aktuell.
    private var sidebarStatusBadgeSignature: SidebarStatusBadgeSignature {
        SidebarBadgeSignatureBuilder.statusSignature(articles: statusBadgeArticles)
    }

    /// Tag-Signatur trennt Tag-relevante Änderungen von reinen Statuswechseln.
    /// Dadurch bleibt der Relationship-heavy Tag-Count-Cache bei Stern/Archiv-
    /// Klicks stabil.
    private var sidebarTagBadgeSignature: SidebarTagBadgeSignature {
        SidebarBadgeSignatureBuilder.tagSignature(
            feeds: feeds,
            tags: tags,
            directTagVersion: directTagVersion
        )
    }

    /// Liefert die Badge-Zähler — Tag-Zähler aus dem Cache wenn die Tag-Signatur
    /// trifft, Status-Zähler direkt aus der leichten Status-Signatur.
    private func badgeCounts(
        statusSignature: SidebarStatusBadgeSignature,
        tagSignature: SidebarTagBadgeSignature
    ) -> SidebarBadgeCounts {
        let tagCounts: [PersistentIdentifier: Int]
        if cachedTagSignature == tagSignature, let cached = cachedTagCounts {
            tagCounts = cached
        } else {
            tagCounts = cachedTagCounts ?? [:]
        }

        return SidebarBadgeCounts(
            tagCounts: tagCounts,
            starred: statusSignature.starredCount,
            hidden: statusSignature.hiddenCount,
            saved: statusSignature.savedCount
        )
    }

    /// Tag-Badges werden bewusst nachgelagert per fetchCount berechnet. Damit
    /// beobachtet die Sidebar keine globale Artikelliste mehr und ein
    /// Read/Unread-Wechsel im Reader kann keinen Voll-Refetch aller Artikel
    /// anstoßen.
    private func computeSidebarTagCounts() -> [PersistentIdentifier: Int] {
        var tagCounts: [PersistentIdentifier: Int] = [:]
        for tag in tags {
            if let count = try? SidebarTagCount.articleCount(for: tag, context: modelContext),
               count > 0 {
                tagCounts[tag.persistentModelID] = count
            }
        }

        return tagCounts
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

    private var sqliteSidebarReloadToken: String {
        let feedIDs = feeds
            .map { $0.id.uuidString }
            .sorted()
            .joined(separator: ",")
        return "\(sqliteStatusVersion)#\(showsReadFeedsInSidebar)#\(feedIDs)"
    }
}

private struct SmartFolderSidebarRow: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let smartFolder: SmartFolder
    let feeds: [Feed]
    let counts: SidebarBadgeCounts

    // Badge bewusst hier im Body berechnen: für 'Ungelesen' summiert das
    // SmartFolderSidebarBadge die feed.unreadCount — diese Beobachtung lebt
    // nur in dieser Zeile, nicht in der gesamten Sidebar. Status-Badges
    // (Stern/Versteckt/Gespeichert) greifen auf die übergebenen counts zu und
    // beobachten feed.unreadCount nicht.
    private var badgeText: String? {
        SmartFolderSidebarBadge.badgeText(for: smartFolder, feeds: feeds, counts: counts)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: SmartFolderFormatter.systemImage(for: smartFolder))
                .font(interfaceTextSize.font(size: 14, weight: .semibold))
                .foregroundStyle(SmartFolderFormatter.color(for: smartFolder).opacity(SidebarStyle.iconOpacity))
                .frame(width: interfaceTextSize.scaled(20))

            Text(smartFolder.localizedDisplayName)
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

private struct TagSidebarRow: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let tag: Tag
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

    let title: String
    let isExpanded: Bool
    let toggle: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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

                    Text(title)
                        .font(interfaceTextSize.font(size: 13, weight: .medium))
                        .foregroundStyle(SidebarStyle.primaryText.opacity(0.82))
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .frame(height: interfaceTextSize.scaled(24))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 0)
            .padding(.top, 8)

            content
        }
    }
}

private struct SidebarRow: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let title: LocalizedStringKey
    let systemImage: String
    let iconColor: Color
    let isSelected: Bool
    var badgeText: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(interfaceTextSize.font(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor.opacity(SidebarStyle.iconOpacity))
                    .frame(width: interfaceTextSize.scaled(20))

                Text(title)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(SidebarRowButtonStyle(isSelected: isSelected))
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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @State private var viewModel = FeedViewModel()
    @State private var urlString = ""
    @State private var discoveryResults: [FeedDiscoveryResult] = []
    @State private var selectedFeedURL: String?
    @State private var discoveryErrorMessage: String?
    @State private var isDiscovering = false
    private let discoveryService = FeedDiscoveryService()

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
                    Text(publishedAt.feedivoRelativeDisplay)
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
            context: modelContext,
            sqliteDatabase: feedivoDatabase
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
    @Environment(\.modelContext) private var modelContext

    let existingFolderNames: [String]

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

        modelContext.insert(FeedFolder(name: normalizedName))
        try? modelContext.save()
        dismiss()
    }
}
