import SwiftData
import SwiftUI

enum ArticleInspectorTypography {
    static let titleFontSize = 15.0
    static let sectionTitleFontSize = 13.0
    static let primaryValueFontSize = 12.0
    static let controlFontSize = 11.5
    static let labelFontSize = 11.0
    static let secondaryFontSize = 11.0
    static let chipFontSize = 11.0
    static let iconFontSize = 12.0
}

private enum ArticleInspectorStyle {
    static let background = Color(red: 0.94, green: 0.95, blue: 0.96)
}

struct ArticleMetadataInspectorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.interfaceTextSize) private var interfaceTextSize
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query(sort: \FeedFolder.name) private var folders: [FeedFolder]
    @Query(sort: \Tag.name) private var tags: [Tag]

    @State private var newTagName = ""
    @State private var newTagColorHex = TagColorPalette.defaultColorHex
    @State private var newFolderName = ""
    @State private var articleViewModel = ArticleViewModel()
    @State private var isFeedFolderSectionExpanded = true
    @State private var isTagSectionExpanded = true
    @State private var isContextSectionExpanded = true
    @State private var isSourceSectionExpanded = false

    let article: Article
    let close: () -> Void
    var isOfflineOperationInProgress = false
    var toggleOfflineAvailability: () -> Void = {}

    private var folderNames: [String] {
        FeedFolderOrganizer.folderNames(in: feeds, folders: folders)
    }

    private var folderSelection: Binding<String> {
        Binding {
            article.feed?.folderName ?? ""
        } set: { newValue in
            ArticleMetadataEditor.setFolderName(
                newValue.isEmpty ? nil : newValue,
                for: article,
                context: modelContext
            )
        }
    }

    private var sortedAllTags: [Tag] {
        tags.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var details: ArticleInspectorDetails {
        ArticleInspectorFormatter.details(for: article)
    }

    private var selectedFolderTitle: String {
        guard let folderName = FeedFolderOrganizer.normalizedFolderName(article.feed?.folderName) else {
            return String(localized: "reader.inspector.noFolder")
        }

        return folderName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    primaryActionSection
                    feedFolderSection
                    tagSection
                    contextSection
                    sourceSection
                }
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 280, idealWidth: 318, maxWidth: 360)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ArticleInspectorStyle.background)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.readerInspectorTitle)
                    .font(interfaceTextSize.font(size: ArticleInspectorTypography.labelFontSize, weight: .bold))
                    .foregroundStyle(SidebarStyle.sectionText)

                Text(details.title)
                    .font(interfaceTextSize.font(size: ArticleInspectorTypography.titleFontSize, weight: .semibold))
                    .foregroundStyle(SidebarStyle.primaryText)
                    .lineLimit(3)

                statusStrip
            }

            Spacer()

            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(interfaceTextSize.font(size: ArticleInspectorTypography.iconFontSize, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(SidebarStyle.primaryText)
            .frame(
                width: interfaceTextSize.scaled(30),
                height: interfaceTextSize.scaled(30)
            )
            .background(SidebarStyle.activeSelection, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .help(L10n.readerInspectorButton)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SidebarStyle.separator)
                .frame(height: 1)
        }
    }

    private var statusStrip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(details.isRead ? Color.green : Color.blue)
                .frame(width: 8, height: 8)

            Text(LocalizedStringKey(details.readStateKey))
                .font(interfaceTextSize.font(size: ArticleInspectorTypography.labelFontSize, weight: .semibold))
                .foregroundStyle(SidebarStyle.secondaryText)

            Rectangle()
                .fill(SidebarStyle.separator)
                .frame(width: 1, height: 13)
                .padding(.horizontal, 2)

            Image(systemName: details.starStateSystemImage)
                .font(interfaceTextSize.font(size: ArticleInspectorTypography.iconFontSize, weight: .semibold))
                .foregroundStyle(details.isStarred ? Color.yellow : SidebarStyle.secondaryText)

            Text(LocalizedStringKey(details.starStateKey))
                .font(interfaceTextSize.font(size: ArticleInspectorTypography.labelFontSize, weight: .semibold))
                .foregroundStyle(SidebarStyle.secondaryText)
        }
    }

    private var sourceSection: some View {
        inspectorSection(
            L10n.readerInspectorSourceSection,
            isExpanded: $isSourceSectionExpanded
        ) {
            VStack(alignment: .leading, spacing: 7) {
                wideSourceButton(
                    title: LocalizedStringKey(L10n.articleCopyLinkCommand),
                    systemImage: "link"
                ) {
                    _ = articleViewModel.copyLink(article)
                }
                .disabled(!details.hasOriginalURL)

                wideSourceButton(
                    title: L10n.readerOpenOriginal,
                    systemImage: "arrow.up.right"
                ) {
                    _ = articleViewModel.openOriginal(article)
                }
                .disabled(!details.hasOriginalURL)

                if !details.hasOriginalURL {
                    Text(L10n.readerInspectorUnavailable)
                        .font(interfaceTextSize.font(size: ArticleInspectorTypography.secondaryFontSize))
                        .foregroundStyle(SidebarStyle.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var primaryActionSection: some View {
        HStack(spacing: 8) {
            actionIconButton(
                systemImage: details.isStarred ? "star.fill" : "star",
                tint: details.isStarred ? .yellow : SidebarStyle.primaryText,
                isActive: details.isStarred,
                activeTint: .yellow,
                help: L10n.readerInspectorStarStatus
            ) {
                articleViewModel.toggleStarred(article)
            }

            actionIconButton(
                systemImage: "book.pages",
                tint: details.isRead ? .green : SidebarStyle.primaryText,
                isActive: details.isRead,
                activeTint: .green,
                help: L10n.readerInspectorReadStatus
            ) {
                articleViewModel.toggleRead(article)
            }

            actionIconButton(
                systemImage: article.offlineState.isAvailable ? "wifi.slash" : "wifi",
                tint: article.offlineState.isAvailable ? .blue : SidebarStyle.primaryText,
                isActive: article.offlineState.isAvailable,
                activeTint: .blue,
                help: LocalizedStringKey(details.offlineActionKey)
            ) {
                toggleOfflineAvailability()
            }
            .disabled(isOfflineOperationInProgress)

            actionIconButton(
                systemImage: "link",
                tint: details.hasOriginalURL ? SidebarStyle.primaryText : SidebarStyle.secondaryText,
                isActive: false,
                activeTint: .blue,
                help: LocalizedStringKey(L10n.articleCopyLinkCommand)
            ) {
                _ = articleViewModel.copyLink(article)
            }
            .disabled(!details.hasOriginalURL)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var feedFolderSection: some View {
        inspectorSection(
            L10n.readerInspectorFeedFolder,
            isExpanded: $isFeedFolderSectionExpanded
        ) {
            sectionLabel(L10n.readerInspectorFeedFolder)

            Menu {
                Button(L10n.readerInspectorNoFolder) {
                    ArticleMetadataEditor.setFolderName(nil, for: article, context: modelContext)
                }

                if !folderNames.isEmpty {
                    Divider()
                }

                ForEach(folderNames, id: \.self) { folderName in
                    Button(folderName) {
                        ArticleMetadataEditor.setFolderName(folderName, for: article, context: modelContext)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedFolderTitle)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(interfaceTextSize.font(size: 10, weight: .bold))
                        .foregroundStyle(SidebarStyle.primaryText)
                        .frame(
                            width: interfaceTextSize.scaled(22),
                            height: interfaceTextSize.scaled(22)
                        )
                        .background(SidebarStyle.activeSelection, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .font(interfaceTextSize.font(size: ArticleInspectorTypography.controlFontSize))
                .foregroundStyle(SidebarStyle.primaryText)
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .frame(maxWidth: .infinity, minHeight: interfaceTextSize.scaled(30), alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .menuStyle(.button)

            Text(L10n.readerInspectorFeedFolderHint)
                .font(interfaceTextSize.font(size: ArticleInspectorTypography.secondaryFontSize))
                .lineSpacing(1)
                .foregroundStyle(SidebarStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel(L10n.readerInspectorNewFeedFolder)

                HStack(spacing: 8) {
                    TextField(L10n.readerInspectorNewFeedFolderPlaceholder, text: $newFolderName)
                        .textFieldStyle(.plain)
                        .font(interfaceTextSize.font(size: ArticleInspectorTypography.controlFontSize))
                        .padding(.horizontal, 9)
                        .frame(height: interfaceTextSize.scaled(30))
                        .inspectorControl()
                        .onSubmit(addFolder)

                    Button {
                        addFolder()
                    } label: {
                        Image(systemName: "plus")
                            .font(interfaceTextSize.font(size: ArticleInspectorTypography.iconFontSize, weight: .semibold))
                    }
                    .disabled(FeedFolderOrganizer.normalizedFolderName(newFolderName) == nil)
                    .buttonStyle(.plain)
                    .frame(
                        width: interfaceTextSize.scaled(32),
                        height: interfaceTextSize.scaled(30)
                    )
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(SidebarStyle.separator, lineWidth: 1)
                    }
                    .foregroundStyle(
                        FeedFolderOrganizer.normalizedFolderName(newFolderName) == nil
                        ? SidebarStyle.secondaryText
                        : SidebarStyle.primaryText
                    )
                }
            }
        }
    }

    private var tagSection: some View {
        inspectorSection(
            L10n.readerInspectorTags,
            isExpanded: $isTagSectionExpanded
        ) {
            if sortedAllTags.isEmpty {
                Text(L10n.readerInspectorNoTags)
                    .font(interfaceTextSize.font(size: ArticleInspectorTypography.primaryValueFontSize))
                    .foregroundStyle(SidebarStyle.secondaryText)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(sortedAllTags) { tag in
                        tagTogglePill(tag)
                    }
                }
            }

            tagCreator
        }
    }

    private var tagCreator: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(L10n.readerInspectorNewTag)

            HStack(spacing: 6) {
                TextField(L10n.readerInspectorAddTagPlaceholder, text: $newTagName)
                    .textFieldStyle(.plain)
                    .font(interfaceTextSize.font(size: ArticleInspectorTypography.controlFontSize))
                    .padding(.horizontal, 9)
                    .frame(height: interfaceTextSize.scaled(30))
                    .inspectorControl()
                    .onSubmit(addTag)

                Button {
                    addTag()
                } label: {
                    Image(systemName: "plus")
                        .font(interfaceTextSize.font(size: ArticleInspectorTypography.iconFontSize, weight: .semibold))
                }
                .disabled(ArticleMetadataEditor.normalizedTagName(newTagName) == nil)
                .buttonStyle(.plain)
                .frame(
                    width: interfaceTextSize.scaled(32),
                    height: interfaceTextSize.scaled(30)
                )
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(SidebarStyle.separator, lineWidth: 1)
                }
                .foregroundStyle(
                    ArticleMetadataEditor.normalizedTagName(newTagName) == nil
                    ? SidebarStyle.secondaryText
                    : SidebarStyle.primaryText
                )
            }

            ColorSwatchPicker(selection: $newTagColorHex)
        }
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SidebarStyle.separator)
                .frame(height: 1)
        }
        .padding(.top, 4)
    }

    private var contextSection: some View {
        inspectorSection(
            L10n.readerInspectorContextSection,
            isExpanded: $isContextSectionExpanded
        ) {
            VStack(spacing: 7) {
                metadataListRow(title: L10n.readerInspectorFeed, value: details.feedName)
                metadataListRow(
                    title: L10n.readerInspectorOriginalLink,
                    value: details.originalURL?.host(percentEncoded: false)
                )
                metadataListRow(title: L10n.readerInspectorPublished, value: details.publishedAtText)
                metadataListRow(title: L10n.readerInspectorReadingTime, value: details.readingTime)
                metadataListRow(
                    title: L10n.readerInspectorOfflineStatus,
                    value: NSLocalizedString(details.offlineStateKey, comment: "")
                )
            }
        }
    }

    private func sectionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(interfaceTextSize.font(size: ArticleInspectorTypography.labelFontSize, weight: .bold))
            .fontWeight(.bold)
            .foregroundStyle(SidebarStyle.sectionText)
    }

    private func inspectorSection<Content: View>(
        _ title: LocalizedStringKey,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(interfaceTextSize.font(size: ArticleInspectorTypography.labelFontSize, weight: .bold))
                        .foregroundStyle(SidebarStyle.secondaryText)
                        .frame(width: 15)

                    Text(title)
                        .font(interfaceTextSize.font(size: ArticleInspectorTypography.sectionTitleFontSize, weight: .bold))
                        .foregroundStyle(SidebarStyle.primaryText)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
            }
        }
        .padding(12)
        .inspectorPanel(cornerRadius: 11)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func actionIconButton(
        systemImage: String,
        tint: Color,
        isActive: Bool,
        activeTint: Color,
        help: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(interfaceTextSize.font(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: interfaceTextSize.scaled(40))
                .background(actionButtonBackground(isActive: isActive, tint: activeTint), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(actionButtonBorder(isActive: isActive, tint: activeTint), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func actionButtonBackground(isActive: Bool, tint: Color) -> Color {
        isActive ? tint.opacity(0.12) : Color(nsColor: .textBackgroundColor)
    }

    private func actionButtonBorder(isActive: Bool, tint: Color) -> Color {
        isActive ? tint.opacity(0.32) : SidebarStyle.separator
    }

    private func wideSourceButton(
        title: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(title)
                    .lineLimit(1)
            } icon: {
                Image(systemName: systemImage)
                    .font(interfaceTextSize.font(size: 15, weight: .semibold))
            }
            .font(interfaceTextSize.font(size: ArticleInspectorTypography.primaryValueFontSize, weight: .semibold))
            .foregroundStyle(SidebarStyle.primaryText)
            .frame(maxWidth: .infinity, minHeight: interfaceTextSize.scaled(31), alignment: .leading)
            .padding(.horizontal, 9)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(SidebarStyle.separator, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func metadataListRow(title: LocalizedStringKey, value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(interfaceTextSize.font(size: ArticleInspectorTypography.labelFontSize, weight: .bold))
                .foregroundStyle(SidebarStyle.secondaryText)
                .frame(width: 88, alignment: .leading)

            Text(value ?? String(localized: "reader.inspector.unavailable"))
                .font(interfaceTextSize.font(size: ArticleInspectorTypography.primaryValueFontSize, weight: .semibold))
                .foregroundStyle(value == nil ? SidebarStyle.secondaryText : SidebarStyle.primaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 22)
    }

    private func tagTogglePill(_ tag: Tag) -> some View {
        let tagColor = TagColorPalette.color(for: tag.colorHex)
        let isActive = article.tags.contains { $0.id == tag.id }

        return Button {
            toggleTag(tag)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "tag")
                    .font(interfaceTextSize.font(size: ArticleInspectorTypography.chipFontSize, weight: .semibold))

                Text(tag.name)
                    .lineLimit(1)
            }
            .font(interfaceTextSize.font(size: ArticleInspectorTypography.chipFontSize, weight: .semibold))
            .fontWeight(.semibold)
            .foregroundStyle(isActive ? SidebarStyle.primaryText : SidebarStyle.secondaryText)
            .padding(.horizontal, 8)
            .frame(minHeight: interfaceTextSize.scaled(26))
            .background(isActive ? tagColor.opacity(0.12) : Color(nsColor: .textBackgroundColor), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(isActive ? tagColor.opacity(0.42) : SidebarStyle.separator, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func toggleTag(_ tag: Tag) {
        if article.tags.contains(where: { $0.id == tag.id }) {
            ArticleMetadataEditor.removeTag(tag, from: article, context: modelContext)
        } else {
            ArticleMetadataEditor.addTag(
                named: tag.name,
                to: article,
                availableTags: tags,
                context: modelContext
            )
        }
    }

    private func addTag() {
        ArticleMetadataEditor.addTag(
            named: newTagName,
            colorHex: newTagColorHex,
            to: article,
            availableTags: tags,
            context: modelContext
        )
        newTagName = ""
    }

    private func addFolder() {
        ArticleMetadataEditor.createFolderAndAssign(
            named: newFolderName,
            to: article,
            existingFolders: folders,
            context: modelContext
        )
        newFolderName = ""
    }
}

private extension View {
    func inspectorControl(cornerRadius: CGFloat = 8) -> some View {
        self
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SidebarStyle.separator, lineWidth: 1)
            }
    }

    func inspectorPanel(cornerRadius: CGFloat = 8) -> some View {
        self
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SidebarStyle.separator, lineWidth: 1)
            }
    }
}

struct ArticleInspectorDetails: Equatable {
    let title: String
    let summaryExcerpt: String?
    let feedName: String?
    let feedInitial: String
    let publishedAtText: String?
    let readingTime: String?
    let isRead: Bool
    let readStateKey: String
    let readStateSystemImage: String
    let isStarred: Bool
    let starStateKey: String
    let starStateSystemImage: String
    let contentAvailabilityKey: String
    let contentAvailabilityDetail: String
    let contentAvailabilitySystemImage: String
    let offlineStateKey: String
    let offlineStateSystemImage: String
    let offlineDetail: String?
    let offlineActionKey: String
    let offlineActionSystemImage: String
    let originalURL: URL?

    var hasOriginalURL: Bool {
        originalURL != nil
    }

    var offlineTint: Color {
        switch offlineStateKey {
        case "reader.offline.failed":
            .orange
        case "reader.offline.feedContentAvailable", "reader.offline.fullTextAvailable":
            .green
        default:
            .secondary
        }
    }
}

enum ArticleInspectorFormatter {
    static func details(for article: Article) -> ArticleInspectorDetails {
        let contentAvailability = ReaderContentAvailability.resolved(
            offlineState: article.offlineState,
            offlineContent: article.offlineContent,
            content: article.content,
            summary: article.summary
        )
        let feedName = normalizedText(article.feed?.title)

        return ArticleInspectorDetails(
            title: normalizedText(article.title) ?? String(localized: "reader.inspector.unavailable"),
            summaryExcerpt: summaryExcerpt(article.summary),
            feedName: feedName,
            feedInitial: feedInitial(feedName),
            publishedAtText: publishedAtText(article.publishedAt),
            readingTime: ReaderMetadataFormatter.readingTimeText(
                content: preferredReadingContent(for: article),
                summary: article.summary
            ),
            isRead: article.isRead,
            readStateKey: article.isRead ? "reader.inspector.read" : "reader.inspector.unread",
            readStateSystemImage: article.isRead ? "checkmark.circle" : "circle.fill",
            isStarred: article.isStarred,
            starStateKey: article.isStarred ? "reader.inspector.starred" : "reader.inspector.notStarred",
            starStateSystemImage: article.isStarred ? "star.fill" : "star",
            contentAvailabilityKey: contentAvailability.localizationKey,
            contentAvailabilityDetail: contentAvailability.detailText,
            contentAvailabilitySystemImage: contentAvailability.systemImageName,
            offlineStateKey: article.offlineState.localizationKey,
            offlineStateSystemImage: article.offlineState.systemImageName,
            offlineDetail: offlineDetail(for: article),
            offlineActionKey: article.offlineState.isAvailable ? "reader.offline.remove" : "reader.offline.save",
            offlineActionSystemImage: article.offlineState.isAvailable ? "trash" : "arrow.down.circle",
            originalURL: originalURL(from: article.link)
        )
    }

    private static func preferredReadingContent(for article: Article) -> String? {
        if article.offlineState.isAvailable, let offlineContent = normalizedText(article.offlineContent) {
            return offlineContent
        }

        return article.content
    }

    private static func publishedAtText(_ date: Date?) -> String? {
        date?.formatted(date: .abbreviated, time: .shortened)
    }

    private static func summaryExcerpt(_ summary: String?) -> String? {
        guard let summary = normalizedText(summary) else {
            return nil
        }

        let plainSummary = summary
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !plainSummary.isEmpty else {
            return nil
        }

        if plainSummary.count <= 180 {
            return plainSummary
        }

        let endIndex = plainSummary.index(plainSummary.startIndex, offsetBy: 180)
        return "\(plainSummary[..<endIndex])..."
    }

    private static func feedInitial(_ feedName: String?) -> String {
        guard let firstCharacter = feedName?.first else {
            return "F"
        }

        return String(firstCharacter).uppercased()
    }

    private static func offlineDetail(for article: Article) -> String? {
        if article.offlineState == .failed {
            return normalizedText(article.offlineErrorMessage)
        }

        return article.offlineSavedAt?.feedivoRelativeDisplay
    }

    private static func originalURL(from link: String?) -> URL? {
        guard let link = normalizedText(link), let url = URL(string: link), url.scheme != nil else {
            return nil
        }

        return url
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

private extension ReaderContentAvailability {
    var localizationKey: String {
        switch self {
        case .fullText:
            "reader.inspector.content.fullText"
        case .feedContent:
            "reader.inspector.content.feedContent"
        case .summaryOnly:
            "reader.inspector.content.summaryOnly"
        case .empty:
            "reader.inspector.content.empty"
        }
    }

    var systemImageName: String {
        switch self {
        case .fullText:
            "doc.text.fill"
        case .feedContent:
            "doc.text"
        case .summaryOnly:
            "text.alignleft"
        case .empty:
            "doc"
        }
    }

    var detailText: String {
        switch self {
        case .fullText:
            String(localized: "reader.inspector.content.fullText.detail")
        case .feedContent:
            String(localized: "reader.inspector.content.feedContent.detail")
        case .summaryOnly:
            String(localized: "reader.inspector.content.summaryOnly.detail")
        case .empty:
            String(localized: "reader.inspector.content.empty.detail")
        }
    }
}

private extension ArticleOfflineState {
    var localizationKey: String {
        switch self {
        case .none:
            "reader.offline.notSaved"
        case .feedContent:
            "reader.offline.feedContentAvailable"
        case .fullText:
            "reader.offline.fullTextAvailable"
        case .failed:
            "reader.offline.failed"
        }
    }

    var systemImageName: String {
        switch self {
        case .none:
            "arrow.down.circle"
        case .feedContent, .fullText:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }
}

private struct TimelineStripe: View {
    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .stroke(.blue, lineWidth: 2)
                .frame(width: 8, height: 8)

            Rectangle()
                .fill(SidebarStyle.separator)
                .frame(width: 1)

            Circle()
                .stroke(SidebarStyle.secondaryText.opacity(0.55), lineWidth: 2)
                .frame(width: 8, height: 8)

            Rectangle()
                .fill(SidebarStyle.separator)
                .frame(width: 1)

            Circle()
                .stroke(SidebarStyle.secondaryText.opacity(0.55), lineWidth: 2)
                .frame(width: 8, height: 8)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let rows = rows(in: width, subviews: subviews)
        return CGSize(
            width: width,
            height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * spacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = bounds.origin
        for row in rows(in: bounds.width, subviews: subviews) {
            origin.x = bounds.minX
            for element in row.elements {
                element.subview.place(
                    at: origin,
                    proposal: ProposedViewSize(element.size)
                )
                origin.x += element.size.width + spacing
            }
            origin.y += row.height + spacing
        }
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentRow = Row()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRow.width + size.width > width, !currentRow.elements.isEmpty {
                rows.append(currentRow)
                currentRow = Row()
            }

            currentRow.add(subview: subview, size: size, spacing: spacing)
        }

        if !currentRow.elements.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    private struct Row {
        var elements: [(subview: LayoutSubview, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func add(subview: LayoutSubview, size: CGSize, spacing: CGFloat) {
            if !elements.isEmpty {
                width += spacing
            }
            elements.append((subview, size))
            width += size.width
            height = max(height, size.height)
        }
    }
}
