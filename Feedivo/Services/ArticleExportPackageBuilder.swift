import Foundation

protocol ArticleExportImageDataLoading: Sendable {
    func data(from url: URL) async throws -> Data
}

struct URLSessionArticleExportImageDataLoader: ArticleExportImageDataLoading {
    nonisolated init() {}

    func data(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        return data
    }
}

struct ArticleExportPackageAsset: Equatable, Sendable {
    let path: String
    let data: Data
}

struct ArticleExportPackage: Sendable {
    let filename: String
    let contentType: ArticleExportPackageContentType
    let text: String
    let assets: [ArticleExportPackageAsset]
    let failedImageURLs: [URL]
    let archiveData: Data
}

enum ArticleExportPackageContentType: Sendable {
    case document
    case zipArchive
}

enum ArticleExportPackageProgress: Equatable, Sendable {
    case preparingDocument
    case downloadingImage(current: Int, total: Int)
    case creatingArchive
}

enum ArticleExportPackageBuilder {
    static func package(
        for snapshot: ArticleExportSnapshot,
        options: ArticleExportOptions,
        includesOfflineImages: Bool,
        imageLoader: ArticleExportImageDataLoading = URLSessionArticleExportImageDataLoader(),
        progress: @MainActor @escaping (ArticleExportPackageProgress) -> Void = { _ in }
    ) async -> ArticleExportPackage {
        progress(.preparingDocument)

        let originalText = ArticleExportService.text(for: snapshot, options: options)
        let documentFilename = ArticleExportService.defaultFilename(for: snapshot, format: options.format)

        guard includesOfflineImages, options.format.supportsOfflineImagePackage else {
            return ArticleExportPackage(
                filename: documentFilename,
                contentType: .document,
                text: originalText,
                assets: [],
                failedImageURLs: [],
                archiveData: Data(originalText.utf8)
            )
        }

        let assetFolderName = "Pictures"
        let imageURLs = imageURLs(in: originalText)
        var replacements: [String: String] = [:]
        var assets: [ArticleExportPackageAsset] = []
        var failedImageURLs: [URL] = []

        for (index, imageURL) in imageURLs.enumerated() {
            await progress(.downloadingImage(current: index + 1, total: imageURLs.count))

            do {
                let data = try await imageLoader.data(from: imageURL)
                let assetPath = "\(assetFolderName)/image-\(index + 1).\(fileExtension(for: imageURL))"
                replacements[imageURL.absoluteString] = assetPath
                assets.append(ArticleExportPackageAsset(path: assetPath, data: data))
            } catch {
                failedImageURLs.append(imageURL)
            }
        }

        let rewrittenText = textByReplacingImageURLs(in: originalText, replacements: replacements)
        progress(.creatingArchive)

        let archiveFiles = [ArticleExportZIPFile(path: documentFilename, data: Data(rewrittenText.utf8))]
            + assets.map { ArticleExportZIPFile(path: $0.path, data: $0.data) }
        let archiveData = ArticleExportZIPArchive.data(files: archiveFiles)

        return ArticleExportPackage(
            filename: "\(filenameBase(from: documentFilename)).zip",
            contentType: .zipArchive,
            text: rewrittenText,
            assets: assets,
            failedImageURLs: failedImageURLs,
            archiveData: archiveData
        )
    }

    private static func imageURLs(in text: String) -> [URL] {
        var result: [URL] = []
        var seen = Set<String>()

        func appendURLString(_ value: String) {
            guard
                let url = URL(string: value),
                let scheme = url.scheme?.lowercased(),
                ["http", "https"].contains(scheme),
                !seen.contains(url.absoluteString)
            else {
                return
            }

            seen.insert(url.absoluteString)
            result.append(url)
        }

        for match in matches(in: text, pattern: #"<img[^>]+src\s*=\s*"([^"]+)""#) {
            appendURLString(match)
        }

        for match in matches(in: text, pattern: #"<img[^>]+src\s*=\s*'([^']+)'"#) {
            appendURLString(match)
        }

        for match in matches(in: text, pattern: #"\!\[[^\]]*\]\((https?://[^)\s]+)\)"#) {
            appendURLString(match)
        }

        return result
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        return expression.matches(in: text, range: NSRange(text.startIndex ..< text.endIndex, in: text)).compactMap { match in
            guard
                match.numberOfRanges > 1,
                let range = Range(match.range(at: 1), in: text)
            else {
                return nil
            }

            return String(text[range])
        }
    }

    private static func textByReplacingImageURLs(in text: String, replacements: [String: String]) -> String {
        replacements.reduce(text) { partialResult, replacement in
            partialResult.replacingOccurrences(of: replacement.key, with: replacement.value)
        }
    }

    private static func filenameBase(from filename: String) -> String {
        let url = URL(fileURLWithPath: filename)
        let base = url.deletingPathExtension().lastPathComponent
        return base.isEmpty ? "Artikel" : base
    }

    private static func fileExtension(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        let allowedExtensions = Set(["avif", "gif", "jpeg", "jpg", "png", "svg", "webp"])
        return allowedExtensions.contains(pathExtension) ? pathExtension : "img"
    }
}

private extension ArticleExportFormat {
    var supportsOfflineImagePackage: Bool {
        self == .markdown || self == .html
    }
}

struct ArticleExportZIPFile {
    let path: String
    let data: Data
}

enum ArticleExportZIPArchive {
    static func data(files: [ArticleExportZIPFile]) -> Data {
        var archive = Data()
        var centralDirectory = Data()

        for file in files {
            let offset = UInt32(archive.count)
            let fileNameData = Data(file.path.utf8)
            let crc = CRC32.checksum(file.data)

            archive.appendUInt32(0x04034b50)
            archive.appendUInt16(20)
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt32(crc)
            archive.appendUInt32(UInt32(file.data.count))
            archive.appendUInt32(UInt32(file.data.count))
            archive.appendUInt16(UInt16(fileNameData.count))
            archive.appendUInt16(0)
            archive.append(fileNameData)
            archive.append(file.data)

            centralDirectory.appendUInt32(0x02014b50)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(crc)
            centralDirectory.appendUInt32(UInt32(file.data.count))
            centralDirectory.appendUInt32(UInt32(file.data.count))
            centralDirectory.appendUInt16(UInt16(fileNameData.count))
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(0)
            centralDirectory.appendUInt32(offset)
            centralDirectory.append(fileNameData)
        }

        let centralDirectoryStart = UInt32(archive.count)
        let centralDirectorySize = UInt32(centralDirectory.count)
        archive.append(centralDirectory)
        archive.appendUInt32(0x06054b50)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(UInt16(files.count))
        archive.appendUInt16(UInt16(files.count))
        archive.appendUInt32(centralDirectorySize)
        archive.appendUInt32(centralDirectoryStart)
        archive.appendUInt16(0)

        return archive
    }
}

private enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
    }

    private static let table: [UInt32] = (0 ... 255).map { value in
        var crc = UInt32(value)
        for _ in 0 ..< 8 {
            crc = (crc & 1) == 1 ? 0xedb88320 ^ (crc >> 1) : crc >> 1
        }
        return crc
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
