import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownText = UTType(filenameExtension: "md") ?? .plainText
}

struct ArticleExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.markdownText, .plainText, .html]
    }

    static var writableContentTypes: [UTType] {
        [.markdownText, .plainText, .html]
    }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
