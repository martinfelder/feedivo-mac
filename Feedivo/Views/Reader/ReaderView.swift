import SwiftUI

struct ReaderView: View {
    let article: Article
    let canSelectPreviousArticle: Bool
    let canSelectNextArticle: Bool
    let selectPreviousArticle: () -> Void
    let selectNextArticle: () -> Void

    init(
        article: Article,
        canSelectPreviousArticle: Bool = false,
        canSelectNextArticle: Bool = false,
        selectPreviousArticle: @escaping () -> Void = {},
        selectNextArticle: @escaping () -> Void = {}
    ) {
        self.article = article
        self.canSelectPreviousArticle = canSelectPreviousArticle
        self.canSelectNextArticle = canSelectNextArticle
        self.selectPreviousArticle = selectPreviousArticle
        self.selectNextArticle = selectNextArticle
    }

    @AppStorage("readerTitleFontPreset")
    private var titleFontPresetRawValue = ReaderFontPreset.system.rawValue

    @AppStorage("readerBodyFontPreset")
    private var bodyFontPresetRawValue = ReaderFontPreset.system.rawValue

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
    @State private var isMetadataInspectorPresented = false
    @State private var viewModel = ArticleViewModel()

    private var titleFontPreset: ReaderFontPreset {
        ReaderFontPreset.resolved(from: titleFontPresetRawValue)
    }

    private var bodyFontPreset: ReaderFontPreset {
        ReaderFontPreset.resolved(from: bodyFontPresetRawValue)
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

    private var metadataFontSize: CGFloat {
        CGFloat(ReaderTypography.metadataFontSize(forBodyFontSize: readerBodyFontSize))
    }

    private var readerDisplayMode: ReaderDisplayMode {
        ReaderDisplayMode.resolved(from: readerDisplayModeRawValue)
    }

    private var originalURL: URL? {
        viewModel.originalURL(for: article)
    }

    private var shouldShowWebView: Bool {
        readerDisplayMode == .web && originalURL != nil
    }

    private var contentBlocks: [ReaderContentBlock] {
        ReaderContentRenderer.blocks(
            summary: article.summary,
            content: article.content,
            fallbackImageURL: article.imageURL
        )
    }

    private var metadataText: String {
        ReaderMetadataFormatter.metadataParts(
            feedName: article.feed?.title,
            readingTime: ReaderMetadataFormatter.readingTimeText(
                content: article.content,
                summary: article.summary
            ),
            publishedAt: article.publishedAt
        )
        .joined(separator: " · ")
    }

    var body: some View {
        readerWithOptionalInspector
        .navigationTitle(article.title)
        .toolbar {
            ToolbarItemGroup {
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
            }

            ToolbarItem {
                Button {
                    _ = viewModel.copyLink(article)
                } label: {
                    Image(systemName: "link")
                }
                .help(L10n.articleCopyLinkCommand)
                .disabled(originalURL == nil)
            }

            ToolbarItem {
                Button {
                    _ = viewModel.openOriginal(article)
                } label: {
                    Image(systemName: "safari")
                }
                .help(L10n.articleOpenOriginalCommand)
                .disabled(originalURL == nil)
            }

            ToolbarItem {
                Picker(L10n.readerDisplayModePicker, selection: $readerDisplayModeRawValue) {
                    ForEach(ReaderDisplayMode.allCases) { mode in
                        Text(mode.titleKey)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .help(L10n.readerDisplayModeToggleHelp)
                .disabled(originalURL == nil)
            }

            ToolbarItem {
                Button {
                    isAppearancePopoverPresented.toggle()
                } label: {
                    Image(systemName: "textformat")
                }
                .help(L10n.readerAppearanceButton)
                .popover(isPresented: $isAppearancePopoverPresented, arrowEdge: .bottom) {
                    readerAppearancePopover
                }
            }

            ToolbarItem {
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
            }
        }
    }

    @ViewBuilder
    private var readerWithOptionalInspector: some View {
        if isMetadataInspectorPresented {
            HStack(spacing: 0) {
                readerContent

                Divider()

                ArticleMetadataInspectorView(article: article) {
                    isMetadataInspectorPresented = false
                }
            }
        } else {
            readerContent
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !metadataText.isEmpty {
                    Text(metadataText)
                        .font(bodyFontPreset.font(size: metadataFontSize, relativeTo: .caption))
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                readerTitle

                ForEach(Array(contentBlocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .paragraph(let text):
                        readerParagraph(text)
                    case .heading(let text):
                        Text(text)
                            .font(bodyFontPreset.font(
                                size: min(clampedBodyFontSize + 5, CGFloat(ReaderTypography.defaultTitleFontSize - 2)),
                                relativeTo: .title3
                            ))
                            .fontWeight(.semibold)
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

                if let link = article.link, let url = URL(string: link) {
                    Link(L10n.readerOpenOriginal, destination: url)
                }
            }
            .frame(maxWidth: clampedContentWidth, alignment: .leading)
            .padding()
        }
    }

    private func readerParagraph(_ text: String) -> some View {
        Text(text)
            .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body))
            .lineSpacing(clampedLineSpacing)
            .textSelection(.enabled)
    }

    private func readerQuote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(.secondary.opacity(0.35))
                .frame(width: 3)

            Text(text)
                .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body))
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
                .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body))
                .foregroundStyle(.secondary)

            Text(text)
                .font(bodyFontPreset.font(size: clampedBodyFontSize, relativeTo: .body))
                .lineSpacing(clampedLineSpacing)
                .textSelection(.enabled)
        }
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

            Picker(L10n.readerBodyFontPicker, selection: $bodyFontPresetRawValue) {
                ForEach(ReaderFontPreset.allCases) { preset in
                    Text(preset.title)
                        .tag(preset.rawValue)
                }
            }
            .pickerStyle(.menu)

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
                relativeTo: .largeTitle
            ))
            .fontWeight(.bold)
            .lineSpacing(clampedTitleLineSpacing)
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
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    EmptyView()
                case .empty:
                    ProgressView()
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
