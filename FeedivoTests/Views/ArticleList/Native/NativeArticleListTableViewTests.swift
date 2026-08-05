import Foundation
import Testing
@testable import Feedivo

struct NativeArticleListTableViewTests {
    private func makeSnapshot(id: String) -> ArticleListSnapshot {
        ArticleListSnapshot(
            id: id, feedID: "f1", feedTitle: "Feed", title: "Titel \(id)",
            summary: nil, link: nil, imageURL: nil, publishedAt: nil,
            arrivedAt: Date(), estimatedReadingMinutes: nil,
            isRead: false, isStarred: false, isArchived: false,
            isHidden: false, faviconURL: nil
        )
    }

    @Test func needsReloadIstFalseBeiIdentischenSnapshots() {
        let rows = [makeSnapshot(id: "a1"), makeSnapshot(id: "a2")]
        #expect(NativeArticleListTableView.needsReload(current: rows, previous: rows) == false)
    }

    @Test func needsReloadIstTrueBeiUnterschiedlicherReihenfolge() {
        let a = makeSnapshot(id: "a1")
        let b = makeSnapshot(id: "a2")
        #expect(NativeArticleListTableView.needsReload(current: [a, b], previous: [b, a]) == true)
    }

    @Test func needsReloadIstTrueBeiZusaetzlicherZeile() {
        let a = makeSnapshot(id: "a1")
        let b = makeSnapshot(id: "a2")
        #expect(NativeArticleListTableView.needsReload(current: [a, b], previous: [a]) == true)
    }
}
