import Foundation
import SwiftData
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

private final class CapturingArticleSharingPresenter: ArticleSharingPresenter {
    var sharedURL: URL?

    func share(_ url: URL) {
        sharedURL = url
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

    @Test func toggleArchivedWechseltArchivStatus() {
        let article = Article(title: "Test", isArchived: false)
        let viewModel = ArticleViewModel()

        viewModel.toggleArchived(article)

        #expect(article.isArchived)

        viewModel.toggleArchived(article)

        #expect(!article.isArchived)
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

    @Test func shareOriginalTeiltGueltigenLink() {
        let article = Article(title: "Test", link: "https://example.com/article")
        let presenter = CapturingArticleSharingPresenter()
        let viewModel = ArticleViewModel()

        let didShare = viewModel.shareOriginal(article, presenter: presenter)

        #expect(didShare)
        #expect(presenter.sharedURL?.absoluteString == "https://example.com/article")
    }

    @MainActor
    @Test func markAllReadMarkiertArtikelUndKorrigiertFeedZaehler() throws {
        let context = try testContext()
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        feed.unreadCount = 2
        let unreadArticle = Article(title: "Ungelesen", isRead: false, feed: feed)
        let readArticle = Article(title: "Gelesen", isRead: true, feed: feed)
        context.insert(feed)
        context.insert(unreadArticle)
        context.insert(readArticle)
        try context.save()

        ArticleViewModel().markAllRead([unreadArticle, readArticle])

        #expect(unreadArticle.isRead)
        #expect(readArticle.isRead)
        #expect(feed.unreadCount == 1)
    }

    @MainActor
    @Test func markReadMitZeitoptionMarkiertNurPassendeUngeleseneArtikel() throws {
        let context = try testContext()
        let calendar = Calendar(identifier: .gregorian)
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 25,
            hour: 12
        )))
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        feed.unreadCount = 3
        let oldUnreadArticle = Article(
            title: "Alt und ungelesen",
            publishedAt: now.addingTimeInterval(-3 * 24 * 60 * 60),
            isRead: false,
            feed: feed
        )
        let newUnreadArticle = Article(
            title: "Neu und ungelesen",
            publishedAt: now.addingTimeInterval(-12 * 60 * 60),
            isRead: false,
            feed: feed
        )
        let oldReadArticle = Article(
            title: "Alt und gelesen",
            publishedAt: now.addingTimeInterval(-3 * 24 * 60 * 60),
            isRead: true,
            feed: feed
        )
        context.insert(feed)
        context.insert(oldUnreadArticle)
        context.insert(newUnreadArticle)
        context.insert(oldReadArticle)
        try context.save()

        ArticleViewModel().markRead(
            [oldUnreadArticle, newUnreadArticle, oldReadArticle],
            matching: .olderThanTwoDays,
            now: now,
            calendar: calendar
        )

        #expect(oldUnreadArticle.isRead)
        #expect(!newUnreadArticle.isRead)
        #expect(oldReadArticle.isRead)
        #expect(feed.unreadCount == 2)
    }

    @Test func articleMarkReadOptionenFilternNachAlterUndIgnorierenGeleseneArtikel() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 25,
            hour: 12
        )))
        let recentUnreadArticle = Article(
            title: "Neu",
            publishedAt: now.addingTimeInterval(-12 * 60 * 60),
            isRead: false
        )
        let twoDaysOldUnreadArticle = Article(
            title: "Zwei Tage",
            publishedAt: now.addingTimeInterval(-49 * 60 * 60),
            isRead: false
        )
        let threeDaysOldReadArticle = Article(
            title: "Gelesen",
            publishedAt: now.addingTimeInterval(-72 * 60 * 60),
            isRead: true
        )
        let undatedUnreadArticle = Article(title: "Ohne Datum", isRead: false)
        let articles = [
            recentUnreadArticle,
            twoDaysOldUnreadArticle,
            threeDaysOldReadArticle,
            undatedUnreadArticle
        ]

        #expect(ArticleMarkReadOption.olderThanOneDay.matchingArticles(
            in: articles,
            now: now,
            calendar: calendar
        ).map(\.title) == ["Zwei Tage"])
        #expect(ArticleMarkReadOption.olderThanTwoDays.matchingArticles(
            in: articles,
            now: now,
            calendar: calendar
        ).map(\.title) == ["Zwei Tage"])
        #expect(ArticleMarkReadOption.olderThanThreeDays.matchingArticles(
            in: articles,
            now: now,
            calendar: calendar
        ).isEmpty)
        #expect(ArticleMarkReadOption.allVisible.matchingArticles(
            in: articles,
            now: now,
            calendar: calendar
        ).map(\.title) == ["Neu", "Zwei Tage", "Ohne Datum"])
    }

    @MainActor
    @Test func deleteArticleEntferntArtikelUndKorrigiertFeedZaehler() throws {
        let context = try testContext()
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        feed.unreadCount = 1
        let article = Article(title: "Ungelesen", isRead: false, feed: feed)
        context.insert(feed)
        context.insert(article)
        try context.save()

        ArticleViewModel().deleteArticle(article, context: context)

        let articles = try context.fetch(FetchDescriptor<Article>())
        #expect(articles.isEmpty)
        #expect(feed.unreadCount == 0)
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
        #expect(state.previousArticle?.id == newest.id)
        #expect(state.nextArticle?.id == oldest.id)
    }

    @Test func articleNavigationStateHatLeerenStartzustandOhneArtikelliste() {
        let state = ArticleNavigationState.empty

        #expect(state.previousArticle == nil)
        #expect(state.nextArticle == nil)
    }

    @MainActor
    private func testContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            Article.self,
            Tag.self,
            Rule.self,
            RuleCondition.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        return ModelContext(container)
    }
}
