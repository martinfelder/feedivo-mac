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
    let onRequestExportArticle: (Article) -> Void
    // preparedArticle wird asynchron und ausserhalb des MainActors gebaut
    // (siehe buildPreparedArticle()). Im init steht nur ein leerer Platzhalter,
    // damit der teure HTML-Parse nicht bei jeder Body-Eval des Parents
    // synchron in ReaderView.init laeuft (frueher via State(initialValue:)).
    @State private var preparedArticle: ReaderPreparedArticle = .empty
    @State private var isBuildingPreparedArticle = false
    // contentRevision treibt den .task(id:)-Refresh bei Inhaltsaenderungen
    // (Content/Summary/Offline …) an, ohne persistentModelID zu beruehren.
    @State private var contentRevision = 0

    init(
        article: Article,
        isMetadataInspectorPresented: Binding<Bool>,
        canSelectPreviousArticle: Bool = false,
        canSelectNextArticle: Bool = false,
        selectPreviousArticle: @escaping () -> Void = {},
        selectNextArticle: @escaping () -> Void = {},
        onRequestCreateRuleFromArticle: @escaping (Article) -> Void = { _ in },
        onRequestExportArticle: @escaping (Article) -> Void = { _ in }
    ) {
        self.article = article
        self._isMetadataInspectorPresented = isMetadataInspectorPresented
        self.canSelectPreviousArticle = canSelectPreviousArticle
        self.canSelectNextArticle = canSelectNextArticle
        self.selectPreviousArticle = selectPreviousArticle
        self.selectNextArticle = selectNextArticle
        self.onRequestCreateRuleFromArticle = onRequestCreateRuleFromArticle
        self.onRequestExportArticle = onRequestExportArticle
        self._preparedArticle = State(initialValue: ReaderPreparedArticle(
            input: ReaderArticleInput.makePreview(from: article)
        ))
        self._relationshipMetadata = State(initialValue: ReaderArticleRelationshipMetadata.make(from: article))
    }

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

    @State private var isAppearancePopoverPresented = false
    @State private var viewModel = ArticleViewModel()
    @State private var offlineDownloadService = OfflineDownloadService()
    @State private var isOfflineOperationInProgress = false
    @State private var readabilityArticle: ReadabilityExtractedArticle?
    @State private var readabilityRequestedURL: URL?
    @State private var readabilityLoadedURL: URL?
    @State private var isReadabilityExtractionInProgress = false
    @State private var readabilityFailureNotice: ReadabilityFailureNotice?
    @State private var relationshipMetadata = ReaderArticleRelationshipMetadata.empty
    @State private var isTagEditorPopoverPresented = false

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
        ArticleOriginalURLResolver.url(for: article)
    }

    private var shouldShowWebView: Bool {
        readerDisplayMode == .web && originalURL != nil
    }

    private var shouldShowReadabilityMode: Bool {
        readerDisplayMode == .readability && originalURL != nil
    }

    private var contentBlocks: [ReaderContentBlock] {
        preparedArticle.contentBlocks
    }

    private var readabilityContentBlocks: [ReaderContentBlock] {
        guard let readabilityArticle else {
            return []
        }

        return ReaderContentRenderer.blocks(
            summary: nil,
            content: readabilityArticle.normalizedContentHTML,
            fallbackImageURL: article.imageURL
        )
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
        currentRelationshipMetadata.folderName
    }

    private var sortedArticleTags: [ReaderArticleTagMetadata] {
        currentRelationshipMetadata.tags
    }

    private var currentRelationshipMetadata: ReaderArticleRelationshipMetadata {
        guard relationshipMetadata.articleID == article.persistentModelID else {
            return .empty
        }

        return relationshipMetadata
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
        .task(id: preparedArticleRefreshToken) {
            await buildPreparedArticle()
        }
        .task(id: article.persistentModelID) {
            await loadRelationshipMetadata()
        }
        .onAppear {
            startReadabilityExtractionIfNeeded()
        }
        // Leichte Inhalts-Signatur: Der Reader reagiert auf Status- und
        // Kurztext-Änderungen, ohne beim View-Aufbau die großen Textfelder
        // `content` und `offlineContent` zu faulten.
        .onChange(of: ReaderArticleObservationSignature.make(from: article)) {
            contentRevision += 1
        }
        .onChange(of: article.link) {
            contentRevision += 1
            resetReadabilityState()
            startReadabilityExtractionIfNeeded()
        }
        .onChange(of: readerDisplayModeRawValue) {
            startReadabilityExtractionIfNeeded()
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
                    onRequestExportArticle(article)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help(L10n.articleExportCommand)

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
        } else if shouldShowReadabilityMode, let originalURL {
            readabilityReader(originalURL: originalURL)
        } else {
            nativeReader
        }
    }

    private var nativeReader: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: contentBlockSpacing) {
                readerHeader

                if shouldShowOfflineStatusNotice {
                    offlineStatusNotice
                }

                if contentBlocks.isEmpty, isBuildingPreparedArticle {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }

                ForEach(Array(contentBlocks.enumerated()), id: \.element.id) { index, block in
                    VStack(alignment: .leading, spacing: imageTextDividerSpacing) {
                        readerContentBlock(block)

                        if shouldShowImageTextDivider(after: index, in: contentBlocks) {
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
        .id(article.persistentModelID)
    }

    private func readabilityReader(originalURL: URL) -> some View {
        ZStack(alignment: .topLeading) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: contentBlockSpacing) {
                    readerHeader
                    readabilityStatusNotice

                    let blocks = readabilityContentBlocks
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                        VStack(alignment: .leading, spacing: imageTextDividerSpacing) {
                            readerContentBlock(block)

                            if shouldShowImageTextDivider(after: index, in: blocks) {
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
            .id(article.persistentModelID)

            if readabilityRequestedURL == originalURL {
                ReadabilityExtractionView(url: originalURL) { result in
                    handleReadabilityExtraction(result, for: originalURL)
                }
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityHidden(true)
            }
        }
    }

    private var readabilityStatusNotice: some View {
        Label {
            VStack(alignment: .leading, spacing: 6) {
                Text(readabilityStatusTitle)

                if let readabilityFailureNotice {
                    Text(LocalizedStringKey(readabilityFailureNotice.detailKey))
                        .font(interfaceTextSize.font(size: 11))
                        .foregroundStyle(.secondary)
                } else if let message = readabilityStatusDetail {
                    Text(message)
                        .font(interfaceTextSize.font(size: 11))
                        .foregroundStyle(.secondary)
                }

                if readabilityFailureNotice != nil {
                    Button(L10n.readerReadabilityRetryButton) {
                        startReadabilityExtraction()
                    }
                    .controlSize(.small)
                    .disabled(isReadabilityExtractionInProgress || originalURL == nil)
                }
            }
        } icon: {
            if isReadabilityExtractionInProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: readabilityStatusSystemImage)
            }
        }
        .font(interfaceTextSize.font(size: 12, weight: .medium))
        .foregroundStyle(readabilityStatusForegroundStyle)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(readabilityStatusBackgroundStyle, in: RoundedRectangle(cornerRadius: 8))
    }

    private var readabilityStatusTitle: LocalizedStringKey {
        if isReadabilityExtractionInProgress {
            return L10n.readerReadabilityLoading
        }

        if readabilityFailureNotice != nil {
            return L10n.readerReadabilityFailed
        }

        if readabilityLoadedURL != nil {
            return L10n.readerReadabilityLoaded
        }

        return L10n.readerReadabilityIdleTitle
    }

    private var readabilityStatusDetail: LocalizedStringKey? {
        if isReadabilityExtractionInProgress {
            return L10n.readerReadabilityLoadingDescription
        }

        if readabilityFailureNotice != nil {
            return nil
        }

        if readabilityLoadedURL == nil {
            return L10n.readerReadabilityIdleDescription
        }

        return nil
    }

    private var readabilityStatusSystemImage: String {
        if readabilityFailureNotice != nil {
            return "exclamationmark.triangle.fill"
        }

        if readabilityLoadedURL != nil {
            return "doc.text.magnifyingglass"
        }

        return "arrow.down.doc"
    }

    private var readabilityStatusForegroundStyle: Color {
        if readabilityFailureNotice != nil {
            return .orange
        }

        if readabilityLoadedURL != nil {
            return .green
        }

        return .secondary
    }

    private var readabilityStatusBackgroundStyle: Color {
        readabilityStatusForegroundStyle.opacity(0.1)
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

            readerTagEditorButton
        }
    }

    private var readerMetadataChipHeight: CGFloat {
        interfaceTextSize.scaled(26)
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
        .frame(height: readerMetadataChipHeight)
        .background(.secondary.opacity(0.08), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.secondary.opacity(0.16), lineWidth: 1)
        }
    }

    private func readerTagChip(_ tag: ReaderArticleTagMetadata) -> some View {
        let tagColor = TagColorPalette.color(for: tag.colorHex)

        return Text("#\(tag.name)")
            .lineLimit(1)
            .font(interfaceTextSize.font(size: 12, weight: .semibold))
            .foregroundStyle(tagColor)
            .padding(.horizontal, 10)
            .frame(height: readerMetadataChipHeight)
            .background(tagColor.opacity(0.1), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tagColor.opacity(0.24), lineWidth: 1)
            }
    }

    private var readerTagEditorButton: some View {
        Button {
            isTagEditorPopoverPresented.toggle()
        } label: {
            Image(systemName: "plus")
                .font(interfaceTextSize.font(size: 12, weight: .bold))
                .frame(width: readerMetadataChipHeight, height: readerMetadataChipHeight)
        }
        .buttonStyle(.plain)
        .foregroundStyle(SidebarStyle.primaryText)
        .background(.secondary.opacity(0.08), in: Circle())
        .overlay {
            Circle()
                .stroke(.secondary.opacity(0.16), lineWidth: 1)
        }
        .help(L10n.readerInspectorNewTag)
        .popover(isPresented: $isTagEditorPopoverPresented) {
            ReaderInlineTagEditorPopover(
                article: article,
                onMetadataChange: refreshRelationshipMetadata
            )
            .frame(width: 320)
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
                Color.clear
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: leadImageMaxHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func startReadabilityExtraction() {
        guard let originalURL else {
            return
        }

        readabilityArticle = nil
        readabilityLoadedURL = nil
        readabilityFailureNotice = nil
        isReadabilityExtractionInProgress = true
        readabilityRequestedURL = originalURL
    }

    private func startReadabilityExtractionIfNeeded() {
        guard ReadabilityLoadDecision.shouldStartExtraction(
            mode: readerDisplayMode,
            originalURL: originalURL,
            requestedURL: readabilityRequestedURL,
            loadedURL: readabilityLoadedURL,
            isInProgress: isReadabilityExtractionInProgress
        ) else {
            return
        }

        startReadabilityExtraction()
    }

    private func handleReadabilityExtraction(_ result: Result<ReadabilityExtractedArticle, Error>, for url: URL) {
        guard readabilityRequestedURL == url else {
            return
        }

        readabilityRequestedURL = nil
        isReadabilityExtractionInProgress = false

        switch result {
        case .success(let article):
            readabilityArticle = article
            readabilityLoadedURL = url
            readabilityFailureNotice = nil
        case .failure(let error):
            readabilityArticle = nil
            readabilityLoadedURL = nil
            readabilityFailureNotice = ReadabilityFailureNotice.make(for: error)
        }
    }

    private func resetReadabilityState() {
        readabilityArticle = nil
        readabilityRequestedURL = nil
        readabilityLoadedURL = nil
        isReadabilityExtractionInProgress = false
        readabilityFailureNotice = nil
    }

    private var preparedArticleRefreshToken: ReaderRefreshToken {
        ReaderRefreshToken(articleID: article.persistentModelID, revision: contentRevision)
    }

    @MainActor
    private func buildPreparedArticle() async {
        let token = preparedArticleRefreshToken

        let previewInput = ReaderArticleInput.makePreview(from: article)
        preparedArticle = ReaderPreparedArticle(input: previewInput)
        isBuildingPreparedArticle = true
        await Task.yield()

        let input = ReaderArticleInput.make(from: article)

        // Hebel 5: Bereits geparsten Artikel aus dem Cache übernehmen, wenn
        // sich die inhaltsbestimmenden Felder nicht geändert haben (z. B.
        // Vor-/Zurück-Navigation). Dann entfällt der Parse komplett.
        if let cached = ReaderPreparedArticleCache.shared.prepared(for: input) {
            guard !Task.isCancelled, token == preparedArticleRefreshToken else {
                return
            }
            preparedArticle = cached
            isBuildingPreparedArticle = false
            return
        }

        // Parse ausserhalb des MainActors: reine Datenverarbeitung ohne UI-/
        // Modellzugriff. Der MainThread bleibt beim Artikelwechsel frei.
        let prepared = await Task.detached(priority: .userInitiated) {
            ReaderPreparedArticle(input: input)
        }.value

        // Veraltete Ergebnisse verwerfen, wenn Artikel oder Inhalt seit dem
        // Start gewechselt wurde (.task(id:) bricht den alten Task ab).
        guard !Task.isCancelled, token == preparedArticleRefreshToken else {
            isBuildingPreparedArticle = false
            return
        }

        ReaderPreparedArticleCache.shared.store(prepared, for: input)
        preparedArticle = prepared
        isBuildingPreparedArticle = false
    }

    @MainActor
    private func loadRelationshipMetadata() async {
        let articleID = article.persistentModelID

        guard !Task.isCancelled, articleID == article.persistentModelID else {
            return
        }

        relationshipMetadata = ReaderArticleRelationshipMetadata.make(from: article)
    }

    @MainActor
    private func refreshRelationshipMetadata() {
        relationshipMetadata = ReaderArticleRelationshipMetadata.make(from: article)
    }

    @MainActor
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

        try? modelContext.save()
        // Offline-Inhalt hat sich geaendert — asynchroner Rebuild ueber
        // contentRevision (die .onChange-Handler bumpen ohnehin; expliziter
        // Bump ist idempotent und robust gegen Reihenfolge).
        contentRevision += 1
        isOfflineOperationInProgress = false
    }
}

