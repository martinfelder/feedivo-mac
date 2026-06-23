import Foundation
import Testing
@testable import Feedivo

private struct StubOfflineContentFetcher: OfflineArticleContentFetching {
    var result: Result<String, Error>

    func content(from url: URL) async throws -> String {
        try result.get()
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

    @Test func removeOfflineContentClearsOfflineFields() async {
        let article = Article(
            title: "Gespeichert",
            link: "https://example.com/article",
            content: "<p>Text</p>"
        )
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
    }
}
