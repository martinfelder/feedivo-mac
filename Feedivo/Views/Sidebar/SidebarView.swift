import SwiftData
import SwiftUI

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.feedivoDatabase) private var feedivoDatabase
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    @Query(sort: \Feed.title) private var feeds: [Feed]
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
    @State private var smartFolderEditing: SQLiteSmartFolderSnapshot?
    @State private var smartFolderPendingDeletion: SQLiteSmartFolderSnapshot?
    @State private var isCreatingSmartFolder = false
    @State private var smartFolderViewModel = SmartFolderViewModel()
    @State private var sqliteSidebarState = SQLiteSidebarState()
    @State private var collapsedFolderNames: Set<String> = []
    @State private var sidebarDefinitionVersion = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    smartFoldersSection(badgeSnapshot: sqliteSidebarState.smartFolderBadgeSnapshot)
                    tagsSection
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
                    feedFolderNames: feeds.map(\.folderName),
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
            SmartFolderEditorView(existingFolders: [])
        }
        .sheet(item: $smartFolderEditing) { smartFolder in
            Text(smartFolder.name)
                .padding()
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
            let visibleFeeds = sqliteSidebarState.visibleFeeds(
                from: feeds,
                showsReadFeeds: showsReadFeedsInSidebar
            )

            if visibleFeeds.isEmpty && sqliteSidebarState.feedFolders.isEmpty {
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
                ForEach(feedsByFolderName(in: visibleFeeds), id: \.folderName) { entry in
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

    private func smartFoldersSection(badgeSnapshot: SmartFolderSidebarBadgeSnapshot) -> some View {
        CollapsibleSidebarSection(
            title: L10n.sidebarSmartFoldersSection,
            isCollapsed: $isSmartFoldersCollapsed,
            actionSystemImage: "plus",
            actionHelp: String(localized: "sidebar.smartFolder.create")
        ) {
            isCreatingSmartFolder = true
        } content: {
            let visibleSmartFolders = sqliteSidebarState.smartFolderSnapshots

            if visibleSmartFolders.isEmpty {
                Text(L10n.sidebarSmartFoldersEmpty)
                    .font(interfaceTextSize.font(size: 13))
                    .foregroundStyle(SidebarStyle.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                ForEach(visibleSmartFolders) { smartFolder in
                    Button {
                        selection = .smartFolder(smartFolder.id)
                    } label: {
                        SmartFolderSidebarRow(
                            smartFolder: smartFolder,
                            badgeSnapshot: badgeSnapshot
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(
                        SidebarRowButtonStyle(
                            isSelected: selection == .smartFolder(smartFolder.id)
                        )
                    )
                    .contextMenu {
                        Button {
                            smartFolderEditing = smartFolder
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
                    isSelected: selection == .tag(tag.id)
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

    private func feedsByFolderName(in feeds: [Feed]) -> [(folderName: String, feeds: [Feed])] {
        let orderedFolderNames = FeedFolderOrganizer.folderNames(
            feedFolderNames: feeds.map(\.folderName),
            explicitFolderNames: sqliteSidebarState.feedFolders.map(\.name)
        )
        var feedsByLowercasedName: [String: [Feed]] = [:]

        for feed in feeds {
            guard let normalizedName = FeedFolderOrganizer.normalizedFolderName(feed.folderName) else {
                continue
            }

            feedsByLowercasedName[normalizedName.lowercased(), default: []].append(feed)
        }

        return orderedFolderNames.map { folderName in
            let groupedFeeds = feedsByLowercasedName[folderName.lowercased()] ?? []
            return (
                folderName,
                groupedFeeds.sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            )
        }
    }

    private func duplicateSmartFolder(_ smartFolder: SQLiteSmartFolderSnapshot) {
        guard let database = feedivoDatabase else {
            return
        }

        let existingCount = sqliteSidebarState.smartFolderSnapshots.count
        let duplicatedID = UUID().uuidString
        let conditions = smartFolder.conditions.enumerated().map { index, condition in
            SmartFolderConditionRecord(
                id: UUID().uuidString,
                smartFolderID: duplicatedID,
                field: condition.field.rawValue,
                conditionOperator: condition.conditionOperator.rawValue,
                value: condition.value,
                sortOrder: index
            )
        }

        try? SQLiteSmartFolderStore(database: database).save(
            SmartFolderRecord(
                id: duplicatedID,
                name: "\(smartFolder.name) Kopie",
                matchMode: smartFolder.matchMode.rawValue,
                isShownInSidebar: true,
                isDefault: false,
                sortOrder: existingCount,
                iconName: smartFolder.iconName,
                colorHex: smartFolder.colorHex
            ),
            conditions: conditions
        )
        sidebarDefinitionVersion += 1
    }

    private func deleteSmartFolder(_ smartFolder: SQLiteSmartFolderSnapshot) {
        guard let database = feedivoDatabase else {
            return
        }

        try? SQLiteSmartFolderStore(database: database).delete(id: smartFolder.id)
        sidebarDefinitionVersion += 1
    }

    private var sqliteSidebarReloadToken: String {
        let feedIDs = feeds
            .map { $0.id.uuidString }
            .sorted()
            .joined(separator: ",")
        return "\(sqliteStatusVersion)#\(directTagVersion)#\(showsReadFeedsInSidebar)#\(sidebarDefinitionVersion)#\(feedIDs)"
    }
}

private struct SmartFolderSidebarRow: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let smartFolder: SQLiteSmartFolderSnapshot
    let badgeSnapshot: SmartFolderSidebarBadgeSnapshot

    // Badge bewusst aus dem SQLite-Snapshot berechnen: Die Sidebar muss dafür
    // keine Artikel-Query und keine SwiftData-Relationships beobachten.
    private var badgeText: String? {
        SmartFolderSidebarBadge.badgeText(for: smartFolder, snapshot: badgeSnapshot)
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