private struct ReaderInlineTagEditorPopover: View {
    @Environment(\.interfaceTextSize) private var interfaceTextSize
    @Environment(\.modelContext) private var modelContext

    let article: Article
    let onMetadataChange: () -> Void

    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var newTagName = ""
    @State private var newTagColorHex = TagColorPalette.defaultColorHex

    private var sortedAllTags: [Tag] {
        allTags.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.readerInspectorTags)
                .font(interfaceTextSize.font(size: ArticleInspectorTypography.sectionTitleFontSize, weight: .semibold))
                .foregroundStyle(SidebarStyle.primaryText)

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
        .padding(14)
    }

    private var tagCreator: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.readerInspectorNewTag)
                .font(interfaceTextSize.font(size: ArticleInspectorTypography.labelFontSize, weight: .bold))
                .foregroundStyle(SidebarStyle.secondaryText)

            HStack(spacing: 6) {
                TextField(L10n.readerInspectorAddTagPlaceholder, text: $newTagName)
                    .textFieldStyle(.plain)
                    .font(interfaceTextSize.font(size: ArticleInspectorTypography.controlFontSize))
                    .padding(.horizontal, 9)
                    .frame(height: interfaceTextSize.scaled(30))
                    .readerInlineTagControl()
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
    }

    private func tagTogglePill(_ tag: Tag) -> some View {
        let tagColor = TagColorPalette.color(for: tag.colorHex)
        let isActive = (article.tags ?? []).contains { $0.id == tag.id }

        return Button {
            toggleTag(tag)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(tagColor)
                    .frame(width: 7, height: 7)

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
        if (article.tags ?? []).contains(where: { $0.id == tag.id }) {
            ArticleMetadataEditor.removeTag(tag, from: article, context: modelContext)
        } else {
            ArticleMetadataEditor.addTag(
                named: tag.name,
                to: article,
                availableTags: allTags,
                context: modelContext
            )
        }
        onMetadataChange()
    }

    private func addTag() {
        ArticleMetadataEditor.addTag(
            named: newTagName,
            colorHex: newTagColorHex,
            to: article,
            availableTags: allTags,
            context: modelContext
        )
        newTagName = ""
        onMetadataChange()
    }
}

