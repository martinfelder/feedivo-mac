import Foundation
import Testing
@testable import Feedivo

private final class CapturingPasteboard: ArticleLinkPasteboard {
    var copiedString: String?

    func copy(_ string: String) {
        copiedString = string
    }
}

private final class CapturingURLOpener: ArticleURLOpener {
    var openedURL: URL?

    func open(_ url: URL) {
        openedURL = url
    }
}

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

    @Test func optionaleArtikelAktionenIgnorierenFehlendeAuswahl() {
        let viewModel = ArticleViewModel()

        viewModel.toggleRead(nil)
        viewModel.toggleStarred(nil)
    }

    @Test func optionaleArtikelAktionenSchaltenVorhandenenArtikel() {
        let article = Article(title: "Test", isRead: false, isStarred: false)
        let viewModel = ArticleViewModel()

        viewModel.toggleRead(article)
        viewModel.toggleStarred(article)

        #expect(article.isRead)
        #expect(article.isStarred)
    }

    @Test func markReadIfNeededBeruecksichtigtEinstellung() {
        let article = Article(title: "Test", isRead: false)
        let viewModel = ArticleViewModel()

        viewModel.markReadIfNeeded(article, isEnabled: false)

        #expect(!article.isRead)

        viewModel.markReadIfNeeded(article, isEnabled: true)

        #expect(article.isRead)
    }

    @Test func originalURLIgnoriertFehlendenOderUngueltigenLink() {
        let viewModel = ArticleViewModel()

        #expect(viewModel.originalURL(for: nil) == nil)
        #expect(viewModel.originalURL(for: Article(title: "Ohne Link")) == nil)
        #expect(viewModel.originalURL(for: Article(title: "Relativ", link: "/artikel")) == nil)
    }

    @Test func originalURLAkzeptiertAbsoluteLinks() throws {
        let article = Article(title: "Test", link: "https://example.com/article")
        let viewModel = ArticleViewModel()

        let url = try #require(viewModel.originalURL(for: article))

        #expect(url.absoluteString == "https://example.com/article")
    }

    @Test func copyLinkSchreibtGueltigenLinkInPasteboard() {
        let article = Article(title: "Test", link: "https://example.com/article")
        let pasteboard = CapturingPasteboard()
        let viewModel = ArticleViewModel()

        let didCopy = viewModel.copyLink(article, pasteboard: pasteboard)

        #expect(didCopy)
        #expect(pasteboard.copiedString == "https://example.com/article")
    }

    @Test func copyLinkIgnoriertArtikelOhneGueltigenLink() {
        let pasteboard = CapturingPasteboard()
        let viewModel = ArticleViewModel()

        let didCopy = viewModel.copyLink(Article(title: "Test", link: "/artikel"), pasteboard: pasteboard)

        #expect(!didCopy)
        #expect(pasteboard.copiedString == nil)
    }

    @Test func openOriginalOeffnetGueltigenLink() {
        let article = Article(title: "Test", link: "https://example.com/article")
        let opener = CapturingURLOpener()
        let viewModel = ArticleViewModel()

        let didOpen = viewModel.openOriginal(article, opener: opener)

        #expect(didOpen)
        #expect(opener.openedURL?.absoluteString == "https://example.com/article")
    }
}
