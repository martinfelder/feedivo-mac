import SwiftUI

struct ReaderView: View {
    let article: Article

    @AppStorage("readerTitleFontPreset")
    private var titleFontPresetRawValue = ReaderFontPreset.system.rawValue

    @AppStorage("readerBodyFontPreset")
    private var bodyFontPresetRawValue = ReaderFontPreset.system.rawValue

    @State private var isAppearancePopoverPresented = false

    private var titleFontPreset: ReaderFontPreset {
        ReaderFontPreset.resolved(from: titleFontPresetRawValue)
    }

    private var bodyFontPreset: ReaderFontPreset {
        ReaderFontPreset.resolved(from: bodyFontPresetRawValue)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !metadataText.isEmpty {
                    Text(metadataText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(article.title)
                    .font(.system(.largeTitle, design: titleFontPreset.design))
                    .fontWeight(.bold)

                ForEach(Array(contentBlocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .paragraph(let text):
                        Text(text)
                            .font(.system(.body, design: bodyFontPreset.design))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    case .image(let urlString):
                        readerImage(urlString: urlString)
                    }
                }

                if let link = article.link, let url = URL(string: link) {
                    Link(L10n.readerOpenOriginal, destination: url)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding()
        }
        .navigationTitle(article.title)
        .toolbar {
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
        }
    }

    private var readerAppearancePopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.readerAppearanceTitle)
                .font(.headline)

            Picker(L10n.readerTitleFontPicker, selection: $titleFontPresetRawValue) {
                ForEach(ReaderFontPreset.allCases) { preset in
                    Text(preset.titleKey)
                        .tag(preset.rawValue)
                }
            }

            Picker(L10n.readerBodyFontPicker, selection: $bodyFontPresetRawValue) {
                ForEach(ReaderFontPreset.allCases) { preset in
                    Text(preset.titleKey)
                        .tag(preset.rawValue)
                }
            }
        }
        .padding(16)
        .frame(width: 260)
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
