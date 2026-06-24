import SwiftUI
import UniformTypeIdentifiers

struct ArticleExportRequest: Identifiable {
    let id = UUID()
    let document: ArticleMarkdownDocument
    let defaultFilename: String
}

struct ArticleExportSheet: View {
    let request: ArticleExportRequest
    let onClose: () -> Void

    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.secondary)

            Text(L10n.articleExportPreparingTitle)
                .font(.headline)

            Text(L10n.articleExportPreparingMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Button(L10n.commonCancel) {
                    onClose()
                }

                Button(L10n.articleExportSaveButton) {
                    isExporting = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .frame(width: 320)
        .padding(28)
        .fileExporter(
            isPresented: $isExporting,
            document: request.document,
            contentType: .plainText,
            defaultFilename: request.defaultFilename
        ) { _ in
            onClose()
        }
    }
}
