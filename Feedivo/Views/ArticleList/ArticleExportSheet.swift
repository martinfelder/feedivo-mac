import SwiftUI

struct ArticleExportRequest: Identifiable {
    let id = UUID()
    let snapshot: ArticleExportSnapshot
}

private enum ArticleExportStep {
    case prepare
    case preview
}

struct ArticleExportSheet: View {
    let request: ArticleExportRequest
    let onClose: () -> Void

    @State private var step: ArticleExportStep = .prepare
    @State private var selectedFormat: ArticleExportFormat = .markdown
    @State private var includesMetadata = true
    @State private var isExporting = false

    private var options: ArticleExportOptions {
        ArticleExportOptions(format: selectedFormat, includesMetadata: includesMetadata)
    }

    private var exportText: String {
        ArticleExportService.text(for: request.snapshot, options: options)
    }

    private var previewText: String {
        ArticleExportService.previewText(for: request.snapshot, options: options)
    }

    private var defaultFilename: String {
        ArticleExportService.defaultFilename(for: request.snapshot, format: selectedFormat)
    }

    private var document: ArticleExportDocument {
        ArticleExportDocument(text: exportText)
    }

    private var contentSourceLabel: String {
        if request.snapshot.offlineState.isAvailable,
           request.snapshot.offlineContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return L10n.articleExportSourceOffline
        }

        if request.snapshot.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return L10n.articleExportSourceFeedContent
        }

        return L10n.articleExportSourceSummary
    }

    var body: some View {
        Group {
            switch step {
            case .prepare:
                prepareStep
            case .preview:
                previewStep
            }
        }
        .frame(width: 520)
        .padding(22)
        .fileExporter(
            isPresented: $isExporting,
            document: document,
            contentType: selectedFormat.contentType,
            defaultFilename: defaultFilename
        ) { _ in
            onClose()
        }
    }

    private var prepareStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sheetHeader(
                title: L10n.articleExportPrepareTitle,
                message: L10n.articleExportPrepareMessage
            )

            VStack(spacing: 0) {
                ForEach(ArticleExportFormat.allCases) { format in
                    ArticleExportFormatRow(
                        format: format,
                        isSelected: selectedFormat == format
                    ) {
                        selectedFormat = format
                    }

                    if format.id != ArticleExportFormat.allCases.last?.id {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator, lineWidth: 1)
            }

            Toggle(isOn: $includesMetadata) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.articleExportMetadataToggle)
                    Text(L10n.articleExportMetadataDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button(L10n.commonCancel) {
                    onClose()
                }
                Button(L10n.commonNext) {
                    step = .preview
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var previewStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sheetHeader(
                title: L10n.articleExportPreviewTitle,
                message: L10n.articleExportPreviewMessage
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(selectedFormat.localizedTitle)
                        .font(.headline)
                    Spacer()
                    Text(defaultFilename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    Text(previewText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 220)
            }
            .padding(12)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator, lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                exportSummaryRow(label: L10n.articleExportSummaryFormat, value: selectedFormat.localizedTitle)
                exportSummaryRow(label: L10n.articleExportSummaryMetadata, value: includesMetadata ? L10n.commonOn : L10n.commonOff)
                exportSummaryRow(label: L10n.articleExportSummarySource, value: contentSourceLabel)
            }

            HStack {
                Button(L10n.commonBack) {
                    step = .prepare
                }
                Spacer()
                Button(L10n.commonCancel) {
                    onClose()
                }
                Button(L10n.articleExportSaveButton) {
                    isExporting = true
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func sheetHeader(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func exportSummaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
            Spacer(minLength: 0)
        }
        .font(.caption)
    }
}

private struct ArticleExportFormatRow: View {
    let format: ArticleExportFormat
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(format.localizedTitle)
                            .font(.callout)
                            .foregroundStyle(.primary)
                        Text(".\(format.fileExtension)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(format.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension ArticleExportFormat {
    var localizedTitle: String {
        switch self {
        case .markdown:
            L10n.articleExportFormatMarkdown
        case .plainText:
            L10n.articleExportFormatPlainText
        case .html:
            L10n.articleExportFormatHTML
        }
    }

    var localizedDescription: String {
        switch self {
        case .markdown:
            L10n.articleExportFormatMarkdownDescription
        case .plainText:
            L10n.articleExportFormatPlainTextDescription
        case .html:
            L10n.articleExportFormatHTMLDescription
        }
    }
}
