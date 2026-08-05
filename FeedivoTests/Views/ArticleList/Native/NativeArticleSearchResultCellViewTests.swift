import Testing
@testable import Feedivo

struct NativeArticleSearchResultCellViewTests {
    @Test func summaryTextWandeltHTMLZuPlainTextUm() {
        let text = NativeArticleSearchResultCellView.summaryText(from: "<p>Hallo <b>Welt</b></p>")
        #expect(text == ReaderContentRenderer.htmlToPlainText("<p>Hallo <b>Welt</b></p>"))
    }

    @Test func summaryTextIstNilOhneSummary() {
        #expect(NativeArticleSearchResultCellView.summaryText(from: nil) == nil)
    }

    @Test func summaryTextIstNilBeiLeererSummary() {
        #expect(NativeArticleSearchResultCellView.summaryText(from: "") == nil)
    }
}
