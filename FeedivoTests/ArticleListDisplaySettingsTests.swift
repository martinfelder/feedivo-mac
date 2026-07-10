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

    @Test func summaryVisibilityDefaultIstAn() {
        #expect(ArticleListSummaryVisibilitySettings.defaultShowsSummary == true)
    }

    @Test func summaryLineCountDefaultIstZwei() {
        #expect(ArticleListSummaryLineCount.defaultValue == 2)
    }

    @Test func summaryLineCountResolvedFaengtUngueltigeWerteAb() {
        #expect(ArticleListSummaryLineCount.resolved(from: 1) == 1)
        #expect(ArticleListSummaryLineCount.resolved(from: 3) == 3)
        #expect(ArticleListSummaryLineCount.resolved(from: 0) == ArticleListSummaryLineCount.defaultValue)
        #expect(ArticleListSummaryLineCount.resolved(from: 4) == ArticleListSummaryLineCount.defaultValue)
        #expect(ArticleListSummaryLineCount.resolved(from: -1) == ArticleListSummaryLineCount.defaultValue)
    }
}
