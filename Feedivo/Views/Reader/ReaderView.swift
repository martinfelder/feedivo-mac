import SwiftUI
import SwiftData

struct ReaderView: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize
    @Environment(\.modelContext) private var modelContext

    let article: Article
    @Binding var isMetadataInspectorPresented: Bool
    let canSelectPreviousArticle: Bool
    let canSelectNextArticle: Bool
    let selectPreviousArticle: () -> Void
    let selectNextArticle: () -> Void
    let onRequestCreateRuleFromArticle: (Article) -> Void
    @State private var preparedArticle: ReaderPreparedArticle

    init(
        article: Article,
        isMetadataInspectorPresented: Binding<Bool>,
        canSelectPreviousArticle: Bool = false,
        canSelectNextArticle: Bool = false,
        selectPreviousArticle: @escaping () -> Void = {},
        selectNextArticle: @escaping () -> Void = {},
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void = { _ in }
    ) {
        self.article = article
        self._isMetadataInspectorPresented = isMetadataInspectorPresented
        self.canSelectPreviousArticle = canSelectPreviousArticle
        self.canSelectNextArticle = canSelectNextArticle
        self.selectPreviousArticle = selectPreviousArticle
        self.selectNextArticle = selectNextArticle
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
        self._preparedArticle = State(initialValue: ReaderPreparedArticle(article: article))
    }

    @AppStorage("readerTitleFontPreset")
    private var titleFontPresetRawValue = ReaderFontPreset.system.rawValue

    @AppStorage("readerBodyFontPreset")
    private var bodyFontPresetRawValue = ReaderFontPreset.system.rawValue

    @AppStorage("readerTitleFontIsBold")
    private var readerTitleFontIsBold = ReaderTypography.defaultTitleFontIsBold

    @AppStorage("readerBodyFontIsBold")
    private var readerBodyFontIsBold = ReaderTypography.defaultBodyFontIsBold

    @AppStorage("readerBodyFontSize")
    private var readerBodyFontSize = ReaderTypography.defaultBodyFontSize

    @AppStorage("readerLineSpacing")
    private var readerLineSpacing = ReaderTypography.defaultLineSpacing

    @AppStorage("readerTitleLineSpacing")
    private var readerTitleLineSpacing = ReaderTypography.defaultTitleLineSpacing

    @AppStorage("readerContentWidth")
    private var readerContentWidth = ReaderTypography.defaultContentWidth

    @AppStorage(ReaderDisplayMode.storageKey)
    private var readerDisplayModeRawValue = ReaderDisplayMode.defaultMode.rawValue

    @State private var isAppearancePopoverPresented = false
    @State private var viewModel = ArticleViewModel()
    @State private var offlineDownloadService = OfflineDownloadService()
    @State private var isOfflineOperationInProgress = false

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

    private var articleTopPadding: CGFloat {
        CGFloat(ReaderTypography.articleTopPadding)
    }

    private var articleBottomPadding: CGFloat {
        CGFloat(ReaderTypography.articleBottomPadding)
    }

    private var headerSpacing: CGFloat {
        CGFloat(ReaderTypography.headerSpacing)
    }

    private var contentBlockSpacing: CGFloat {
        CGFloat(ReaderTypography.contentBlockSpacing)
    }

    private var imageTextDividerSpacing: CGFloat {
        CGFloat(ReaderTypography.imageTextDividerSpacing)
    }

    private var leadImageMaxHeight: CGFloat {
        CGFloat(ReaderTypography.leadImageMaxHeight)
    }

    private var footerTopPadding: CGFloat {
        CGFloat(ReaderTypography.footerTopPadding)
    }

    private var metadataFontSize: CGFloat {
        CGFloat(ReaderTypography.metadataFontSize(forBodyFontSize: readerBodyFontSize))
    }

    private var readerDisplayMode: ReaderDisplayMode {
        ReaderDisplayMode.resolved(from: readerDisplayModeRawValue)
    }

    private var originalURL: URL? {
        preparedArticle.originalURL
    }

    private var shouldShowWebView: Bool {
        readerDisplayMode == .web && originalURL != nil
    }

    private var contentBlocks: [ReaderContentBlock] {
        preparedArticle.contentBlocks
    }

    private var shouldShowOfflineStatusNotice: Bool {
        isOfflineOperationInProgress || article.offlineState != .none
    }

    private var offlineActionTitle: LocalizedStringKey {
        article.offlineState.isAvailable ? L10n.readerOfflineRemove : L10n.readerOfflineSave
    }

    private var offlineActionSystemImage: String {
        if isOfflineOperationInProgress {
            return "arrow.down.circle"
        }

        return article.offlineState.isAvailable ? "checkmark.circle.fill" : "arrow.down.circle"
    }

    private var metadataText: String {
        preparedArticle.metadataText
    }

    private var normalizedFolderName: String? {
        FeedFolderOrganizer.normalizedFolderName(article.feed?.folderName)
    }

    private var sortedArticleTags: [Tag] {
        article.tags.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var hasVisibleArticleMetadata: Bool {
        normalizedFolderName != nil || !sortedArticleTags.isEmpty
    }

    var body: some View {
        readerContent
        .inspector(isPresented: $isMetadataInspectorPresented) {
            ArticleMetadataInspectorView(
                article: article,
                close: {
                    isMetadataInspectorPresented = false
                },
                isOfflineOperationInProgress: isOfflineOperationInProgress,
                toggleOfflineAvailability: {
                    Task {
                        await toggleOfflineAvailability()
                    }
                }
            )
            .inspectorColumnWidth(min: 280, ideal: 318, max: 360)
        }
        .onChange(of: article.persistentModelID) {
            preparedArticle = ReaderPreparedArticle(article: article)
        }
        .navigationTitle(article.title)
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
                    _ = viewModel.openOriginal(article)
                } label: {
                    Image(systemName: "safari")
                }
                .help(L10n.articleOpenOriginalCommand)
                .disabled(originalURL == nil)

                Button {
                    Task {
                        await toggleOfflineAvailability()
                    }
                } label: {
                    if isOfflineOperationInProgress {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: offlineActionSystemImage)
                    }
                }
                .help(offlineActionTitle)
                .disabled(isOfflineOperationInProgress)

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
                        onRequestCreateRuleFromArticle(article)
                    } label: {
                        Label(L10n.articleCreateRuleCommand, systemImage: "slider.horizontal.3")
                    }

                    Button {
                        _ = viewModel.copyLink(article)
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

    @ViewBuilder
    private var readerContent: some View {
        if shouldShowWebView, let originalURL {
            WebContentView(url: originalURL)
        } else {
            nativeReader
        }
    }

    private var nativeReader: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: contentBlockSpacing) {
                readerHeader

                if shouldShowOfflineStatusNotice {
                    offlineStatusNotice
                }

                ForEach(contentBlocks.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: imageTextDividerSpacing) {
                        readerContentBlock(contentBlocks[index])

                        if shouldShowImageTextDivider(after: index) {
                            readerSectionDivider
                        }
                    }
                }

                readerFooter
            }
            .frame(maxWidth: clampedContentWidth, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, articleTopPadding)
            .padding(.bottom, articleBottomPadding)
        }
    }

    private var offlineStatusNotice: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(offlineStatusTitle)

                if let message = offlineStatusDetail {
                    Text(message)
                        .font(interfaceTextSize.font(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: offlineStatusSystemImage)
        }
        .font(interfaceTextSize.font(size: 12, weight: .medium))
        .foregroundStyle(offlineStatusForegroundStyle)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(offlineStatusBackgroundStyle, in: RoundedRectangle(cornerRadius: 8))
    }

    private var offlineStatusTitle: LocalizedStringKey {
        if isOfflineOperationInProgress {
            return L10n.readerOfflineSaving
        }

        switch article.offlineState {
        case .fullText:
            return L10n.readerOfflineFullTextAvailable
        case .feedContent:
            return L10n.readerOfflineFeedContentAvailable
        case .failed:
            return L10n.readerOfflineFailed
        case .none:
            return L10n.readerOfflineNotSaved
        }
    }

    private var offlineStatusDetail: String? {
        if article.offlineState == .failed {
            return article.offlineErrorMessage
        }

        guard let savedAt = article.offlineSavedAt else {
            return nil
        }

        return savedAt.feedivoRelativeDisplay
    }

    private var offlineStatusSystemImage: String {
        if isOfflineOperationInProgress {
            return "arrow.down.circle"
        }

        switch article.offlineState {
        case .fullText, .feedContent:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .none:
            return "arrow.down.circle"
        }
    }

    private var offlineStatusForegroundStyle: Color {
        switch article.offlineState {
        case .failed:
            return .orange
        case .fullText, .feedContent:
            return .green
        case .none:
            return .secondary
        }
    }

    private var offlineStatusBackgroundStyle: Color {
        offlineStatusForegroundStyle.opacity(0.1)
    }

    private var readerHeader: some View {
        VStack(alignment: .leading, spacing: headerSpacing) {
            if !metadataText.isEmpty {
                Text(metadataText)
                    .font(interfaceTextSize.font(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            readerTitle

            if hasVisibleArticleMetadata {
                readerArticleMetadata
            }
        }
    }

    @ViewBuilder
    private var readerFooter: some View {
        if let link = article.link, let url = URL(string: link) {
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

    private func readerParagraph(_ text: String) -> some View {
        Text(text)
            .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body, weight: bodyFontWeight))
            .fontWeight(bodyFontWeight)
            .lineSpacing(clampedLineSpacing)
            .textSelection(.enabled)
    }

    private func readerQuote(_ text: String) -> some View {
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
    }

    private func readerListItem(_ text: String) -> some View {
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
    }

    @ViewBuilder
    private func readerContentBlock(_ block: ReaderContentBlock) -> some View {
        switch block {
        case .paragraph(let text):
            readerParagraph(text)
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
            readerQuote(text)
        case .listItem(let text):
            readerListItem(text)
        case .image(let urlString):
            readerImage(urlString: urlString)
        }
    }

    private var readerSectionDivider: some View {
        Rectangle()
            .fill(.secondary.opacity(ReaderTypography.readerDividerOpacity))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    private func shouldShowImageTextDivider(after index: Int) -> Bool {
        guard contentBlocks.indices.contains(index), isImageBlock(contentBlocks[index]) else {
            return false
        }

        let nextIndex = contentBlocks.index(after: index)
        guard contentBlocks.indices.contains(nextIndex) else {
            return false
        }

        return !isImageBlock(contentBlocks[nextIndex])
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

    @ViewBuilder
    private var readerTitle: some View {
        if originalURL != nil {
            Button {
                _ = viewModel.openOriginal(article)
            } label: {
                readerTitleText
            }
            .buttonStyle(.plain)
            .help(L10n.articleOpenOriginalCommand)
        } else {
            readerTitleText
        }
    }

    private var readerTitleText: some View {
        Text(article.title)
            .font(titleFontPreset.font(
                size: CGFloat(ReaderTypography.defaultTitleFontSize),
                relativeTo: .largeTitle,
                weight: titleFontWeight
            ))
            .fontWeight(titleFontWeight)
            .lineSpacing(clampedTitleLineSpacing)
            .textSelection(.enabled)
    }

    private var readerArticleMetadata: some View {
        FlowLayout(spacing: 8) {
            if let normalizedFolderName {
                readerFolderChip(normalizedFolderName)
            }

            ForEach(sortedArticleTags) { tag in
                readerTagChip(tag)
            }
        }
    }

    private func readerFolderChip(_ folderName: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.caption2)

            Text(folderName)
                .lineLimit(1)
        }
        .font(interfaceTextSize.font(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.secondary.opacity(0.08), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.secondary.opacity(0.16), lineWidth: 1)
        }
    }

    private func readerTagChip(_ tag: Tag) -> some View {
        let tagColor = TagColorPalette.color(for: tag.colorHex)

        return Text("#\(tag.name)")
            .lineLimit(1)
            .font(interfaceTextSize.font(size: 12, weight: .semibold))
            .foregroundStyle(tagColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tagColor.opacity(0.1), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tagColor.opacity(0.24), lineWidth: 1)
            }
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
                Text("\(Int(displayedValue)) px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(value: value, in: range, step: step)
        }
    }

    @ViewBuilder
    private func readerImage(urlString: String) -> some View {
        if let url = URL(string: urlString) {
            CachedRemoteImageView(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                ProgressView()
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: leadImageMaxHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func toggleOfflineAvailability() async {
        guard !isOfflineOperationInProgress else {
            return
        }

        isOfflineOperationInProgress = true

        if article.offlineState.isAvailable {
            offlineDownloadService.removeOfflineContent(from: article)
        } else {
            await offlineDownloadService.saveForOffline(article)
        }

        preparedArticle = ReaderPreparedArticle(article: article)
        try? modelContext.save()
        isOfflineOperationInProgress = false
    }
}
