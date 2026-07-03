import AppKit
import SwiftUI

struct SQLiteReaderView: View {
    @Environment(\.feedivoDatabase) private var database
    @Environment(\.interfaceTextSize) private var interfaceTextSize

    let articleID: String
    let canSelectPreviousArticle: Bool
    let canSelectNextArticle: Bool
    let selectPreviousArticle: () -> Void
    let selectNextArticle: () -> Void
    let onSnapshotChange: (ArticleReaderSnapshot?) -> Void

    @State private var state = SQLiteReaderState()
    @State private var offlineDownloadService = SQLiteOfflineDownloadService()
    @State private var isOfflineOperationInProgress = false
    @State private var isAppearancePopoverPresented = false
    @State private var isMetadataInspectorPresented = false
    @State private var articleExportRequest: ArticleExportRequest?

    @AppStorage(ReaderTypographySettings.titleFontPresetKey)
    private var titleFontPresetRawValue = ReaderFontPreset.system.rawValue

    @AppStorage(ReaderTypographySettings.bodyFontPresetKey)
    private var bodyFontPresetRawValue = ReaderFontPreset.system.rawValue

    @AppStorage(ReaderTypographySettings.titleFontIsBoldKey)
    private var readerTitleFontIsBold = ReaderTypography.defaultTitleFontIsBold

    @AppStorage(ReaderTypographySettings.bodyFontIsBoldKey)
    private var readerBodyFontIsBold = ReaderTypography.defaultBodyFontIsBold

    @AppStorage(ReaderTypographySettings.bodyFontSizeKey)
    private var readerBodyFontSize = ReaderTypography.defaultBodyFontSize

    @AppStorage(ReaderTypographySettings.lineSpacingKey)
    private var readerLineSpacing = ReaderTypography.defaultLineSpacing

    @AppStorage(ReaderTypographySettings.titleLineSpacingKey)
    private var readerTitleLineSpacing = ReaderTypography.defaultTitleLineSpacing

    @AppStorage(ReaderTypographySettings.contentWidthKey)
    private var readerContentWidth = ReaderTypography.defaultContentWidth

    @AppStorage(ReaderDisplayMode.storageKey)
    private var readerDisplayModeRawValue = ReaderDisplayMode.defaultMode.rawValue

    init(
        articleID: String,
        canSelectPreviousArticle: Bool = false,
        canSelectNextArticle: Bool = false,
        selectPreviousArticle: @escaping () -> Void = {},
        selectNextArticle: @escaping () -> Void = {},
        onSnapshotChange: @escaping (ArticleReaderSnapshot?) -> Void = { _ in }
    ) {
        self.articleID = articleID
        self.canSelectPreviousArticle = canSelectPreviousArticle
        self.canSelectNextArticle = canSelectNextArticle
        self.selectPreviousArticle = selectPreviousArticle
        self.selectNextArticle = selectNextArticle
        self.onSnapshotChange = onSnapshotChange
    }

