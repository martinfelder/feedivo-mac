import AppKit
import SwiftUI

private enum SQLiteArticleInspectorStyle {
    // Vorher hartcodiertes Fast-Weiss (blieb in Dark Mode hell). Jetzt Systemsemantikfarbe,
    // die sich automatisch an Hell/Dunkel anpasst.
    static let background = Color(nsColor: .controlBackgroundColor)
}

/// SQLite-Inspector für den produktiven Reader.
/// Das Layout orientiert sich am früheren Artikelinfo-Inspector, alle Datenänderungen laufen über GRDB-Stores.
struct ArticleMetadataInspectorView: View {
    @Environment(\.feedivoDatabase) private var database
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    @AppStorage(ArticleDateDisplayMode.storageKey)
    private var dateDisplayModeRawValue = ArticleDateDisplayMode.defaultMode.rawValue

    let snapshot: ArticleReaderSnapshot
    let close: () -> Void

    @State private var currentSnapshot: ArticleReaderSnapshot
    @State private var folderNames: [String] = []
    @State private var newFolderName = ""
    @State private var isFeedFolderSectionExpanded = true
    @State private var isTagSectionExpanded = true
    @State private var isContextSectionExpanded = true
    @State private var isSourceSectionExpanded = false

    init(snapshot: ArticleReaderSnapshot, close: @escaping () -> Void) {
        self.snapshot = snapshot
        self.close = close
        _currentSnapshot = State(initialValue: snapshot)
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
        .background(SQLiteArticleInspectorStyle.background)
        .task {
            reloadInspectorData()
        }
        .onChange(of: snapshot) { _, newSnapshot in
            currentSnapshot = newSnapshot
            reloadInspectorData()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.readerInspectorTitle)
                    .font(interfaceTextSize.font(size: ArticleInspectorTypography.labelFontSize, weight: .bold))
                    .foregroundStyle(SidebarStyle.sectionText)

                Text(currentSnapshot.title)
                    .font(interfaceTextSize.font(size: ArticleInspectorTypography.titleFontSize, weight: .semibold))
                    .lineLimit(3)
                    .foregroundStyle(SidebarStyle.primaryText)

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
            .frame(width: interfaceTextSize.scaled(30), height: interfaceTextSize.scaled(30))
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
                .fill(currentSnapshot.isRead ? Color.green : Color.accentColor)
                .frame(width: 8, height: 8)

            Text(currentSnapshot.isRead ? L10n.articleRowMarkUnread : L10n.articleRowMarkRead)
                .font(interfaceTextSize.font(size: ArticleInspectorTypography.labelFontSize, weight: .semibold))
                .foregroundStyle(SidebarStyle.secondaryText)

            Rectangle()
                .fill(SidebarStyle.separator)
                .frame(width: 1, height: 13)
                .padding(.horizontal, 2)

            Image(systemName: currentSnapshot.isStarred ? "star.fill" : "star")
                .font(interfaceTextSize.font(size: ArticleInspectorTypography.iconFontSize, weight: .semibold))
                .foregroundStyle(currentSnapshot.isStarred ? Color.yellow : SidebarStyle.secondaryText)

            Text(currentSnapshot.isStarred ? L10n.articleRowStarRemove : L10n.articleRowStarAdd)
                .font(interfaceTextSize.font(size: ArticleInspectorTypography.labelFontSize, weight: .semibold))
                .foregroundStyle(SidebarStyle.secondaryText)
        }
    }

    private var primaryActionSection: some View {
        HStack(spacing: 8) {
            actionIconButton(
                systemImage: currentSnapshot.isStarred ? "star.fill" : "star",
                tint: currentSnapshot.isStarred ? .yellow : SidebarStyle.primaryText,
                isActive: currentSnapshot.isStarred,
                activeTint: .yellow,
                help: L10n.readerInspectorStarStatus
            ) {
                toggleStarred()
            }

            actionIconButton(
                systemImage: "book.pages",
                tint: currentSnapshot.isRead ? .green : SidebarStyle.primaryText,
                isActive: currentSnapshot.isRead,
                activeTint: .green,
                help: L10n.readerInspectorReadStatus
            ) {
                toggleRead()
            }

            actionIconButton(
                systemImage: "link",
                tint: originalURL == nil ? SidebarStyle.secondaryText : SidebarStyle.primaryText,
                isActive: false,
                activeTint: .blue,
                help: LocalizedStringKey(L10n.articleCopyLinkCommand)
            ) {
                copyLink()
            }
            .disabled(originalURL == nil)

            actionIconButton(
                systemImage: "arrow.up.right",
                tint: originalURL == nil ? SidebarStyle.secondaryText : SidebarStyle.primaryText,
                isActive: false,
                activeTint: .blue,
                help: L10n.readerOpenOriginal
            ) {
                openOriginal()
            }
            .disabled(originalURL == nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var feedFolderSection: some View {
        inspectorSection(
            L10n.readerInspectorFeedFolder,
            isExpanded: $isFeedFolderSectionExpanded
        ) {
            sectionLabel(L10n.readerInspectorFeedFolder)

            Menu {
                Button(L10n.readerInspectorNoFolder) {
                    setFolderName(nil)
                }

                if !folderNames.isEmpty {
                    Divider()
                }

                ForEach(folderNames, id: \.self) { folderName in
                    Button(folderName) {
                        setFolderName(folderName)
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
                        .frame(width: interfaceTextSize.scaled(22), height: interfaceTextSize.scaled(22))
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
                        .sqliteInspectorControl()
                        .onSubmit(addFolder)

                    Button {
                        addFolder()
                    } label: {
                        Image(systemName: "plus")
                            .font(interfaceTextSize.font(size: ArticleInspectorTypography.iconFontSize, weight: .semibold))
                    }
                    .disabled(FeedFolderOrganizer.normalizedFolderName(newFolderName) == nil)
                    .buttonStyle(.plain)
                    .frame(width: interfaceTextSize.scaled(32), height: interfaceTextSize.scaled(30))
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
            ArticleTagAssignmentView(articleID: currentSnapshot.id, snapshotTags: currentSnapshot.tags)
        }
    }

    private var contextSection: some View {
        inspectorSection(
            L10n.readerInspectorContextSection,
            isExpanded: $isContextSectionExpanded
        ) {
            VStack(spacing: 7) {
                metadataListRow(title: L10n.readerInspectorFeed, value: currentSnapshot.feedTitle)
                metadataListRow(title: L10n.readerInspectorFolder, value: currentSnapshot.folderName)
                metadataListRow(title: L10n.readerInspectorOriginalLink, value: originalURL?.host(percentEncoded: false))
                metadataListRow(title: L10n.readerInspectorPublished, value: publishedAtText)
                metadataListRow(title: L10n.readerInspectorReadingTime, value: readingTimeText)
            }
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
                    copyLink()
                }
                .disabled(originalURL == nil)

                wideSourceButton(
                    title: L10n.readerOpenOriginal,
                    systemImage: "arrow.up.right"
                ) {
                    openOriginal()
                }
                .disabled(originalURL == nil)

                if originalURL == nil {
                    Text(L10n.readerInspectorUnavailable)
                        .font(interfaceTextSize.font(size: ArticleInspectorTypography.secondaryFontSize))
                        .foregroundStyle(SidebarStyle.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedFolderTitle: String {
        FeedFolderOrganizer.normalizedFolderName(currentSnapshot.folderName)
        ?? String(localized: "reader.inspector.noFolder")
    }

    private var originalURL: URL? {
        guard let link = currentSnapshot.link,
              let url = URL(string: link) else {
            return nil
        }

        return url
    }

    private var publishedAtText: String? {
        currentSnapshot.publishedAt?.feedivoDisplay(mode: ArticleDateDisplayMode.resolved(from: dateDisplayModeRawValue))
    }

    private var readingTimeText: String? {
        guard let minutes = currentSnapshot.estimatedReadingMinutes else {
            return nil
        }

        return L10n.readerReadingTime(minutes: minutes)
    }

    private func sectionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(interfaceTextSize.font(size: ArticleInspectorTypography.labelFontSize, weight: .bold))
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
        .sqliteInspectorPanel(cornerRadius: 11)
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

    private func reloadInspectorData() {
        guard let database else {
            folderNames = []
            return
        }

        do {
            if let reloadedSnapshot = try ArticleStore(database: database).readerArticle(id: currentSnapshot.id) {
                currentSnapshot = reloadedSnapshot
            }

            let feedFolderStore = FeedFolderStore(database: database)
            let feeds = try FeedStore(database: database).feeds()
            let explicitFolders = try feedFolderStore.folders()
            folderNames = FeedFolderOrganizer.folderNames(
                feedFolderNames: feeds.map(\.folderName),
                explicitFolderNames: explicitFolders.map(\.name)
            )
        } catch {
            return
        }
    }

    private func toggleRead() {
        guard let database else {
            return
        }

        do {
            try ArticleStatusStore(database: database).setRead(!currentSnapshot.isRead, articleID: currentSnapshot.id, at: Date())
            reloadInspectorData()
        } catch {
            return
        }
    }

    private func toggleStarred() {
        guard let database else {
            return
        }

        do {
            try ArticleStatusStore(database: database).setStarred(!currentSnapshot.isStarred, articleID: currentSnapshot.id, at: Date())
            reloadInspectorData()
        } catch {
            return
        }
    }

    private func setFolderName(_ folderName: String?) {
        guard let database else {
            return
        }

        do {
            try FeedStore(database: database).updateFolderName(id: currentSnapshot.feedID, folderName: folderName)
            SQLiteDataInvalidationSignal.shared.bumpStatusVersion()
            reloadInspectorData()
        } catch {
            return
        }
    }

    private func addFolder() {
        guard let database,
              let normalizedFolderName = FeedFolderOrganizer.normalizedFolderName(newFolderName) else {
            return
        }

        do {
            try FeedFolderStore(database: database).save(
                FeedFolderRecord(name: normalizedFolderName)
            )
            try FeedStore(database: database).updateFolderName(id: currentSnapshot.feedID, folderName: normalizedFolderName)
            SQLiteDataInvalidationSignal.shared.bumpStatusVersion()
            newFolderName = ""
            reloadInspectorData()
        } catch {
            return
        }
    }

    private func copyLink() {
        guard let link = currentSnapshot.link else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(link, forType: .string)
    }

    private func openOriginal() {
        guard let originalURL else {
            return
        }

        ArticleOriginalBrowserLauncher.open(originalURL)
    }
}

extension View {
    func sqliteInspectorControl(cornerRadius: CGFloat = 8) -> some View {
        self
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SidebarStyle.separator, lineWidth: 1)
            }
    }

    func sqliteInspectorPanel(cornerRadius: CGFloat = 8) -> some View {
        self
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SidebarStyle.separator, lineWidth: 1)
            }
    }
}
