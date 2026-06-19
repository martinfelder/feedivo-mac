import Testing
@testable import Feedivo

struct ArticleViewModelTests {

    @Test func toggleReadWechseltGelesenStatus() {
        let article = Article(title: "Test", isRead: false)
        let viewModel = ArticleViewModel()

        viewModel.toggleRead(article)

        #expect(article.isRead)

        viewModel.toggleRead(article)

        #expect(!article.isRead)
    }

    @Test func toggleStarredWechseltSternStatus() {
        let article = Article(title: "Test", isStarred: false)
        let viewModel = ArticleViewModel()

        viewModel.toggleStarred(article)

        #expect(article.isStarred)

        viewModel.toggleStarred(article)

        #expect(!article.isStarred)
    }

    @Test func markReadIfNeededBeruecksichtigtEinstellung() {
        let article = Article(title: "Test", isRead: false)
        let viewModel = ArticleViewModel()

        viewModel.markReadIfNeeded(article, isEnabled: false)

        #expect(!article.isRead)

        viewModel.markReadIfNeeded(article, isEnabled: true)

        #expect(article.isRead)
    }
}