    var body: some View {
        Group {
            if let database {
                readerContent(database: database)
            } else {
                ContentUnavailableView(
                    "SQLite nicht verfügbar",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Die lokale Artikeldatenbank konnte nicht geöffnet werden.")
                )
            }
        }
        .navigationTitle(state.snapshot?.title ?? "")
        .onChange(of: state.snapshot) { _, snapshot in
            onSnapshotChange(snapshot)
        }
        .onDisappear {
            onSnapshotChange(nil)
        }
        .sheet(item: $articleExportRequest) { request in
            ArticleExportSheet(request: request) {
                articleExportRequest = nil
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Spacer()

                Button {
                    selectPreviousArticle()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .help(L10n.articlePreviousCommand)
                .disabled(!canSelectPreviousArticle)

                Button {
                    selectNextArticle()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .help(L10n.articleNextCommand)
                .disabled(!canSelectNextArticle)

                Button {
                    openOriginal()
                } label: {
                    Image(systemName: "safari")
                }
                .help(L10n.articleOpenOriginalCommand)
                .disabled(originalURL == nil)

                Button {
                    requestExportArticle()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help(L10n.articleExportCommand)
                .disabled(state.snapshot == nil)

                Button {
                    if let database {
                        state.toggleArchived(database: database)
                    }
                } label: {
                    Image(systemName: state.snapshot?.isArchived == true ? "archivebox.fill" : "archivebox")
                }
                .help(L10n.articleArchiveCommand)
                .disabled(state.snapshot == nil)

                Button {
                    if let database {
                        Task {
                            await toggleOffline(database: database)
                        }
                    }
                } label: {
                    Image(systemName: offlineToolbarSystemImage)
                }
                .help(offlineToolbarHelp)
                .disabled(state.snapshot == nil || isOfflineOperationInProgress)

                Picker(L10n.readerDisplayModePicker, selection: $readerDisplayModeRawValue) {
                    ForEach(ReaderDisplayMode.allCases) { mode in
                        Text(mode.titleKey)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .help(L10n.readerDisplayModeToggleHelp)
                .disabled(originalURL == nil)

                Button {
                    isAppearancePopoverPresented.toggle()
                } label: {
                    Image(systemName: "textformat")
                }
                .help(L10n.readerAppearanceButton)
                .popover(isPresented: $isAppearancePopoverPresented, arrowEdge: .bottom) {
                    readerAppearancePopover
                }

                Button {
                    isMetadataInspectorPresented.toggle()
                } label: {
                    Label(L10n.readerInspectorButton, systemImage: "sidebar.right")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .symbolVariant(isMetadataInspectorPresented ? .fill : .none)
                .help(L10n.readerInspectorButton)

                Menu {
                    Button {
                    } label: {
                        Label(L10n.articleCreateRuleCommand, systemImage: "slider.horizontal.3")
                    }
                    .disabled(true)

                    Button {
                        copyLink()
                    } label: {
                        Label(L10n.articleCopyLinkCommand, systemImage: "link")
                    }
                    .disabled(originalURL == nil)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help(L10n.articleCopyLinkCommand)
            }
        }
    }

    private var titleFontPreset: ReaderFontPreset {
        ReaderFontPreset.resolved(from: titleFontPresetRawValue)
    }

    private var bodyFontPreset: ReaderFontPreset {
        ReaderFontPreset.resolved(from: bodyFontPresetRawValue)
    }

    private var titleFontWeight: Font.Weight {
        readerTitleFontIsBold ? .bold : .semibold
    }

    private var bodyFontWeight: Font.Weight {
        readerBodyFontIsBold ? .bold : .regular
    }

    private var contentHeadingFontWeight: Font.Weight {
        readerBodyFontIsBold ? .bold : .semibold
    }

    private var clampedBodyFontSize: CGFloat {
        CGFloat(ReaderTypography.clampedBodyFontSize(readerBodyFontSize))
    }

    private var clampedLineSpacing: CGFloat {
        CGFloat(ReaderTypography.clampedLineSpacing(readerLineSpacing))
    }

    private var clampedTitleLineSpacing: CGFloat {
        CGFloat(ReaderTypography.clampedTitleLineSpacing(readerTitleLineSpacing))
    }

    private var clampedContentWidth: CGFloat {
        CGFloat(ReaderTypography.clampedContentWidth(readerContentWidth))
    }

    private var contentBlockSpacing: CGFloat {
        CGFloat(ReaderTypography.contentBlockSpacing)
    }

    private var imageTextDividerSpacing: CGFloat {
        CGFloat(ReaderTypography.imageTextDividerSpacing)
    }

    private var articleTopPadding: CGFloat {
        CGFloat(ReaderTypography.articleTopPadding)
    }

    private var articleBottomPadding: CGFloat {
        CGFloat(ReaderTypography.articleBottomPadding)
    }

    private var headerSpacing: CGFloat {
        CGFloat(ReaderTypography.headerSpacing)
    }

    private var footerTopPadding: CGFloat {
        CGFloat(ReaderTypography.footerTopPadding)
    }

    private var metadataFontSize: CGFloat {
        CGFloat(ReaderTypography.metadataFontSize(forBodyFontSize: readerBodyFontSize))
    }

    private var originalURL: URL? {
        guard let link = state.snapshot?.link else {
            return nil
        }

        return URL(string: link)
    }

    private var readerDisplayMode: ReaderDisplayMode {
        ReaderDisplayMode.resolved(from: readerDisplayModeRawValue)
    }

    private var offlineToolbarSystemImage: String {
        if isOfflineOperationInProgress {
            return "arrow.triangle.2.circlepath"
        }

        return state.snapshot?.offlineState.isAvailable == true ? "trash" : "arrow.down.circle"
    }

    private var offlineToolbarHelp: LocalizedStringKey {
        if isOfflineOperationInProgress {
            return L10n.readerOfflineSaving
        }

        return state.snapshot?.offlineState.isAvailable == true
            ? L10n.readerOfflineRemove
            : L10n.readerOfflineSave
    }

    @ViewBuilder
    private func readerContent(database: FeedivoDatabase) -> some View {
        if readerDisplayMode == .web, let originalURL {
            WebContentView(url: originalURL)
                .task(id: articleID) {
                    state.load(articleID: articleID, database: database)
                }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: contentBlockSpacing) {
                    if let snapshot = state.snapshot {
                        readerHeader(snapshot)

                        if isOfflineOperationInProgress || snapshot.offlineState.isAvailable {
                            offlineStatusNotice(snapshot)
                        }

                        ForEach(Array(state.preparedArticle.contentBlocks.enumerated()), id: \.element.id) { index, block in
                            VStack(alignment: .leading, spacing: imageTextDividerSpacing) {
                                contentBlock(block)

                                if shouldShowImageTextDivider(after: index, in: state.preparedArticle.contentBlocks) {
                                    readerSectionDivider
                                }
                            }
                        }

                        readerFooter(snapshot)
                    } else if state.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 28)
                    } else {
                        ContentUnavailableView(
                            "Artikel nicht gefunden",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text(state.errorMessage ?? "Der Artikel ist nicht mehr in der lokalen Datenbank vorhanden.")
                        )
                    }
                }
                .frame(maxWidth: clampedContentWidth, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, articleTopPadding)
                .padding(.bottom, articleBottomPadding)
            }
            .task(id: articleID) {
                state.load(articleID: articleID, database: database)
            }
            .id(articleID)
        }
    }

    private func readerHeader(_ snapshot: ArticleReaderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: headerSpacing) {
            if !state.preparedArticle.metadataText.isEmpty {
                Text(state.preparedArticle.metadataText)
                    .font(interfaceTextSize.font(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                openOriginal()
            } label: {
                Text(snapshot.title)
                    .font(titleFontPreset.font(
                        size: CGFloat(ReaderTypography.defaultTitleFontSize),
                        relativeTo: .largeTitle,
                        weight: titleFontWeight
                    ))
                    .fontWeight(titleFontWeight)
                    .lineSpacing(clampedTitleLineSpacing)
                    .textSelection(.enabled)
            }
            .buttonStyle(.plain)
            .disabled(originalURL == nil)
        }
    }

    private func offlineStatusNotice(_ snapshot: ArticleReaderSnapshot) -> some View {
        Label {
            Text(offlineStatusTitle(snapshot))
        } icon: {
            if isOfflineOperationInProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: snapshot.offlineState.isAvailable ? "checkmark.circle.fill" : "arrow.down.circle")
            }
        }
        .font(interfaceTextSize.font(size: 12, weight: .medium))
        .foregroundStyle(snapshot.offlineState.isAvailable ? .green : .secondary)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background((snapshot.offlineState.isAvailable ? Color.green : Color.secondary).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func offlineStatusTitle(_ snapshot: ArticleReaderSnapshot) -> LocalizedStringKey {
        if isOfflineOperationInProgress {
            return L10n.readerOfflineSaving
        }

        return snapshot.offlineState.isAvailable
            ? L10n.readerOfflineFeedContentAvailable
            : L10n.readerOfflineNotSaved
    }

    @ViewBuilder
    private func readerFooter(_ snapshot: ArticleReaderSnapshot) -> some View {
        if let link = snapshot.link, let url = URL(string: link) {
            VStack(alignment: .leading, spacing: 12) {
                Divider()

                Link(destination: url) {
                    Label(L10n.readerOpenOriginal, systemImage: "arrow.up.right")
                        .font(bodyFontPreset.font(size: max(metadataFontSize, 13), relativeTo: .callout))
                        .fontWeight(.semibold)
                }
            }
            .padding(.top, footerTopPadding)
        }
    }

    @ViewBuilder
    private func contentBlock(_ block: ReaderContentBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body, weight: bodyFontWeight))
                .fontWeight(bodyFontWeight)
                .lineSpacing(clampedLineSpacing)
                .textSelection(.enabled)
        case .heading(let text):
            Text(text)
                .font(bodyFontPreset.font(
                    size: min(clampedBodyFontSize + 5, CGFloat(ReaderTypography.defaultTitleFontSize - 2)),
                    relativeTo: .title3,
                    weight: contentHeadingFontWeight
                ))
                .fontWeight(contentHeadingFontWeight)
                .lineSpacing(clampedLineSpacing)
                .textSelection(.enabled)
        case .quote(let text):
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 3)

                Text(text)
                    .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body, weight: bodyFontWeight))
                    .fontWeight(bodyFontWeight)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineSpacing(clampedLineSpacing)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 2)
        case .listItem(let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: "•")
                    .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body, weight: bodyFontWeight))
                    .fontWeight(bodyFontWeight)
                    .foregroundStyle(.secondary)

                Text(text)
                    .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body, weight: bodyFontWeight))
                    .fontWeight(bodyFontWeight)
                    .lineSpacing(clampedLineSpacing)
                    .textSelection(.enabled)
            }
        case .image(let urlString):
            CachedRemoteImageView(url: URL(string: urlString)) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } placeholder: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(height: 180)
            }
        }
    }

    private var readerSectionDivider: some View {
        Rectangle()
            .fill(.secondary.opacity(ReaderTypography.readerDividerOpacity))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    private func shouldShowImageTextDivider(after index: Int, in blocks: [ReaderContentBlock]) -> Bool {
        guard blocks.indices.contains(index), isImageBlock(blocks[index]) else {
            return false
        }

        let nextIndex = blocks.index(after: index)
        guard blocks.indices.contains(nextIndex) else {
            return false
        }

        return !isImageBlock(blocks[nextIndex])
    }

    private func isImageBlock(_ block: ReaderContentBlock) -> Bool {
        if case .image = block {
            return true
        }

        return false
    }

    private var readerAppearancePopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.readerAppearanceTitle)
                .font(.headline)

            Picker(L10n.readerTitleFontPicker, selection: $titleFontPresetRawValue) {
                ForEach(ReaderFontPreset.allCases) { preset in
                    Text(preset.title)
                        .tag(preset.rawValue)
                }
            }
            .pickerStyle(.menu)

            Toggle(L10n.readerTitleFontBoldToggle, isOn: $readerTitleFontIsBold)

            Picker(L10n.readerBodyFontPicker, selection: $bodyFontPresetRawValue) {
                ForEach(ReaderFontPreset.allCases) { preset in
                    Text(preset.title)
                        .tag(preset.rawValue)
                }
            }
            .pickerStyle(.menu)

            Toggle(L10n.readerBodyFontBoldToggle, isOn: $readerBodyFontIsBold)

            typographySlider(
                L10n.readerBodyFontSizeSlider,
                value: $readerBodyFontSize,
                range: ReaderTypography.bodyFontSizeRange,
                displayedValue: ReaderTypography.clampedBodyFontSize(readerBodyFontSize)
            )

            typographySlider(
                L10n.readerTitleLineSpacingSlider,
                value: $readerTitleLineSpacing,
                range: ReaderTypography.titleLineSpacingRange,
                displayedValue: ReaderTypography.clampedTitleLineSpacing(readerTitleLineSpacing)
            )

            typographySlider(
                L10n.readerLineSpacingSlider,
                value: $readerLineSpacing,
                range: ReaderTypography.lineSpacingRange,
                displayedValue: ReaderTypography.clampedLineSpacing(readerLineSpacing)
            )

            typographySlider(
                L10n.readerContentWidthSlider,
                value: $readerContentWidth,
                range: ReaderTypography.contentWidthRange,
                displayedValue: ReaderTypography.clampedContentWidth(readerContentWidth),
                step: ReaderTypography.contentWidthStep
            )
        }
        .padding(16)
        .frame(width: 320)
    }

    private func typographySlider(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        displayedValue: Double,
        step: Double = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(displayedValue.formatted(.number.precision(.fractionLength(0))))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.caption)

            Slider(value: value, in: range, step: step)
        }
    }

    @MainActor
    private func toggleOffline(database: FeedivoDatabase) async {
        guard !isOfflineOperationInProgress else {
            return
        }

        isOfflineOperationInProgress = true
        await state.toggleOffline(database: database, offlineDownloadService: offlineDownloadService)
        isOfflineOperationInProgress = false
    }

    private func openOriginal() {
        guard let originalURL else {
            return
        }

        NSWorkspace.shared.open(originalURL)
    }

    private func copyLink() {
        guard let link = state.snapshot?.link?.trimmingCharacters(in: .whitespacesAndNewlines),
              !link.isEmpty
        else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
    }

    private func requestExportArticle() {
        guard let snapshot = state.snapshot,
              let database
        else {
            return
        }

        do {
            let tagNames = try TagStore(database: database).exportTagNames(
                articleID: snapshot.id,
                feedID: snapshot.feedID
            )
            articleExportRequest = ArticleExportRequest(
                snapshot: ArticleExportSnapshot(sqliteSnapshot: snapshot, tagNames: tagNames)
            )
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }
}
