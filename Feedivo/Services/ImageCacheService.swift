import AppKit
import CryptoKit
import Foundation
import ImageIO

protocol ImageDataLoading: Sendable {
    func data(from url: URL) async throws -> Data
}

struct URLSessionImageDataLoader: ImageDataLoading {
    func data(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        return data
    }
}

final class ImageCacheService: @unchecked Sendable {
    static let shared = ImageCacheService()

    private let cacheDirectory: URL
    private let dataLoader: ImageDataLoading
    private let fileManager: FileManager
    private let autoTrimLimitInBytes: @Sendable () -> Int64?
    private let memoryCache = NSCache<NSURL, NSImage>()
    private let thumbnailMemoryCache = NSCache<NSString, NSImage>()
    private let trimEveryNWrites: Int
    private var writesSinceLastTrim = 0

    init(
        cacheDirectory: URL = ImageCacheService.defaultCacheDirectory(),
        dataLoader: ImageDataLoading = URLSessionImageDataLoader(),
        fileManager: FileManager = .default,
        autoTrimLimitInBytes: @escaping @Sendable () -> Int64? = { ImageCacheSettings.currentLimitInBytes },
        trimEveryNWrites: Int = 20
    ) {
        self.cacheDirectory = cacheDirectory
        self.dataLoader = dataLoader
        self.fileManager = fileManager
        self.autoTrimLimitInBytes = autoTrimLimitInBytes
        self.trimEveryNWrites = max(1, trimEveryNWrites)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // countLimit ist nur ein Hinweis an NSCache, keine harte Grenze — beim Wechseln
        // durch viele Artikel wuchs der Speicher trotzdem auf mehrere GB (gemessen:
        // 3,4 GB), weil grosse decodierte Vollbilder (bis ~1960x1960px = ~15 MB je
        // Bild) einfach im RAM blieben. totalCostLimit ist bytebasiert und wird pro
        // eingefuegtem Bild ueber `cost:` in `setObject` mit der tatsaechlichen
        // Pixelgroesse befuellt — das begrenzt den echten Speicherverbrauch, nicht
        // nur die Anzahl der Eintraege.
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 150_000_000
        thumbnailMemoryCache.countLimit = 200
        thumbnailMemoryCache.totalCostLimit = 30_000_000
    }

    private static func estimatedByteCost(of image: NSImage) -> Int {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return 0
        }

