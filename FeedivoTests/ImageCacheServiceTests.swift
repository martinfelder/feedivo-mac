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

    private static func temporaryCacheDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func pngData() throws -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()

        let tiffData = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiffData))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}
