import Testing
@testable import Feedivo

struct ArticleListDisplaySettingsTests {

    @Test func imagePositionResolvedFaelltBeiUnbekanntemRohwertAufDefaultZurueck() {
        #expect(ArticleListImagePosition.resolved(from: "left") == .left)
        #expect(ArticleListImagePosition.resolved(from: "right") == .right)
        #expect(ArticleListImagePosition.resolved(from: "hidden") == .hidden)
        #expect(ArticleListImagePosition.resolved(from: "unknown") == ArticleListImagePosition.defaultPosition)
    }

    @Test func imagePositionDefaultIstLinks() {
        #expect(ArticleListImagePosition.defaultPosition == .left)
    }

    @Test func feedNamePositionResolvedFaelltBeiUnbekanntemRohwertAufDefaultZurueck() {
        #expect(ArticleListFeedNamePosition.resolved(from: "beforeTitle") == .beforeTitle)
        #expect(ArticleListFeedNamePosition.resolved(from: "afterTitle") == .afterTitle)
        #expect(ArticleListFeedNamePosition.resolved(from: "unknown") == ArticleListFeedNamePosition.defaultPosition)
    }

    @Test func feedNamePositionDefaultIstNachDemTitel() {
        #expect(ArticleListFeedNamePosition.defaultPosition == .afterTitle)
    }

    @Test func feedNameVisibilityDefaultIstAn() {
        #expect(ArticleListFeedNameVisibilitySettings.defaultShowsFeedName == true)
    }
}
