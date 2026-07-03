import Foundation
import Testing
@testable import Feedivo

struct ReaderPreparedArticleTests {
    @Test func readerInputKannAusSQLiteReaderSnapshotGebautWerden() {
        let snapshot = ArticleReaderSnapshot(
            id: "article-1",
            feedID: "feed-1",
            feedTitle: "SQLite Feed",
            title: "SQLite Artikel",
            link: "https://example.com/artikel",
            summary: "Kurzfassung",
            content: "<p>Volltext</p>",
            imageURL: "https://example.com/bild.jpg",
            author: "Martin",
            publishedAt: Date(timeIntervalSince1970: 100),
            arrivedAt: Date(timeIntervalSince1970: 200),
            estimatedReadingMinutes: 2,
            isRead: false,
            isStarred: false,
            isArchived: false,
            isHidden: false
        )

        let input = ReaderArticleInput.make(from: snapshot)

        #expect(input.summary == "Kurzfassung")
        #expect(input.content == "<p>Volltext</p>")
        #expect(input.contentFingerprint == ReaderArticleTextFingerprint.make(from: "<p>Volltext</p>"))
        #expect(input.imageURL == "https://example.com/bild.jpg")
        #expect(input.offlineContent == nil)
        #expect(input.offlineContentFingerprint == nil)
        #expect(input.offlineState == .none)
        #expect(input.offlineStateRaw == ArticleOfflineState.none.rawValue)
        #expect(input.link == "https://example.com/artikel")
        #expect(input.feedTitle == "SQLite Feed")
        #expect(input.publishedAt == Date(timeIntervalSince1970: 100))
    }
}
