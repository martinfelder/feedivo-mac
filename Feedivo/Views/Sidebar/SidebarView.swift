import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query(sort: \FeedFolder.name) private var folders: [FeedFolder]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(sort: \Rule.name) private var rules: [Rule]
    @Binding var selection: SidebarSelection?
    let selectedArticle: Article?
    let onRequestAddFeed: () -> Void
    let onRequestDeleteFeed: (Feed) -> Void
    let onRequestCreateRuleFromArticle: (Article) -> Void
    @State private var feedShowingProperties: Feed?
    @State private var feedRenaming: Feed?
    @State private var isShowingAddFolderSheet = false
    @State private var isShowingTagManager = false
    @State private var collapsedFolderNames: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    smartFiltersSection
                    tagsSection
                    rulesSection
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

    private var smartFiltersSection: some View {
        SidebarSection(title: L10n.sidebarSmartFiltersSection) {
            ForEach(SmartFilter.allCases) { smartFilter in
                SidebarRow(
                    title: smartFilter.title,
                    systemImage: smartFilter.systemImage,
                    iconColor: smartFilter.iconColor.color,
                    isSelected: selection == .smartFilter(smartFilter),
                    badgeText: smartFilter == .unread
                        ? SidebarUnreadCount.badgeText(
                            for: SidebarUnreadCount.totalUnreadArticleCount(in: feeds)
                        )
                        : nil
                ) {
                    selection = .smartFilter(smartFilter)
                }
            }
        }
    }

    private var tagsSection: some View {
        SidebarActionSection(
            title: L10n.sidebarTagsSection,
            actionSystemImage: "tag",
            actionHelp: String(localized: "tagManager.manage.button")
        ) {
            isShowingTagManager = true
        } content: {
            if !tags.isEmpty {
                tagRows(tags)
            }
        }
    }

    private var rulesSection: some View {
        SidebarActionSection(
            title: L10n.sidebarRulesSection,
            actionSystemImage: "slider.horizontal.3",
            actionHelp: L10n.ruleCreateFromArticle,
            isActionDisabled: selectedArticle == nil
        ) {
            if let selectedArticle {
                onRequestCreateRuleFromArticle(selectedArticle)
            }
        } content: {
            Text(L10n.sidebarRulesActiveCount(count: rules.filter(\.isEnabled).count))
                .font(interfaceTextSize.font(size: 13))
                .foregroundStyle(SidebarStyle.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
    }

    private var foldersSection: some View {
        SidebarActionSection(
            title: L10n.sidebarFoldersSection,
            actionSystemImage: "plus",
            actionHelp: String(localized: "sidebar.addFolder.button")
        ) {
            isShowingAddFolderSheet = true
        } content: {
            if feeds.isEmpty && folders.isEmpty {
                Text(L10n.sidebarEmptyTitle)
                    .font(interfaceTextSize.font(size: 13))
                    .foregroundStyle(SidebarStyle.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                let feedsWithoutFolder = FeedFolderOrganizer.feedsWithoutFolder(from: feeds)
                if !feedsWithoutFolder.isEmpty {
                    feedRows(feedsWithoutFolder)
                }

                ForEach(FeedFolderOrganizer.folderNames(in: feeds, folders: folders), id: \.self) { folderName in
                    let isExpanded = !collapsedFolderNames.contains(folderName)
                    SidebarFolderSection(
                        title: folderName,
                        isExpanded: isExpanded
                    ) {
                        toggleFolder(named: folderName)
                    } content: {
                        if isExpanded {
                            feedRows(
                                FeedFolderOrganizer.feeds(in: folderName, from: feeds),
                                isIndented: true
                            )
                        }
                    }
                }
            }
        }
    }

    private func feedRows(_ feeds: [Feed], isIndented: Bool = false) -> some View {
        ForEach(feeds) { feed in
            Button {
                selection = .feed(feed.persistentModelID)
            } label: {
                FeedRowView(
                    feed: feed,
                    unreadCount: SidebarUnreadCount.unreadArticleCount(for: feed)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(
                SidebarRowButtonStyle(
                    isSelected: selection == .feed(feed.persistentModelID),
                    leadingIndent: isIndented ? 18 : 0
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

    private func tagRows(_ tags: [Tag]) -> some View {
        ForEach(tags) { tag in
            Button {
                selection = .tag(tag.persistentModelID)
            } label: {
                TagSidebarRow(
                    tag: tag,
                    badgeText: SidebarTagCount.badgeText(for: tag)
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

private struct SidebarSection<Content: View>: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let title: LocalizedStringKey?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(interfaceTextSize.font(size: 11, weight: .bold))
                    .fontWeight(.bold)
                    .textCase(.uppercase)
                    .foregroundStyle(SidebarStyle.sectionText)
                    .padding(.horizontal, 10)
            }

            content
        }
    }
}

private struct SidebarActionSection<Content: View>: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let title: LocalizedStringKey
    let actionSystemImage: String
    let actionHelp: String
    var isActionDisabled = false
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(interfaceTextSize.font(size: 11, weight: .bold))
                    .fontWeight(.bold)
                    .textCase(.uppercase)

                Spacer()

                Button(action: action) {
                    Image(systemName: actionSystemImage)
                        .font(interfaceTextSize.font(size: 12, weight: .bold))
                        .frame(
                            width: interfaceTextSize.scaled(22),
                            height: interfaceTextSize.scaled(22)
                        )
                }
                .buttonStyle(.plain)
                .help(actionHelp)
                .disabled(isActionDisabled)
            }
            .foregroundStyle(SidebarStyle.sectionText)
            .padding(.horizontal, 10)

            content
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
                HStack(spacing: 7) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(interfaceTextSize.font(size: 10, weight: .bold))
                        .frame(width: interfaceTextSize.scaled(12))

                    Image(systemName: "folder")
                        .font(interfaceTextSize.font(size: 13, weight: .semibold))

                    Text(title)
                        .font(interfaceTextSize.font(size: 11, weight: .bold))
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fontWeight(.bold)
            .foregroundStyle(SidebarStyle.sectionText)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.sidebarAddFeedTitle)
                .font(.title2)
                .fontWeight(.semibold)

            TextField(L10n.sidebarAddFeedURLPlaceholder, text: $urlString)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.isLoading)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Spacer()

                Button(L10n.commonCancel) {
                    dismiss()
                }
                .disabled(viewModel.isLoading)

                Button {
                    Task {
                        await viewModel.addFeed(urlString: urlString, context: modelContext)
                        if viewModel.errorMessage == nil {
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(L10n.commonAdd)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
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
