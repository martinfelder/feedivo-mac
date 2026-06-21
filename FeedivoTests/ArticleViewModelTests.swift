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

    @Test func navigationFolgtSortierterArtikellisteUndStopptAnDenRaendern() {
        let newest = Article(title: "Neu", publishedAt: Date(timeIntervalSince1970: 300))
        let middle = Article(title: "Mitte", publishedAt: Date(timeIntervalSince1970: 200))
        let oldest = Article(title: "Alt", publishedAt: Date(timeIntervalSince1970: 100))
        let viewModel = ArticleViewModel()

        let sortedArticles = viewModel.sortedForList([oldest, newest, middle])

        #expect(sortedArticles.map(\.title) == ["Neu", "Mitte", "Alt"])
        #expect(viewModel.previousArticle(before: newest, in: sortedArticles) == nil)
        #expect(viewModel.nextArticle(after: newest, in: sortedArticles)?.id == middle.id)
        #expect(viewModel.previousArticle(before: middle, in: sortedArticles)?.id == newest.id)
        #expect(viewModel.nextArticle(after: middle, in: sortedArticles)?.id == oldest.id)
        #expect(viewModel.previousArticle(before: oldest, in: sortedArticles)?.id == middle.id)
        #expect(viewModel.nextArticle(after: oldest, in: sortedArticles) == nil)
    }

    @Test func articleNavigationStateSortiertSichtbareArtikelNurEinmal() {
        let newest = Article(title: "Neu", publishedAt: Date(timeIntervalSince1970: 300))
        let middle = Article(title: "Mitte", publishedAt: Date(timeIntervalSince1970: 200))
        let oldest = Article(title: "Alt", publishedAt: Date(timeIntervalSince1970: 100))
        var sortCallCount = 0

        let state = ArticleNavigationState(
            articles: [oldest, newest, middle],
            selectedArticle: middle
        ) { articles in
            sortCallCount += 1
            return articles.sorted {
                ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
            }
        }

        #expect(sortCallCount == 1)
        #expect(state.visibleArticles.map(\.id) == [newest.id, middle.id, oldest.id])
        #expect(state.previousArticle?.id == newest.id)
        #expect(state.nextArticle?.id == oldest.id)
    }
}