        return cgImage.width * cgImage.height * 4
    }

    static func defaultCacheDirectory() -> URL {
        let baseDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseDirectory.appendingPathComponent("Feedivo/ImageCache", isDirectory: true)
    }

    static func cacheFileName(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".img"
    }

    func cachedFileURL(for url: URL) -> URL {
        cacheDirectory.appendingPathComponent(Self.cacheFileName(for: url), isDirectory: false)
    }

    func image(for url: URL) async -> NSImage? {
        let cacheKey = url as NSURL

        if let cachedImage = memoryCache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard let data = await cachedImageData(for: url),
              let image = NSImage(data: data) else {
            return nil
        }

        memoryCache.setObject(image, forKey: cacheKey, cost: Self.estimatedByteCost(of: image))
        return image
    }

    func image(for url: URL, targetPixelSize: CGSize) async -> NSImage? {
        let normalizedTargetSize = Self.normalizedThumbnailPixelSize(targetPixelSize)
        guard normalizedTargetSize.width > 0, normalizedTargetSize.height > 0 else {
            return await image(for: url)
        }

        let cacheKey = Self.thumbnailCacheKey(for: url, targetPixelSize: normalizedTargetSize)
        if let cachedImage = thumbnailMemoryCache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard let data = await cachedImageData(for: url),
              let image = Self.thumbnailImage(from: data, targetPixelSize: normalizedTargetSize) else {
            return nil
        }

        thumbnailMemoryCache.setObject(image, forKey: cacheKey, cost: Self.estimatedByteCost(of: image))
        return image
    }

    @discardableResult
    func cacheImageIfNeeded(from url: URL) async -> Bool {
        await image(for: url) != nil
    }

    /// Maximale Anzahl gleichzeitig laufender Bild-Downloads in `cacheImages`.
    /// Verhindert, dass bei vielen URLs Dutzend Downloads gleichzeitig feuern
    /// (Server-Ratelimiting, Memory-Spitzen). Analog zum Drossel-Pattern in
    /// `FeedService.enrichArticleImagesIfNeeded`.
    static let maxConcurrentImageDownloads = 4

    func cacheImages(from urls: [URL]) async {
        guard !urls.isEmpty else {
            return
        }

        await withTaskGroup(of: Void.self) { group in
            var iterator = urls.makeIterator()
            var activeTasks = 0

            // Start-Window: bis zu `maxConcurrentImageDownloads` Tasks gleichzeitig.
            for _ in 0 ..< min(Self.maxConcurrentImageDownloads, urls.count) {
                guard let url = iterator.next() else {
                    break
                }

                activeTasks += 1
                group.addTask {
                    await self.cacheImageIfNeeded(from: url)
                }
            }

            // Sobald ein Task endet, den nächsten aus der Warteschlange starten.
            while activeTasks > 0 {
                _ = await group.next()
                activeTasks -= 1

                if let url = iterator.next() {
                    activeTasks += 1
                    group.addTask {
                        await self.cacheImageIfNeeded(from: url)
                    }
                }
            }
        }
    }

    func cacheSizeInBytes() throws -> Int64 {
        try cacheFiles().reduce(Int64(0)) { partialResult, fileURL in
            partialResult + fileSize(fileURL)
        }
    }

    func clearCache() throws {
        memoryCache.removeAllObjects()
        thumbnailMemoryCache.removeAllObjects()

        for fileURL in try cacheFiles() {
            try fileManager.removeItem(at: fileURL)
        }
    }

    func trimCache(toLimitInBytes limitInBytes: Int64) throws {
        guard limitInBytes > 0 else {
            try clearCache()
            return
        }

        var files = try cacheFiles().map { fileURL in
            CacheFile(
                url: fileURL,
                size: fileSize(fileURL),
                modificationDate: modificationDate(fileURL)
            )
        }
        .sorted { $0.modificationDate < $1.modificationDate }

        var currentSize = files.reduce(Int64(0)) { $0 + $1.size }
        while currentSize > limitInBytes, !files.isEmpty {
            let file = files.removeFirst()
            try? fileManager.removeItem(at: file.url)
            currentSize -= file.size
        }
    }

    private func cachedImageData(for url: URL) async -> Data? {
        guard ArticleResourceURLPolicy.isArticleImageURLCandidate(url.absoluteString) else {
            return nil
        }

        let fileURL = cachedFileURL(for: url)
        if let data = await readCachedFile(at: fileURL) {
            return data
        }

        do {
            let data = try await dataLoader.data(from: url)
            guard Self.canCreateImage(from: data) else {
                return nil
            }

            await writeCachedFile(data, to: fileURL)
            trimCacheAfterWriteIfNeeded()
            return data
        } catch {
            return nil
        }
    }

    // `image(for:)` wird aus @MainActor-Code (`CachedRemoteImageView`) aufgerufen.
    // Diese Funktion selbst hat aber keine Actor-Isolation — ohne einen echten
    // Suspension-Point wuerde Swift den synchronen Disk-Read + das Metadaten-Update
    // komplett auf dem aufrufenden MainActor (= UI-Thread) ausfuehren und ihn damit
    // waehrend des Scrollens blockieren, statt kooperativ zu unterbrechen.
    // `Task.detached` erzwingt den Hop auf den Hintergrund-Thread-Pool.
    private func readCachedFile(at fileURL: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) { [self] in
            guard let data = try? Data(contentsOf: fileURL) else {
                return nil
            }
            touch(fileURL)
            return data
        }.value
    }

    private func writeCachedFile(_ data: Data, to fileURL: URL) async {
        await Task.detached(priority: .utility) { [self] in
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }.value
    }

    private static func thumbnailImage(from data: Data, targetPixelSize: CGSize) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let maximumPixelSize = max(targetPixelSize.width, targetPixelSize.height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maximumPixelSize.rounded(.up)))
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(
            cgImage: thumbnail,
            size: CGSize(width: thumbnail.width, height: thumbnail.height)
        )
    }

    private static func canCreateImage(from data: Data) -> Bool {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }

        return CGImageSourceGetCount(imageSource) > 0
    }

    private static func normalizedThumbnailPixelSize(_ targetPixelSize: CGSize) -> CGSize {
        CGSize(
            width: targetPixelSize.width.rounded(.up),
            height: targetPixelSize.height.rounded(.up)
        )
    }

    private static func thumbnailCacheKey(for url: URL, targetPixelSize: CGSize) -> NSString {
        "\(url.absoluteString)#\(Int(targetPixelSize.width))x\(Int(targetPixelSize.height))" as NSString
    }

    private func cacheFiles() throws -> [URL] {
        guard fileManager.fileExists(atPath: cacheDirectory.path) else {
            return []
        }

        return try fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
    }

    private func fileSize(_ fileURL: URL) -> Int64 {
        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func modificationDate(_ fileURL: URL) -> Date {
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    private func touch(_ fileURL: URL) {
        try? fileManager.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )
    }

    // Ohne Throttling loeste JEDER einzelne Bild-Download einen vollen
    // Verzeichnis-Scan+Sort ueber den kompletten Cache aus (O(n) pro Schreibvorgang,
    // bei vielen kleinen Cache-Dateien in der Praxis O(n^2)-artig ueber einen
    // Refresh-Batch). Jetzt: nur alle `trimEveryNWrites` Schreibvorgaenge, und dann
    // auf einem Hintergrund-Thread statt inline auf dem aufrufenden Actor.
    private func trimCacheAfterWriteIfNeeded() {
        guard let limitInBytes = autoTrimLimitInBytes() else {
            return
        }

        writesSinceLastTrim += 1
        guard writesSinceLastTrim >= trimEveryNWrites else {
            return
        }
        writesSinceLastTrim = 0

        Task.detached(priority: .utility) { [self] in
            try? trimCache(toLimitInBytes: limitInBytes)
        }
    }
}

private struct CacheFile {
    let url: URL
    let size: Int64
    let modificationDate: Date
}
