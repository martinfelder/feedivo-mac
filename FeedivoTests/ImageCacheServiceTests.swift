import AppKit
import Foundation
import Testing
@testable import Feedivo

private final class StubImageDataLoader: ImageDataLoading, @unchecked Sendable {
    var responses: [URL: Data]
    private(set) var requestedURLs: [URL] = []

    init(responses: [URL: Data]) {
        self.responses = responses
    }

    func data(from url: URL) async throws -> Data {
        requestedURLs.append(url)
        return responses[url] ?? Data()
    }
}

/// Zählt, wie viele Ladevorgänge gleichzeitig aktiv sind, um eine
/// Drosselung der Gleichzeitigkeit in `cacheImages` verifizieren zu können.
final class ConcurrencyTrackingImageDataLoader: ImageDataLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = 0
    private(set) var maxInFlight = 0
    private(set) var completedCount = 0
    private let delayNanoseconds: UInt64
    private let data: Data

    init(delayNanoseconds: UInt64 = 30_000_000, data: Data = Data(repeating: 1, count: 8)) {
        self.delayNanoseconds = delayNanoseconds
        self.data = data
    }

    func data(from url: URL) async throws -> Data {
        lock.lock()
        inFlight += 1
        if inFlight > maxInFlight {
            maxInFlight = inFlight
        }
        lock.unlock()

        try await Task.sleep(nanoseconds: delayNanoseconds)

        lock.lock()
        inFlight -= 1
        completedCount += 1
        lock.unlock()

        return data
    }
}

@MainActor
struct ImageCacheServiceTests {
    @Test func cacheFileNameIstStabilUndDateisystemfreundlich() throws {
        let url = try #require(URL(string: "https://example.com/assets/bild.png?size=large"))

        let firstName = ImageCacheService.cacheFileName(for: url)
        let secondName = ImageCacheService.cacheFileName(for: url)

        #expect(firstName == secondName)
        #expect(firstName.hasSuffix(".img"))
        #expect(!firstName.contains("/"))
        #expect(!firstName.contains("?"))
    }

    @Test func imageLaedtEinmalAusDemNetzUndDanachAusMemoryCache() async throws {
        let cacheDirectory = try Self.temporaryCacheDirectory()
        let url = try #require(URL(string: "https://example.com/image.png"))
        let loader = StubImageDataLoader(responses: [url: try Self.pngData()])
        let service = ImageCacheService(cacheDirectory: cacheDirectory, dataLoader: loader)

        let firstImage = await service.image(for: url)
        let secondImage = await service.image(for: url)

        #expect(firstImage != nil)
        #expect(secondImage != nil)
        #expect(loader.requestedURLs == [url])
        #expect(FileManager.default.fileExists(atPath: service.cachedFileURL(for: url).path))
    }

    @Test func imageLaedtAusDiskCacheOhneNetzwerk() async throws {
        let cacheDirectory = try Self.temporaryCacheDirectory()
        let url = try #require(URL(string: "https://example.com/disk.png"))
        let service = ImageCacheService(
            cacheDirectory: cacheDirectory,
            dataLoader: StubImageDataLoader(responses: [:])
        )
        try Self.pngData().write(to: service.cachedFileURL(for: url))

        let image = await service.image(for: url)

        #expect(image != nil)
    }

