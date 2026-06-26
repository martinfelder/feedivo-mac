import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct ArticleExportRequest: Identifiable {
    let id = UUID()
    let snapshot: ArticleExportSnapshot
}

private enum ArticleExportStep {
    case prepare
    case preview
}

private enum ArticleExportStatus: Equatable {
    case idle
    case preparingDocument
    case downloadingImage(current: Int, total: Int)
    case creatingArchive
    case openingSaveDialog
}

struct ArticleExportSheet: View {
    let request: ArticleExportRequest
    let onClose: () -> Void

    @State private var step: ArticleExportStep = .prepare
    @State private var selectedFormat: ArticleExportFormat = .markdown
    @State private var includesMetadata = true
    @State private var includesOfflineImages = false
    @State private var isExporting = false
    @State private var preparedPackage: ArticleExportPackage?
    @State private var exportStatus: ArticleExportStatus = .idle

    private var options: ArticleExportOptions {
        ArticleExportOptions(format: selectedFormat, includesMetadata: includesMetadata)
    }

    private var exportText: String {
        ArticleExportService.text(for: request.snapshot, options: options)
    }

    private var previewText: String {
        if let preparedPackage {
            return ArticleExportService.previewText(from: preparedPackage.text)
        }

        return ArticleExportService.previewText(for: request.snapshot, options: options)
    }

    private var defaultFilename: String {
        if let preparedPackage {
            return preparedPackage.filename
        }

        return ArticleExportService.defaultFilename(for: request.snapshot, format: selectedFormat)
    }

    private var document: ArticleExportDocument {
        if preparedPackage?.contentType == .zipArchive,
           let archiveData = preparedPackage?.archiveData {
            return ArticleExportDocument(data: archiveData)
        }

        return ArticleExportDocument(text: preparedPackage?.text ?? exportText)
    }

    private var canIncludeOfflineImages: Bool {
        selectedFormat == .markdown || selectedFormat == .html
    }

    private var exportContentType: UTType {
        preparedPackage?.contentType == .zipArchive ? .zip : selectedFormat.contentType
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
        .background(.background)
        .fileExporter(
            isPresented: $isExporting,
            document: document,
            contentType: exportContentType,
            defaultFilename: defaultFilename
        ) { _ in
            exportStatus = .idle
            onClose()
        }
    }

