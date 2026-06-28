import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query(sort: \FeedFolder.name) private var folders: [FeedFolder]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(sort: \SmartFolder.sortOrder) private var smartFolders: [SmartFolder]
    // Artikel für die Badge-Zählung. Über einen FetchDescriptor mit
    // propertiesToFetch geladen, sodass nur die Skalar-Attribute resident sind —
    // content/summary/offlineContent-Strings bleiben ungefaultet (Memory bei
    // großem Datenbestand). Die tags-Relationship faultet nur während der
    // (seltenen) Neuberechnung, nicht pro Render.
    @Query private var allArticles: [Article]
    @Binding var selection: SidebarSelection?
    let onRequestAddFeed: () -> Void
    let onRequestDeleteFeed: (Feed) -> Void
    // Bump bei direkter Artikel→Tag-Zuweisung (siehe SidebarBadgeInvalidation).
    // Status-Toggles, Artikel-Zahl und Feed/Tag-Struktur werden automatisch über
    // die Signatur bzw. die beobachteten @Querys erfasst.
    @AppStorage(SidebarBadgeInvalidation.directTagVersionKey)
    private var directTagVersion = 0
    // Cache für die Badge-Zähler: nur bei Signaturänderung neu berechnet.
    // Reiner Selektionswechsel trifft den Cache → kein O(n)-Scan pro Render.
    @State private var cachedBadgeCounts: SidebarBadgeCounts?
    @State private var cachedBadgeSignature: SidebarBadgeSignature?

    init(
        selection: Binding<SidebarSelection?>,
        onRequestAddFeed: @escaping () -> Void,
        onRequestDeleteFeed: @escaping (Feed) -> Void
    ) {
        self._selection = selection
        self.onRequestAddFeed = onRequestAddFeed
        self.onRequestDeleteFeed = onRequestDeleteFeed

        var descriptor = FetchDescriptor<Article>()
        descriptor.propertiesToFetch = [
            \.id, \.feedID, \.isRead, \.isStarred, \.isArchived, \.isHidden
        ]
        _allArticles = Query(descriptor)
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
    @State private var collapsedFolderNames: Set<String> = []

    var body: some View {
        let signature = sidebarBadgeSignature
        let badgeCounts = badgeCounts(for: signature)

        return VStack(spacing: 0) {
            sidebarHeader

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
        .navigationTitle("Feedivo")
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
        .task(id: signature) {
            // Cache asynchron befüllen, nachdem der Body mit der neuen Signatur
            // gerendert wurde. Bei identischer Signatur (z. B. reinem
            // Selektionswechsel) startet die Task nicht neu → keine Neuberechnung.
            cachedBadgeCounts = computeSidebarBadgeCounts()
            cachedBadgeSignature = signature
        }
    }

    private var sidebarHeader: some View {
        HStack {
            Text("Feedivo")
                .font(interfaceTextSize.font(size: 15, weight: .semibold))
                .foregroundStyle(SidebarStyle.primaryText)

            Spacer()

            Button {
                onRequestAddFeed()
            } label: {
                Image(systemName: "plus")
                    .font(interfaceTextSize.font(size: 15, weight: .semibold))
                    .frame(
                        width: interfaceTextSize.scaled(30),
                        height: interfaceTextSize.scaled(30)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(SidebarStyle.primaryText)
            .background(SidebarStyle.activeSelection, in: RoundedRectangle(cornerRadius: 8))
            .help(L10n.sidebarAddFeedButton)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SidebarStyle.separator)
                .frame(height: 1)
        }
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
            isCollapsed: $isFoldersCollapsed,
            actionSystemImage: "plus",
            actionHelp: String(localized: "sidebar.addFolder.button")
        ) {
            isShowingAddFolderSheet = true
        } content: {
            let visibleFeeds = FeedFolderOrganizer.visibleFeeds(
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
                    feed: feed
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(
                SidebarRowButtonStyle(
                    isSelected: selection == .feed(feed.persistentModelID),
                    leadingIndent: isIndented ? 32 : 0
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

    /// Signatur, die alle Badge-relevanten Änderungen erfasst. Läuft pro Body-
    /// Eval als O(n)-Durchlauf über Skalar-Attribute (kein Relationship-Faulting)
    /// — deutlich billiger als die volle Badge-Berechnung. Status-Toggles
    /// (gelesen/Stern/Archiv/versteckt) werden über die Counts automatisch
    /// abgedeckt; direkte Artikel→Tag-Zuweisungen über `directTagVersion`;
    /// Feed/Tag-Struktur über die beobachteten @Querys.
    private var sidebarBadgeSignature: SidebarBadgeSignature {
        var starredCount = 0
        var hiddenCount = 0
        var archivedCount = 0
        for article in allArticles {
            if article.isStarred { starredCount += 1 }
            if article.isHidden { hiddenCount += 1 }
            if article.isArchived { archivedCount += 1 }
        }

        return SidebarBadgeSignature(
            articleCount: allArticles.count,
            starredCount: starredCount,
            hiddenCount: hiddenCount,
            archivedCount: archivedCount,
            tagFeedMembershipHash: tagFeedMembershipHash,
            tagCount: tags.count,
            feedCount: feeds.count,
            directTagVersion: directTagVersion
        )
    }

    /// Hash der Feed→Tag-Zuordnungen. Ändert sich, wenn einem Feed ein Tag
    /// zugewiesen/entfernt wird (über `feed.tags`, beobachtet via @Query feeds).
    private var tagFeedMembershipHash: Int {
        var hash = feeds.count &* 31 &+ tags.count
        for feed in feeds {
            hash = hash &* 31 &+ feed.tags.count
        }
        return hash
    }

    /// Liefert die Badge-Zähler — aus dem Cache wenn die Signatur trifft, sonst
    /// frisch berechnet (und asynchron via .task erneut abgelegt).
    private func badgeCounts(for signature: SidebarBadgeSignature) -> SidebarBadgeCounts {
        if cachedBadgeSignature == signature, let cached = cachedBadgeCounts {
            return cached
        }
        return computeSidebarBadgeCounts()
    }

    /// Ein einziger Durchlauf über alle Artikel bündelt alle Badge-Zähler
    /// (Tags + SmartFolder-Status). Läuft nur bei Signaturänderung, nicht pro
    /// Render.
    private func computeSidebarBadgeCounts() -> SidebarBadgeCounts {
        // feedID → Set der Tag-IDs, deren Feeds diesen Feed enthalten. Entspricht
        // ArticleListQuery.tagPredicate (matcht article.feedID, nicht die
        // feed-Relationship) — konsistent mit der Artikelliste, auch bei
        // verwaisten Artikeln (feedID gesetzt, feed == nil).
        var feedTagIDsByFeedID: [UUID: Set<PersistentIdentifier>] = [:]
        for feed in feeds {
            feedTagIDsByFeedID[feed.id] = Set(feed.tags.map(\.persistentModelID))
        }

        var tagCounts: [PersistentIdentifier: Int] = [:]
        var starred = 0
        var hidden = 0
        var saved = 0

        for article in allArticles {
            if article.isStarred { starred += 1 }
            if article.isHidden { hidden += 1 }
            if article.isStarred || article.isArchived { saved += 1 }

            // Ein Artikel trifft auf einen Tag zu, wenn er direkt getaggt ist
            // ODER sein Feed dem Tag zugeordnet ist (OR, nur einfach zählen).
            var matchingTagIDs = Set<PersistentIdentifier>()
            for tag in article.tags {
                matchingTagIDs.insert(tag.persistentModelID)
            }
            if let feedID = article.feedID {
                matchingTagIDs.formUnion(feedTagIDsByFeedID[feedID] ?? [])
            }
            for tagID in matchingTagIDs {
                tagCounts[tagID, default: 0] += 1
            }
        }

        return SidebarBadgeCounts(
            tagCounts: tagCounts,
            starred: starred,
            hidden: hidden,
            saved: saved
        )
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
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(interfaceTextSize.font(size: 10, weight: .bold))
                        .frame(width: interfaceTextSize.scaled(12))

                    Image(systemName: "folder")
                        .font(interfaceTextSize.font(size: 13, weight: .medium))

                    Text(title)
                        .font(interfaceTextSize.font(size: 12, weight: .medium))
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(SidebarStyle.primaryText.opacity(0.76))
            .padding(.horizontal, 10)
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(interfaceTextSize.font(size: 13, weight: .semibold))
            .fontWeight(.semibold)
            .foregroundStyle(
                isSelected ? SidebarStyle.primaryText : SidebarStyle.primaryText.opacity(0.82)
            )
            .padding(.horizontal, 10)
            .frame(height: interfaceTextSize.scaled(36))
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
        await viewModel.addFeed(urlString: urlString, context: modelContext)
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