    @Test func thumbnailBegrenztBildgroesseUndNutztOriginalenCache() async throws {
        let cacheDirectory = try Self.temporaryCacheDirectory()
        let url = try #require(URL(string: "https://example.com/large.png"))
        let loader = StubImageDataLoader(responses: [url: try Self.pngData(width: 200, height: 100)])
        let service = ImageCacheService(cacheDirectory: cacheDirectory, dataLoader: loader)

        let firstThumbnail = try #require(await service.image(
            for: url,
            targetPixelSize: CGSize(width: 40, height: 40)
        ))
        let secondThumbnail = try #require(await service.image(
            for: url,
            targetPixelSize: CGSize(width: 40, height: 40)
        ))

        #expect(firstThumbnail.size.width <= 40)
        #expect(firstThumbnail.size.height <= 40)
        #expect(secondThumbnail === firstThumbnail)
        #expect(loader.requestedURLs == [url])
        #expect(FileManager.default.fileExists(atPath: service.cachedFileURL(for: url).path))
    }

    @Test func cacheSizeUndClearCacheBeruecksichtigenDateien() throws {
        let cacheDirectory = try Self.temporaryCacheDirectory()
        let service = ImageCacheService(
            cacheDirectory: cacheDirectory,
            dataLoader: StubImageDataLoader(responses: [:])
        )
        let firstURL = try #require(URL(string: "https://example.com/a.png"))
        let secondURL = try #require(URL(string: "https://example.com/b.png"))
        try Data(repeating: 1, count: 12).write(to: service.cachedFileURL(for: firstURL))
        try Data(repeating: 2, count: 8).write(to: service.cachedFileURL(for: secondURL))

        #expect(try service.cacheSizeInBytes() == 20)

        try service.clearCache()

        #expect(try service.cacheSizeInBytes() == 0)
    }

    @Test func trimCacheEntferntAeltesteDateienBisUnterLimit() throws {
        let cacheDirectory = try Self.temporaryCacheDirectory()
        let service = ImageCacheService(
            cacheDirectory: cacheDirectory,
            dataLoader: StubImageDataLoader(responses: [:])
        )
        let oldURL = try #require(URL(string: "https://example.com/old.png"))
        let newURL = try #require(URL(string: "https://example.com/new.png"))
        let oldFile = service.cachedFileURL(for: oldURL)
        let newFile = service.cachedFileURL(for: newURL)
        try Data(repeating: 1, count: 12).write(to: oldFile)
        try Data(repeating: 2, count: 12).write(to: newFile)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: oldFile.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: newFile.path
        )

        try service.trimCache(toLimitInBytes: 12)

        #expect(!FileManager.default.fileExists(atPath: oldFile.path))
        #expect(FileManager.default.fileExists(atPath: newFile.path))
        #expect(try service.cacheSizeInBytes() == 12)
    }

    @Test func imageTrimmtCacheNachErfolgreichemDownloadAufLimit() async throws {
        let cacheDirectory = try Self.temporaryCacheDirectory()
        let oldURL = try #require(URL(string: "https://example.com/old.png"))
        let downloadedURL = try #require(URL(string: "https://example.com/downloaded.png"))
        let downloadedData = try Self.pngData()
        let loader = StubImageDataLoader(responses: [downloadedURL: downloadedData])
        let service = ImageCacheService(
            cacheDirectory: cacheDirectory,
            dataLoader: loader,
            autoTrimLimitInBytes: { Int64(downloadedData.count) }
        )
        let oldFile = service.cachedFileURL(for: oldURL)
        try Data(repeating: 1, count: downloadedData.count).write(to: oldFile)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: oldFile.path
        )

        let image = await service.image(for: downloadedURL)

        #expect(image != nil)
        #expect(!FileManager.default.fileExists(atPath: oldFile.path))
        #expect(FileManager.default.fileExists(atPath: service.cachedFileURL(for: downloadedURL).path))
        #expect(try service.cacheSizeInBytes() <= Int64(downloadedData.count))
    }

    @Test func cacheImagesDrosseltGleichzeitigeDownloadsAufMaxConcurrency() async throws {
        let cacheDirectory = try Self.temporaryCacheDirectory()
        let loader = ConcurrencyTrackingImageDataLoader()
        let service = ImageCacheService(cacheDirectory: cacheDirectory, dataLoader: loader)

        // Mehr URLs als das Drossel-Limit, damit ohne Drosselung alle gleichzeitig laden.
        let urls = (0 ..< 12).map { offset in
            URL(string: "https://example.com/image-\(offset).png")!
        }

        await service.cacheImages(from: urls)

        // Alle Requests wurden ausgelöst und abgeschlossen.
        #expect(loader.completedCount == urls.count)
        // Gleichzeitigkeit wird auf das Drossel-Limit beschränkt (nicht alle 12 auf einmal).
        #expect(loader.maxInFlight <= ImageCacheService.maxConcurrentImageDownloads, "maxInFlight=\(loader.maxInFlight) – Gleichzeitigkeit nicht gedrosselt")
    }

    private static func temporaryCacheDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func pngData(width: CGFloat = 2, height: CGFloat = 2) throws -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()

        let tiffData = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiffData))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}