    private var prepareStep: some View {
        VStack(spacing: 0) {
            sheetHeader(
                stepText: stepText(current: 1),
                title: L10n.articleExportPrepareTitle,
                message: L10n.articleExportPrepareMessage
            )

            VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 0) {
                ForEach(ArticleExportFormat.allCases) { format in
                    ArticleExportFormatRow(
                        format: format,
                        isSelected: selectedFormat == format
                    ) {
                        selectedFormat = format
                        preparedPackage = nil
                        if format == .plainText {
                            includesOfflineImages = false
                        }
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

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.articleExportMetadataToggle)
                        .font(.callout)
                    Text(L10n.articleExportMetadataDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Toggle("", isOn: $includesMetadata)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(L10n.articleExportMetadataToggle)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .top) {
                Divider()
            }
            .overlay(alignment: .bottom) {
                Divider()
            }

            if canIncludeOfflineImages {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.articleExportOfflineImagesToggle)
                            .font(.callout)
                        Text(L10n.articleExportOfflineImagesDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Toggle("", isOn: $includesOfflineImages)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel(L10n.articleExportOfflineImagesToggle)
                }
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    Divider()
                }
            }

            exportStatusView

            HStack {
                Spacer()
                Button(L10n.commonCancel) {
                    onClose()
                }
                Button(L10n.commonNext) {
                    preparePackageAndShowPreview()
                }
                .disabled(exportStatus.isBusy)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            }
            .padding(22)
        }
    }

    private var previewStep: some View {
        VStack(spacing: 0) {
            sheetHeader(
                stepText: stepText(current: 2),
                title: L10n.articleExportPreviewTitle,
                message: L10n.articleExportPreviewMessage
            )

            VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(previewHeadline)
                        .font(.headline)
                    Spacer()
                    Text(defaultFilename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider()

                renderedPreview
                    .frame(height: 220)
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator, lineWidth: 1)
            }

            exportSummary
            exportStatusView

            HStack {
                Button(L10n.commonBack) {
                    preparedPackage = nil
                    step = .prepare
                }
                Spacer()
                Button(L10n.commonCancel) {
                    onClose()
                }
                Button(L10n.articleExportSaveButton) {
                    exportStatus = .openingSaveDialog
                    isExporting = true
                }
                .disabled(exportStatus.isBusy)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            }
            .padding(22)
        }
    }

    private var previewHeadline: String {
        selectedFormat.localizedPreviewTitle
    }

    @ViewBuilder
    private var renderedPreview: some View {
        switch selectedFormat {
        case .markdown:
            ArticleExportHTMLPreview(
                html: ArticleExportPreviewRenderer.htmlForMarkdownPreview(
                    previewText,
                    assets: preparedPackage?.assets ?? []
                )
            )
        case .plainText:
            ScrollView {
                Text(previewText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        case .html:
            ArticleExportHTMLPreview(
                html: ArticleExportPreviewRenderer.htmlForHTMLPreview(
                    preparedPackage?.text ?? exportText,
                    assets: preparedPackage?.assets ?? []
                )
            )
        }
    }

    private var exportSummary: some View {
        VStack(spacing: 0) {
            exportSummaryRow(label: L10n.articleExportSummaryFormat, value: selectedFormat.localizedTitle)
            Divider()
                .padding(.leading, 92)
            exportSummaryRow(label: L10n.articleExportSummaryMetadata, value: includesMetadata ? L10n.commonOn : L10n.commonOff)
            Divider()
                .padding(.leading, 92)
            exportSummaryRow(label: L10n.articleExportSummarySource, value: contentSourceLabel)
            if let preparedPackage, preparedPackage.contentType == .zipArchive {
                Divider()
                    .padding(.leading, 92)
                exportSummaryRow(label: L10n.articleExportSummaryImages, value: imageSummary(for: preparedPackage))
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var exportStatusView: some View {
        if let statusText = exportStatus.localizedDescription {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)
        }
    }

    private func sheetHeader(stepText: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(stepText)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func stepText(current: Int) -> String {
        current == 1 ? L10n.articleExportStepOne : L10n.articleExportStepTwo
    }

    private func preparePackageAndShowPreview() {
        exportStatus = .preparingDocument
        preparedPackage = nil

        Task {
            let package = await ArticleExportPackageBuilder.package(
                for: request.snapshot,
                options: options,
                includesOfflineImages: includesOfflineImages && canIncludeOfflineImages,
                progress: { progress in
                    exportStatus = ArticleExportStatus(progress: progress)
                }
            )

            preparedPackage = package
            exportStatus = .idle
            step = .preview
        }
    }

    private func imageSummary(for package: ArticleExportPackage) -> String {
        if package.failedImageURLs.isEmpty {
            return String.localizedStringWithFormat(
                L10n.articleExportSummaryImagesSaved,
                package.assets.count
            )
        }

        return String.localizedStringWithFormat(
            L10n.articleExportSummaryImagesPartial,
            package.assets.count,
            package.failedImageURLs.count
        )
    }
}

private extension ArticleExportStatus {
    init(progress: ArticleExportPackageProgress) {
        switch progress {
        case .preparingDocument:
            self = .preparingDocument
        case let .downloadingImage(current, total):
            self = .downloadingImage(current: current, total: total)
        case .creatingArchive:
            self = .creatingArchive
        }
    }

    var isBusy: Bool {
        switch self {
        case .idle:
            false
        case .preparingDocument, .downloadingImage, .creatingArchive, .openingSaveDialog:
            true
        }
    }

    var localizedDescription: String? {
        switch self {
        case .idle:
            nil
        case .preparingDocument:
            L10n.articleExportStatusPreparingDocument
        case let .downloadingImage(current, total):
            String.localizedStringWithFormat(
                L10n.articleExportStatusDownloadingImage,
                current,
                total
            )
        case .creatingArchive:
            L10n.articleExportStatusCreatingArchive
        case .openingSaveDialog:
            L10n.articleExportStatusOpeningSaveDialog
        }
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
                    Text(format.localizedTitle)
                        .font(.callout)
                        .foregroundStyle(.primary)

                    Text(format.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(".\(format.fileExtension)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ArticleExportHTMLPreview: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }

        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator {
        var lastHTML = ""
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

    var localizedPreviewTitle: String {
        switch self {
        case .markdown:
            L10n.articleExportMarkdownPreview
        case .plainText:
            L10n.articleExportPlainTextPreview
        case .html:
            L10n.articleExportHTMLPreview
        }
    }
}
