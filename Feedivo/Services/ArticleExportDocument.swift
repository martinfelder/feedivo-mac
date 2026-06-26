import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownText = UTType(filenameExtension: "md") ?? .plainText
    static let docxDocument = UTType(
        filenameExtension: "docx",
        conformingTo: .zip
    ) ?? .zip
}

struct ArticleExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.markdownText, .plainText, .html, .pdf, .docxDocument, .zip]
    }

    static var writableContentTypes: [UTType] {
        [.markdownText, .plainText, .html, .pdf, .docxDocument, .zip]
    }

    var data: Data

    init(text: String = "") {
        self.data = Data(text.utf8)
    }

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
