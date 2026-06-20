import SwiftUI
import SwiftData

struct SidebarView: View {
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query(sort: \FeedFolder.name) private var folders: [FeedFolder]
    @Binding var selection: SidebarSelection?
    let onRequestAddFeed: () -> Void
    let onRequestDeleteFeed: (Feed) -> Void
    @State private var feedShowingProperties: Feed?
    @State private var isShowingAddFolderSheet = false
    @State private var collapsedFolderNames: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    smartFiltersSection
                    foldersSection
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .scrollContentBackground(.hidden)
        }
        .background(SidebarStyle.darkBackground)
        .navigationTitle("Feedivo")
        .sheet(item: $feedShowingProperties) { feed in
            FeedPropertiesView(feed: feed)
        }
        .sheet(isPresented: $isShowingAddFolderSheet) {
            AddFolderSheet(
                existingFolderNames: FeedFolderOrganizer.folderNames(
                    in: feeds,
                    folders: folders
                )
            )
        }
    }

    private var sidebarHeader: some View {
        HStack {
            Text("Feedivo")
                .font(.headline)
                .foregroundStyle(SidebarStyle.darkPrimaryText)

            Spacer()

            Button {
                onRequestAddFeed()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(SidebarStyle.darkPrimaryText)
            .background(SidebarStyle.darkActiveSelection, in: RoundedRectangle(cornerRadius: 8))
            .help(L10n.sidebarAddFeedButton)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SidebarStyle.darkSeparator)
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
                    isSelected: selection == .smartFilter(smartFilter)
                ) {
                    selection = .smartFilter(smartFilter)
                }
            }
        }
    }

    private var foldersSection: some View {
        SidebarActionSection(
            title: L10n.sidebarFoldersSection,
            actionSystemImage: "plus",
            actionHelp: L10n.sidebarAddFolderButton
        ) {
            isShowingAddFolderSheet = true
        } content: {
            if feeds.isEmpty && folders.isEmpty {
                Text(L10n.sidebarEmptyTitle)
                    .font(.callout)
                    .foregroundStyle(SidebarStyle.darkSecondaryText)
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
                FeedRowView(feed: feed)
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

private struct SidebarSection<Content: View>: View {
    let title: LocalizedStringKey?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .textCase(.uppercase)
                    .foregroundStyle(SidebarStyle.darkSectionText)
                    .padding(.horizontal, 10)
            }

            content
        }
    }
}

private struct SidebarActionSection<Content: View>: View {
    let title: LocalizedStringKey
    let actionSystemImage: String
    let actionHelp: LocalizedStringKey
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .textCase(.uppercase)

                Spacer()

                Button(action: action) {
                    Image(systemName: actionSystemImage)
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(actionHelp)
            }
            .foregroundStyle(SidebarStyle.darkSectionText)
            .padding(.horizontal, 10)

            content
        }
    }
}

private struct SidebarFolderSection<Content: View>: View {
    let title: String
    let isExpanded: Bool
    let toggle: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 7) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 12)

                    Image(systemName: "folder")
                        .font(.system(size: 13, weight: .semibold))

                    Text(title)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(SidebarStyle.darkSectionText)
            .padding(.horizontal, 10)
            .padding(.top, 8)

            content
        }
    }
}

private struct SidebarRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let iconColor: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
                    .lineLimit(1)
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor.opacity(SidebarStyle.darkIconOpacity))
                    .frame(width: 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(SidebarRowButtonStyle(isSelected: isSelected))
    }
}

private struct SidebarRowButtonStyle: ButtonStyle {
    let isSelected: Bool
    var leadingIndent: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .fontWeight(.semibold)
            .foregroundStyle(
                isSelected ? SidebarStyle.darkPrimaryText : SidebarStyle.darkPrimaryText.opacity(0.82)
            )
            .padding(.horizontal, 10)
            .frame(height: 36)
            .padding(.leading, leadingIndent)
            .background(rowBackground(configuration: configuration))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func rowBackground(configuration: Configuration) -> some View {
        let backgroundColor: Color = if isSelected {
            SidebarStyle.darkActiveSelection
        } else if configuration.isPressed {
            SidebarStyle.darkRowHover
        } else {
            Color.clear
        }

        RoundedRectangle(cornerRadius: 8)
            .fill(backgroundColor)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? SidebarStyle.darkActiveBorder : Color.clear,
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
