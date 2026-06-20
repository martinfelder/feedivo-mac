import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let opml = UTType(filenameExtension: "opml") ?? .xml
}

struct OPMLDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.opml, .xml]
    }

    static var writableContentTypes: [UTType] {
        [.opml, .xml]
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
