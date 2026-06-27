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

@MainActor
private final class CapturingArticleOfflineSaver: ArticleOfflineSaving {
    private(set) var savedArticleTitles: [String] = []

    func saveForOffline(_ article: Article) async {
        savedArticleTitles.append(article.title)
        article.offlineState = .feedContent
        article.offlineContent = article.content
    }
}

struct ArticleViewModelTests {

    @MainActor
    @Test func toggleReadWechseltGelesenStatus() {
        let article = Article(title: "Test", isRead: false)
        let viewModel = ArticleViewModel()

        viewModel.toggleRead(article)

        #expect(article.isRead)

        viewModel.toggleRead(article)

        #expect(!article.isRead)
    }

    @MainActor
    @Test func toggleStarredWechseltSternStatus() {
        let article = Article(title: "Test", isStarred: false)
        let viewModel = ArticleViewModel()

        viewModel.toggleStarred(article)

        #expect(article.isStarred)

        viewModel.toggleStarred(article)

        #expect(!article.isStarred)
    }

    @MainActor
    @Test func toggleStarredSpeichertBeiAktiverAutomatikOffline() async {
        let article = Article(title: "Test", content: "<p>Offline</p>", isStarred: false)
        let offlineSaver = CapturingArticleOfflineSaver()
        let viewModel = ArticleViewModel()

        await viewModel.toggleStarred(
            article,
            automaticallySaveForOffline: true,
            offlineSaver: offlineSaver
        )

        #expect(article.isStarred)
        #expect(offlineSaver.savedArticleTitles == ["Test"])
        #expect(article.offlineState == .feedContent)

        await viewModel.toggleStarred(
            article,
            automaticallySaveForOffline: true,
            offlineSaver: offlineSaver
        )

        #expect(!article.isStarred)
        #expect(offlineSaver.savedArticleTitles == ["Test"])
        #expect(article.offlineState == .feedContent)
    }

    @MainActor
    @Test func toggleStarredPersistiertSternStatusImContext() async throws {
        // Regression: toggleStarred sicherte früher nicht (anders als toggleRead).
        // Neuer Context auf demselben In-Memory-Store sieht den Stern nur,
        // wenn save() wirklich aufgerufen wurde.
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            RuleCondition.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let article = Article(title: "Test", isStarred: false)
        context.insert(article)
        try context.save()
        let viewModel = ArticleViewModel()

        await viewModel.toggleStarred(
            article,
            automaticallySaveForOffline: false,
            context: context
        )

        #expect(article.isStarred)

        let verifyContext = ModelContext(container)
        let fetched = try #require(try verifyContext.fetch(FetchDescriptor<Article>()).first)
        #expect(fetched.isStarred)
    }

    @MainActor
    @Test func toggleStarredFordertOhneAktiveAutomatikKeineOfflineKopieAn() async {
        let article = Article(title: "Test", content: "<p>Offline</p>", isStarred: false)
        let offlineSaver = CapturingArticleOfflineSaver()
        let viewModel = ArticleViewModel()

        await viewModel.toggleStarred(
            article,
            automaticallySaveForOffline: false,
            offlineSaver: offlineSaver
        )

        #expect(article.isStarred)
        #expect(offlineSaver.savedArticleTitles.isEmpty)
        #expect(article.offlineState == .none)
    }

    @MainActor
    @Test func toggleArchivedWechseltArchivStatus() {
        let article = Article(title: "Test", isArchived: false)
        let viewModel = ArticleViewModel()

        viewModel.toggleArchived(article)

        #expect(article.isArchived)

        viewModel.toggleArchived(article)

        #expect(!article.isArchived)
    }

    @MainActor
    @Test func optionaleArtikelAktionenIgnorierenFehlendeAuswahl() {
        let viewModel = ArticleViewModel()

        viewModel.toggleRead(nil)
        viewModel.toggleStarred(nil)
    }

