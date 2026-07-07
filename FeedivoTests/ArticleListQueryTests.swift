import Foundation
import Testing
@testable import Feedivo

@Suite(.serialized)
struct ArticleListQueryTests {
    @Test func sqliteDisplayStateHaeltAutomatischGeleseneArtikelSichtbar() {
        let unreadRow = sqliteSnapshot(id: "unread", title: "Ungelesen", isRead: false)
        let autoReadRow = sqliteSnapshot(id: "auto-read", title: "Automatisch gelesen", isRead: true)
        let regularReadRow = sqliteSnapshot(id: "regular-read", title: "Vorher gelesen", isRead: true)

        let state = SQLiteArticleListDisplayState(
            rows: [unreadRow, autoReadRow, regularReadRow],
            showsReadArticles: false,
            selectedArticleID: nil,
            temporarilyVisibleReadArticleIDs: ["auto-read"],
            filterOption: .all
        )

        #expect(state.visibleRows.map(\.title) == ["Ungelesen", "Automatisch gelesen"])
        #expect(state.hiddenReadRowCount == 1)
    }

    @Test func sqliteDisplayStateHaeltAutomatischGeleseneArtikelImUngelesenFilterSichtbar() {
        let unreadRow = sqliteSnapshot(id: "unread", title: "Ungelesen", isRead: false)
        let autoReadRow = sqliteSnapshot(id: "auto-read", title: "Automatisch gelesen", isRead: true)
        let regularReadRow = sqliteSnapshot(id: "regular-read", title: "Vorher gelesen", isRead: true)

        let state = SQLiteArticleListDisplayState(
            rows: [unreadRow, autoReadRow, regularReadRow],
            showsReadArticles: false,
            selectedArticleID: nil,
            temporarilyVisibleReadArticleIDs: ["auto-read"],
            filterOption: .unread
        )

        #expect(state.visibleRows.map(\.title) == ["Ungelesen", "Automatisch gelesen"])
        #expect(state.hiddenReadRowCount == 0)
    }

    @Test func mergingStickyRowsBehaeltArtikelDerAusDerFrischenAbfrageFaellt() {
        let stillPresentRow = sqliteSnapshot(id: "present", title: "Weiterhin da", isRead: false)
        let droppedRow = sqliteSnapshot(id: "dropped", title: "Gerade gelesen", isRead: true)

        let merged = SQLiteArticleListDisplayState.mergingStickyRows(
            into: [stillPresentRow],
            stickyRowSnapshots: ["dropped": droppedRow, "present": stillPresentRow]
        )

        #expect(Set(merged.map(\.id)) == Set(["present", "dropped"]))
    }

    @Test func mergingStickyRowsBevorzugtFrischeZeileBeiDoppelterID() {
        let staleStickyRow = sqliteSnapshot(id: "same", title: "Veraltet", isRead: true)
        let freshRow = sqliteSnapshot(id: "same", title: "Frisch", isRead: false)

        let merged = SQLiteArticleListDisplayState.mergingStickyRows(
            into: [freshRow],
            stickyRowSnapshots: ["same": staleStickyRow]
        )

        #expect(merged.map(\.title) == ["Frisch"])
    }