private extension View {
    func readerInlineTagControl(cornerRadius: CGFloat = 8) -> some View {
        self
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SidebarStyle.separator, lineWidth: 1)
            }
    }
}

// Treiber fuer .task(id:): wechselt bei Artikelwechsel (persistentModelID)
// oder Inhaltsaenderung (contentRevision). Equatable, damit SwiftUI den Task
// nur bei echten Wechseln neu startet.
private struct ReaderRefreshToken: Equatable {
    let articleID: PersistentIdentifier
    let revision: Int
}

struct ReaderArticleTagMetadata: Identifiable, Equatable {
    let id: UUID
    let name: String
    let colorHex: String

    init(tag: Tag) {
        self.id = tag.id
        self.name = tag.name
        self.colorHex = tag.colorHex
    }
}

struct ReaderArticleRelationshipMetadata: Equatable {
    static let empty = ReaderArticleRelationshipMetadata(
        articleID: nil,
        folderName: nil,
        tags: []
    )

    let articleID: PersistentIdentifier?
    let folderName: String?
    let tags: [ReaderArticleTagMetadata]

    static func make(from article: Article) -> ReaderArticleRelationshipMetadata {
        ReaderArticleRelationshipMetadata(
            articleID: article.persistentModelID,
            folderName: FeedFolderOrganizer.normalizedFolderName(article.feed?.folderName),
            tags: (article.tags ?? []).sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }.map(ReaderArticleTagMetadata.init)
        )
    }
}
