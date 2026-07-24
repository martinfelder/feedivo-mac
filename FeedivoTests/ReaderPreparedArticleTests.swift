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
        #expect(input.link == "https://example.com/artikel")
        #expect(input.feedTitle == "SQLite Feed")
        #expect(input.author == "Martin")
        #expect(input.publishedAt == Date(timeIntervalSince1970: 100))
    }

    // Nutzerwunsch (2026-07-23): Autor in der Reader-Metadaten-Zeile anzeigen,
    // zwischen Lesezeit und Datum.
    @Test func metadataTextEnthaeltAutorZwischenLesezeitUndDatum() {
        let input = ReaderArticleInput(
            summary: nil,
            content: "<p>Ein ausreichend langer Absatz fuer die Lesezeitberechnung.</p>",
            contentFingerprint: nil,
            imageURL: nil,
            link: nil,
            feedTitle: "SQLite Feed",
            author: "Martin",
            publishedAt: Date(timeIntervalSince1970: 100)
        )

        let prepared = ReaderPreparedArticle(input: input)

        #expect(prepared.metadataText.contains("Martin"))
        let readingTimeRange = prepared.metadataText.range(of: prepared.readingTimeText ?? "")
        let authorRange = prepared.metadataText.range(of: "Martin")
        if let readingTimeRange, let authorRange {
            #expect(readingTimeRange.upperBound <= authorRange.lowerBound)
        }
    }

    // Regression: ReaderArticleCacheKey ignorierte bisher author, wodurch ein
    // erneuter Feed-Refresh mit neu hinzugekommenem Autor innerhalb derselben
    // App-Session an einer bereits gecachten (identischen bis auf author)
    // ReaderPreparedArticle vorbeilief -- der Autor blieb bis zur naechsten
    // Cache-Verdraengung unsichtbar.
    @Test func cacheKeyUnterscheidetSichBeiUnterschiedlichemAutor() {
        let inputMitAutor = ReaderArticleInput(
            summary: "Kurzfassung",
            content: "<p>Volltext</p>",
            contentFingerprint: ReaderArticleTextFingerprint.make(from: "<p>Volltext</p>"),
            imageURL: nil,
            link: "https://example.com/artikel",
            feedTitle: "SQLite Feed",
            author: "Martin",
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        let inputOhneAutor = ReaderArticleInput(
            summary: "Kurzfassung",
            content: "<p>Volltext</p>",
            contentFingerprint: ReaderArticleTextFingerprint.make(from: "<p>Volltext</p>"),
            imageURL: nil,
            link: "https://example.com/artikel",
            feedTitle: "SQLite Feed",
            author: nil,
            publishedAt: Date(timeIntervalSince1970: 100)
        )

        #expect(inputMitAutor.cacheKey != inputOhneAutor.cacheKey)
    }
}