    @Test func articleSortOptionSortiertArtikelNachBenutzerauswahl() {
        let feedA = Feed(url: "https://example.com/a.xml", title: "Alpha")
        let feedB = Feed(url: "https://example.com/b.xml", title: "Beta")
        let newest = Article(
            title: "Zebra",
            summary: Array(repeating: "wort", count: 220).joined(separator: " "),
            publishedAt: Date(timeIntervalSince1970: 300),
            feed: feedB
        )
        let oldest = Article(
            title: "Apfel",
            summary: "eins",
            publishedAt: Date(timeIntervalSince1970: 100),
            feed: feedA
        )
        let middle = Article(
            title: "Mitte",
            summary: Array(repeating: "wort", count: 420).joined(separator: " "),
            publishedAt: Date(timeIntervalSince1970: 200),
            feed: feedA
        )
        let articles = [middle, newest, oldest]

        #expect(ArticleSortOption.newestFirst.sorted(articles).map(\.title) == ["Zebra", "Mitte", "Apfel"])
        #expect(ArticleSortOption.oldestFirst.sorted(articles).map(\.title) == ["Apfel", "Mitte", "Zebra"])
        #expect(ArticleSortOption.feed.sorted(articles).map(\.title) == ["Mitte", "Apfel", "Zebra"])
        #expect(ArticleSortOption.title.sorted(articles).map(\.title) == ["Apfel", "Mitte", "Zebra"])
        #expect(ArticleSortOption.shortReadingTimeFirst.sorted(articles).map(\.title) == ["Apfel", "Zebra", "Mitte"])
    }

    @Test func articleSortOptionFaelltBeiUngueltigemRawValueAufStandardZurueck() {
        #expect(ArticleSortOption.resolved(from: "kaputt") == .newestFirst)
        #expect(ArticleSortOption.resolved(from: ArticleSortOption.title.rawValue) == .title)
    }

    @Test func articleFilterOptionFiltertArtikelNachBenutzerauswahl() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let unreadArticle = Article(title: "Ungelesen", isRead: false)
        let readArticle = Article(title: "Gelesen", isRead: true)
        let starredArticle = Article(title: "Stern", isStarred: true)
        let archivedArticle = Article(title: "Archiv", isArchived: true)
        let todayArticle = Article(title: "Heute", publishedAt: now)
        let oldArticle = Article(
            title: "Alt",
            publishedAt: calendar.date(byAdding: .day, value: -2, to: now)
        )
        let articles = [
            unreadArticle,
            readArticle,
            starredArticle,
            archivedArticle,
            todayArticle,
            oldArticle
        ]

        #expect(ArticleFilterOption.all.filtered(articles, now: now, calendar: calendar).map(\.title) == [
            "Ungelesen",
            "Gelesen",
            "Stern",
            "Archiv",
            "Heute",
            "Alt"
        ])
        #expect(ArticleFilterOption.unread.filtered(articles, now: now, calendar: calendar).map(\.title) == [
            "Ungelesen",
            "Stern",
            "Archiv",
            "Heute",
            "Alt"
        ])
        #expect(ArticleFilterOption.starred.filtered(articles, now: now, calendar: calendar).map(\.title) == ["Stern"])
        #expect(ArticleFilterOption.archived.filtered(articles, now: now, calendar: calendar).map(\.title) == ["Archiv"])
        #expect(ArticleFilterOption.today.filtered(articles, now: now, calendar: calendar).map(\.title) == ["Heute"])
    }

    @Test func articleFilterOptionFaelltBeiUngueltigemRawValueAufStandardZurueck() {
        #expect(ArticleFilterOption.resolved(from: "kaputt") == .all)
        #expect(ArticleFilterOption.resolved(from: ArticleFilterOption.archived.rawValue) == .archived)
    }

    @Test func articleInitialisiertDirekteFeedIDFuerSchnelleListenQueries() throws {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let article = Article(title: "Artikel", feed: feed)

        #expect(article.feedID == feed.id)
    }

    private func sqliteSnapshot(
        id: String,
        title: String,
        isRead: Bool
    ) -> ArticleListSnapshot {
        ArticleListSnapshot(
            id: id,
            feedID: "feed-1",
            feedTitle: "Feed",
            title: title,
            summary: nil,
            link: nil,
            imageURL: nil,
            publishedAt: Date(timeIntervalSince1970: 100),
            arrivedAt: Date(timeIntervalSince1970: 100),
            estimatedReadingMinutes: nil,
            isRead: isRead,
            isStarred: false,
            isArchived: false,
            isHidden: false
        )
    }
}
