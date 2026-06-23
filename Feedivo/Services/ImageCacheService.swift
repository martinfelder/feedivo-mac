import AppKit
import CryptoKit
import Foundation

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
    private let memoryCache = NSCache<NSURL, NSImage>()

    init(
        cacheDirectory: URL = ImageCacheService.defaultCacheDirectory(),
        dataLoader: ImageDataLoading = URLSessionImageDataLoader(),
        fileManager: FileManager = .default
    ) {
        self.cacheDirectory = cacheDirectory
        self.dataLoader = dataLoader
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
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

        let fileURL = cachedFileURL(for: url)
        if let diskImage = imageFromDisk(at: fileURL) {
            memoryCache.setObject(diskImage, forKey: cacheKey)
            touch(fileURL)
            return diskImage
        }

        do {
            let data = try await dataLoader.data(from: url)
            guard let image = NSImage(data: data) else {
                return nil
            }

            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
            memoryCache.setObject(image, forKey: cacheKey)
            return image
        } catch {
            return nil
        }
    }

    @discardableResult
    func cacheImageIfNeeded(from url: URL) async -> Bool {
        await image(for: url) != nil
    }

    func cacheImages(from urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    await self.cacheImageIfNeeded(from: url)
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

    private func imageFromDisk(at fileURL: URL) -> NSImage? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return NSImage(data: data)
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
}

private struct CacheFile {
    let url: URL
    let size: Int64
    let modificationDate: Date
}
