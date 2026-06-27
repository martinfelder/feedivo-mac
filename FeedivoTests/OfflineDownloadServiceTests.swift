import Foundation
import Testing
@testable import Feedivo

private struct StubOfflineContentFetcher: OfflineArticleContentFetching {
    var result: Result<String, Error>

    func content(from url: URL) async throws -> String {
        try result.get()
    }
}

private final class StubOfflineImageCache: OfflineArticleImageCaching, @unchecked Sendable {
    private(set) var cachedURLs: [URL] = []

    func cacheImages(from urls: [URL]) async {
        cachedURLs.append(contentsOf: urls)
    }
}

private struct OfflineTestError: LocalizedError {
    var errorDescription: String? {
        "Server nicht erreichbar"
    }
}

@MainActor
struct OfflineDownloadServiceTests {
    @Test func saveForOfflineUsesExistingFeedContentWithoutNetworkFetch() async {
        let article = Article(
            title: "Feed Artikel",
            link: "https://example.com/article",
            content: "<p>Volltext aus dem Feed.</p>"
        )
        let service = OfflineDownloadService(
            fetcher: StubOfflineContentFetcher(result: .success("<p>Webseite</p>"))
        )

        await service.saveForOffline(article)

        #expect(article.offlineState == .feedContent)
        #expect(article.offlineContent == "<p>Volltext aus dem Feed.</p>")
        #expect(article.offlineErrorMessage == nil)
        #expect(article.offlineSavedAt != nil)
        #expect(article.offlineRequestedAt != nil)
    }

    @Test func saveForOfflineFetchesOriginalArticleWhenFeedContentIsMissing() async {
        let article = Article(
            title: "Web Artikel",
            link: "https://example.com/article",
            summary: "Kurze Zusammenfassung",
        )
        let service = OfflineDownloadService(
            fetcher: StubOfflineContentFetcher(result: .success("<article>Geladener Volltext</article>"))
        )

        await service.saveForOffline(article)

        #expect(article.offlineState == .fullText)
        #expect(article.offlineContent == "<article>Geladener Volltext</article>")
        #expect(article.offlineErrorMessage == nil)
        #expect(article.offlineSavedAt != nil)
    }

    @Test func saveForOfflineCachesKnownArticleImages() async throws {
        let leadImageURL = try #require(URL(string: "https://example.com/lead.jpg"))
        let inlineImageURL = try #require(URL(string: "https://example.com/inline.jpg"))
        let article = Article(
            title: "Bilder",
            link: "https://example.com/article",
            imageURL: leadImageURL.absoluteString
        )
        let imageCache = StubOfflineImageCache()
        let service = OfflineDownloadService(
            fetcher: StubOfflineContentFetcher(
                result: .success(#"<article><img src="https://example.com/inline.jpg"><p>Text</p></article>"#)
            ),
            imageCache: imageCache
        )

        await service.saveForOffline(article)

        #expect(imageCache.cachedURLs == [leadImageURL, inlineImageURL])
    }

    @Test func saveForOfflineStoresFailureWhenOriginalArticleCannotBeFetched() async {
        let article = Article(
            title: "Defekt",
            link: "https://example.com/article",
            summary: "Kurze Zusammenfassung",
        )
        let service = OfflineDownloadService(
            fetcher: StubOfflineContentFetcher(result: .failure(OfflineTestError()))
        )

        await service.saveForOffline(article)

        #expect(article.offlineState == .failed)
        #expect(article.offlineContent == nil)
        #expect(article.offlineErrorMessage == "Server nicht erreichbar")
        #expect(article.offlineSavedAt == nil)
        #expect(article.offlineRequestedAt != nil)
    }

    @Test func archiveForOfflineSpeichertOfflineKopieUndSetztArchivstatus() async {
        let article = Article(
            title: "Archiv",
            link: "https://example.com/article",
            content: "<p>Archivierter Volltext.</p>"
        )
        let service = OfflineDownloadService(
            fetcher: StubOfflineContentFetcher(result: .success("<p>Webseite</p>"))
        )

        await service.archiveForOffline(article)

        #expect(article.isArchived)
        #expect(article.offlineState == .feedContent)
        #expect(article.offlineContent == "<p>Archivierter Volltext.</p>")
    }

    @Test func archiveForOfflineSetztArchivstatusNichtBeiFehler() async {
        let article = Article(
            title: "Defekt",
            link: "https://example.com/article"
        )
        let service = OfflineDownloadService(
            fetcher: StubOfflineContentFetcher(result: .failure(OfflineTestError()))
        )

        await service.archiveForOffline(article)

        #expect(!article.isArchived)
        #expect(article.offlineState == .failed)
    }

    @Test func archiveForOfflineMeldetErfolgWennKopieErstelltWurde() async {
        let article = Article(
            title: "Archiv",
            link: "https://example.com/article",
            content: "<p>Archivierter Volltext.</p>"
        )
        let service = OfflineDownloadService(
            fetcher: StubOfflineContentFetcher(result: .success("<p>Webseite</p>"))
        )

        let success = await service.archiveForOffline(article)

        #expect(success)
        #expect(article.isArchived)
    }

    @Test func archiveForOfflineMeldetMisserfolgWennSpeichernScheitert() async {
        let article = Article(
            title: "Defekt",
            link: "https://example.com/article"
        )
        let service = OfflineDownloadService(
            fetcher: StubOfflineContentFetcher(result: .failure(OfflineTestError()))
        )

        let success = await service.archiveForOffline(article)

        #expect(!success)
        #expect(!article.isArchived)
        #expect(article.offlineErrorMessage == "Server nicht erreichbar")
    }

    @Test func removeArchiveEntferntArchivstatusUndOfflineKopieAberNichtDenArtikel() async {
        let article = Article(
            title: "Archiviert",
            link: "https://example.com/article",
            isArchived: true
        )
        article.offlineState = .fullText
        article.offlineContent = "<article>Volltext</article>"
        article.offlineRequestedAt = Date()
        article.offlineSavedAt = Date()

        let service = OfflineDownloadService()
        service.removeArchive(from: article)

        #expect(!article.isArchived)
        #expect(article.offlineState == .none)
        #expect(article.offlineContent == nil)
        #expect(article.title == "Archiviert")
    }

    @Test func removeOfflineContentClearsOfflineFields() async {
        let article = Article(
            title: "Gespeichert",
            link: "https://example.com/article",
            content: "<p>Text</p>"
        )
        article.isArchived = true
        article.offlineState = .feedContent
        article.offlineContent = "<p>Text</p>"
        article.offlineErrorMessage = "Alter Fehler"
        article.offlineRequestedAt = Date()
        article.offlineSavedAt = Date()

        let service = OfflineDownloadService()
        service.removeOfflineContent(from: article)

        #expect(article.offlineState == .none)
        #expect(article.offlineContent == nil)
        #expect(article.offlineErrorMessage == nil)
        #expect(article.offlineRequestedAt == nil)
        #expect(article.offlineSavedAt == nil)
        #expect(!article.isArchived)
    }
}