    @MainActor
    @Test func optionaleArtikelAktionenSchaltenVorhandenenArtikel() {
        let article = Article(title: "Test", isRead: false, isStarred: false)
        let viewModel = ArticleViewModel()

        viewModel.toggleRead(article)
        viewModel.toggleStarred(article)

        #expect(article.isRead)
        #expect(article.isStarred)
    }

    @MainActor
    @Test func markReadIfNeededBeruecksichtigtEinstellung() {
        let article = Article(title: "Test", isRead: false)
        let viewModel = ArticleViewModel()

        viewModel.markReadIfNeeded(article, isEnabled: false)

        #expect(!article.isRead)

        viewModel.markReadIfNeeded(article, isEnabled: true)

        #expect(article.isRead)
    }

    @MainActor
    @Test func ungelesenZaehlerSchliesstVersteckteArtikelAus() throws {
        // Regression-Test: `feed.unreadCount` darf versteckte (isHidden)
        // ungelesene Artikel nicht zählen — die Artikelliste blendet sie aus,
        // sonst zeigt das Badge ungelesen an, obwohl keine sichtbar sind.
        let context = try testContext()
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let visibleArticle = Article(title: "Sichtbar", isRead: false, feed: feed)
        let hiddenArticle = Article(title: "Versteckt", isRead: false, feed: feed)
        hiddenArticle.isHidden = true
        context.insert(feed)
        [visibleArticle, hiddenArticle].forEach { context.insert($0) }
        try context.save()

        // Simuliert den Zustand nach einem Refresh, der beide gezählt hat.
        feed.unreadCount = 2

        let viewModel = ArticleViewModel()
        viewModel.markAllRead([visibleArticle], context: context)

        // Sichtbarer ist nun gelesen; der versteckte bleibt ungelesen, zählt
        // aber nicht mehr als ungelesen im Badge.
        #expect(feed.unreadCount == 0)
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

    @Test func originalURLResolverPrueftLinksOhneViewModelInstanz() throws {
        let article = Article(title: "Test", link: "https://example.com/article")

        let url = try #require(ArticleOriginalURLResolver.url(for: article))

        #expect(url.absoluteString == "https://example.com/article")
        #expect(ArticleOriginalURLResolver.url(for: Article(title: "Relativ", link: "/artikel")) == nil)
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
    @Test func markAllReadKorrigiertFeedZaehlerUeberFeedIDWennRelationshipFehlt() throws {
        let context = try testContext()
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        feed.unreadCount = 1
        let article = Article(title: "Ungelesen", isRead: false)
        article.feedID = feed.id
        context.insert(feed)
        context.insert(article)
        try context.save()

        ArticleViewModel().markAllRead([article], context: context)

        #expect(article.isRead)
        #expect(feed.unreadCount == 0)
    }

    @MainActor
    @Test func markAllReadSynchronisiertBereitsFalschenFeedZaehler() throws {
        let context = try testContext()
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        feed.unreadCount = 1000
        let firstArticle = Article(title: "Schon gelesen 1", isRead: true)
        let secondArticle = Article(title: "Schon gelesen 2", isRead: true)
        firstArticle.feedID = feed.id
        secondArticle.feedID = feed.id
        context.insert(feed)
        context.insert(firstArticle)
        context.insert(secondArticle)
        try context.save()

        ArticleViewModel().markAllRead([firstArticle, secondArticle], context: context)

        #expect(firstArticle.isRead)
        #expect(secondArticle.isRead)
        #expect(feed.unreadCount == 0)
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

    @Test func articleMarkReadAlleOptionVerwendetKlarenBefehlstext() {
        #expect(ArticleMarkReadOption.allVisible.label == L10n.articleMarkAllReadCommand)
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

extension ArticleViewModelTests {
    @Test func assignFeedSetztFeedUndFeedIDAtomar() {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let article = Article(title: "Artikel")

        article.assign(feed: feed)

        #expect(article.feed?.id == feed.id)
        #expect(article.feedID == feed.id)

        article.assign(feed: nil)

        #expect(article.feed == nil)
        #expect(article.feedID == nil)
    }
}
