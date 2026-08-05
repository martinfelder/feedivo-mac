import Foundation
import Testing
@testable import Feedivo

struct NativeArticleListRowCellViewTests {
    @Test func metadataTextKombiniertFeednameUndDatumMitTrennzeichen() {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        let text = NativeArticleListRowCellView.metadataText(
            feedTitle: "Beispiel-Feed",
            publishedAt: date,
            showsFeedNameAndFavicon: true,
            dateDisplayMode: .absolute
        )
        #expect(text == "Beispiel-Feed · \(date.feedivoDisplay(mode: .absolute))")
    }

    @Test func metadataTextLaesstFeednameWegWennNichtGezeigt() {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        let text = NativeArticleListRowCellView.metadataText(
            feedTitle: "Beispiel-Feed",
            publishedAt: date,
            showsFeedNameAndFavicon: false,
            dateDisplayMode: .absolute
        )
        #expect(text == date.feedivoDisplay(mode: .absolute))
    }

    @Test func metadataTextIstLeerOhneFeednameUndDatum() {
        let text = NativeArticleListRowCellView.metadataText(
            feedTitle: nil,
            publishedAt: nil,
            showsFeedNameAndFavicon: true,
            dateDisplayMode: .relative
        )
        #expect(text == "")
    }

    @Test func accessibilityLabelEnthaeltUngelesenUndSternHinweise() {
        let snapshot = ArticleListSnapshot(
            id: "1", feedID: "f1", feedTitle: "Feed", title: "Titel",
            summary: nil, link: nil, imageURL: nil, publishedAt: nil,
            arrivedAt: Date(), estimatedReadingMinutes: nil,
            isRead: false, isStarred: true, isArchived: false,
            isHidden: false, faviconURL: nil
        )
        let label = NativeArticleListRowCellView.accessibilityLabel(for: snapshot)
        #expect(label == "Titel, \(L10n.articleRowUnreadText), \(L10n.articleRowStarredText)")
    }

    @Test func accessibilityLabelIstNurTitelWennGelesenUndOhneStern() {
        let snapshot = ArticleListSnapshot(
            id: "1", feedID: "f1", feedTitle: "Feed", title: "Titel",
            summary: nil, link: nil, imageURL: nil, publishedAt: nil,
            arrivedAt: Date(), estimatedReadingMinutes: nil,
            isRead: true, isStarred: false, isArchived: false,
            isHidden: false, faviconURL: nil
        )
        let label = NativeArticleListRowCellView.accessibilityLabel(for: snapshot)
        #expect(label == "Titel")
    }
}
