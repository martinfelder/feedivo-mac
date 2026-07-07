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

    @Test func articleSortOptionFaelltBeiUngueltigemRawValueAufStandardZurueck() {
        #expect(ArticleSortOption.resolved(from: "kaputt") == .newestFirst)
        #expect(ArticleSortOption.resolved(from: ArticleSortOption.title.rawValue) == .title)
    }

    @Test func articleFilterOptionFaelltBeiUngueltigemRawValueAufStandardZurueck() {
        #expect(ArticleFilterOption.resolved(from: "kaputt") == .all)
        #expect(ArticleFilterOption.resolved(from: ArticleFilterOption.archived.rawValue) == .archived)
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
