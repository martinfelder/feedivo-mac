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

    var hasImageSummary: Bool {
        !assets.isEmpty || !failedImageURLs.isEmpty
    }
}

enum ArticleExportPackageContentType: Equatable, Sendable {
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
        // Nicht mehr im Funktionskoerper verwendet, seit der PDF-spezifische Zweig unten
        // entfernt wurde (Feature 25.1 "Drucken" ersetzt den alten CGContext-PDF-Renderer
        // durch nativen Druck; .pdf ist ueber ArticleExportFormat.dialogFormats ohnehin nie
        // erreichbar). Bleibt fuer Aufrufkompatibilitaet mit ArticleExportSheet.swift stehen.
        pdfStyle: ArticlePDFExportStyle = .default,
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
                archiveData: ArticleExportService.data(for: snapshot, options: options)
            )
        }

        let imagePackage = await imagePackage(
            from: originalText,
            imageLoader: imageLoader,
            progress: progress
        )
        let rewrittenText = textByReplacingImageURLs(in: originalText, replacements: imagePackage.replacements)
        progress(.creatingArchive)

        let archiveFiles = [ArticleExportZIPFile(path: documentFilename, data: Data(rewrittenText.utf8))]
            + imagePackage.assets.map { ArticleExportZIPFile(path: $0.path, data: $0.data) }
        let archiveData = ArticleExportZIPArchive.data(files: archiveFiles)

        return ArticleExportPackage(
            filename: "\(filenameBase(from: documentFilename)).zip",
            contentType: .zipArchive,
            text: rewrittenText,
            assets: imagePackage.assets,
            failedImageURLs: imagePackage.failedImageURLs,
            archiveData: archiveData
        )
    }

    /// Maximale Anzahl gleichzeitig laufender Bild-Downloads im Export-Paket.
    /// Verhindert, dass bei vielen Bildern Dutzend Requests gleichzeitig feuern
    /// (Server-Ratelimiting, Memory-Spitzen). Analog zum Drossel-Pattern in
    /// `ImageCacheService.cacheImages`.
    static let maxConcurrentImageDownloads = 4

    private static func imagePackage(
        from text: String,
        imageLoader: ArticleExportImageDataLoading,
        progress: @MainActor @escaping (ArticleExportPackageProgress) -> Void
    ) async -> (replacements: [String: String], assets: [ArticleExportPackageAsset], failedImageURLs: [URL]) {
        let assetFolderName = "Pictures"
        let imageURLs = imageURLs(in: text)

        guard !imageURLs.isEmpty else {
            return ([:], [], [])
        }

        // Parallele Downloads mit Drosselung (Sliding-Window) statt sequenziell.
        // Jeder Task kennt seinen Original-Index, damit Asset-Pfade stabil
        // "image-N" heißen und `assets`/`failedImageURLs` in Dokumentenreihenfolge bleiben.
        var collected: [IndexedImageDownload] = []

        await withTaskGroup(of: IndexedImageDownload.self) { group in
            var iterator = imageURLs.enumerated().makeIterator()
            var activeTasks = 0

            // Start-Window: bis zu `maxConcurrentImageDownloads` Tasks gleichzeitig.
            for _ in 0 ..< min(Self.maxConcurrentImageDownloads, imageURLs.count) {
                guard let entry = iterator.next() else {
                    break
                }

                activeTasks += 1
                group.addTask {
                    let data = try? await imageLoader.data(from: entry.element)
                    return IndexedImageDownload(index: entry.offset, url: entry.element, data: data)
                }
            }

            // Sobald ein Task endet, nächsten aus der Warteschlange starten.
            // Fortschritt meldet die Anzahl abgeschlossener Downloads.
            var completed = 0
            while activeTasks > 0 {
                guard let result = await group.next() else {
                    break
                }

                activeTasks -= 1
                collected.append(result)
                completed += 1
                await progress(.downloadingImage(current: completed, total: imageURLs.count))

                if let next = iterator.next() {
                    activeTasks += 1
                    group.addTask {
                        let data = try? await imageLoader.data(from: next.element)
                        return IndexedImageDownload(index: next.offset, url: next.element, data: data)
                    }
                }
            }
        }

        // Original-Reihenfolge wiederherstellen (Tasks enden nicht zwingend
        // in Start-Reihenfolge).
        collected.sort { $0.index < $1.index }

        var replacements: [String: String] = [:]
        var assets: [ArticleExportPackageAsset] = []
        var failedImageURLs: [URL] = []

        for result in collected {
            let assetPath = "\(assetFolderName)/image-\(result.index + 1).\(fileExtension(for: result.url))"

            if let data = result.data {
                replacements[result.url.absoluteString] = assetPath
                assets.append(ArticleExportPackageAsset(path: assetPath, data: data))
            } else {
                failedImageURLs.append(result.url)
            }
        }

        return (replacements, assets, failedImageURLs)
    }

    /// Ein heruntergeladenes (oder fehlgeschlagenes) Bild inklusive seines
    /// Original-Index in der Quell-URL-Liste, damit die Asset-Pfade stabil
    /// bleiben und das Ergebnis nach Download sortiert werden kann.
    private struct IndexedImageDownload: Sendable {
        let index: Int
        let url: URL
        let data: Data?
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
        self == .markdown || self == .html || self == .pdf
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
