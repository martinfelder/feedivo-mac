import Foundation
import SwiftData
import Testing
@testable import Feedivo

@Suite(.serialized)
struct ArticleListQueryTests {
    @Test func displayStateBlendetGeleseneArtikelStandardmaessigAus() {
        let unreadNewest = Article(
            title: "Ungelesen neu",
            publishedAt: Date(timeIntervalSince1970: 300),
            isRead: false
        )
        let readMiddle = Article(
            title: "Gelesen",
            publishedAt: Date(timeIntervalSince1970: 200),
            isRead: true
        )
        let unreadOldest = Article(
            title: "Ungelesen alt",
            publishedAt: Date(timeIntervalSince1970: 100),
            isRead: false
        )

        let state = ArticleListDisplayState(
            articles: [unreadNewest, readMiddle, unreadOldest],
            showsReadArticles: false
        )

        #expect(state.visibleArticles.map(\.title) == ["Ungelesen neu", "Ungelesen alt"])
        #expect(state.hiddenReadArticleCount == 1)
        #expect(state.shouldShowReadArticlesButton)
    }

    @Test func displaySnapshotBerechnetSichtbareArtikelUndZaehlerGemeinsam() {
        let unreadArticle = Article(title: "Ungelesen", isRead: false)
        let selectedReadArticle = Article(title: "Ausgewaehlt", isRead: true)
        let hiddenReadArticle = Article(title: "Verborgen", isRead: true)

        let state = ArticleListDisplayState(
            articles: [unreadArticle, selectedReadArticle, hiddenReadArticle],
            showsReadArticles: false,
            selectedArticle: selectedReadArticle
        )

        let snapshot = state.snapshot

        #expect(snapshot.visibleArticles.map(\.title) == ["Ungelesen", "Ausgewaehlt"])
        #expect(snapshot.hiddenReadArticleCount == 1)
        #expect(snapshot.shouldShowReadArticlesButton)
    }

    @Test func displayStateZeigtAlleArtikelNachAktivierung() {
        let unreadArticle = Article(title: "Ungelesen", isRead: false)
        let readArticle = Article(title: "Gelesen", isRead: true)

        let state = ArticleListDisplayState(
            articles: [unreadArticle, readArticle],
            showsReadArticles: true
        )

        #expect(state.visibleArticles.map(\.title) == ["Ungelesen", "Gelesen"])
        #expect(state.hiddenReadArticleCount == 0)
        #expect(!state.shouldShowReadArticlesButton)
    }

    @Test func displayStateHaeltAusgewaehltenGelesenenArtikelSichtbar() {
        let unreadArticle = Article(title: "Ungelesen", isRead: false)
        let selectedReadArticle = Article(title: "Ausgewaehlt", isRead: true)
        let hiddenReadArticle = Article(title: "Verborgen", isRead: true)

        let state = ArticleListDisplayState(
            articles: [unreadArticle, selectedReadArticle, hiddenReadArticle],
            showsReadArticles: false,
            selectedArticle: selectedReadArticle
        )

        #expect(state.visibleArticles.map(\.title) == ["Ungelesen", "Ausgewaehlt"])
        #expect(state.hiddenReadArticleCount == 1)
    }

    @Test func displayStateHaeltAutomatischGeleseneArtikelSichtbar() {
        let unreadArticle = Article(title: "Ungelesen", isRead: false)
        let autoReadArticle = Article(title: "Automatisch gelesen", isRead: true)
        let regularReadArticle = Article(title: "Vorher gelesen", isRead: true)

        let state = ArticleListDisplayState(
            articles: [unreadArticle, autoReadArticle, regularReadArticle],
            showsReadArticles: false,
            temporarilyVisibleReadArticleIDs: [autoReadArticle.persistentModelID]
        )

        #expect(state.visibleArticles.map(\.title) == ["Ungelesen", "Automatisch gelesen"])
        #expect(state.hiddenReadArticleCount == 1)
    }

    @Test func displayStateIgnoriertTemporärSichtbareUngeleseneArtikelBeimZaehlen() {
        let unreadArticle = Article(title: "Ungelesen", isRead: false)

        let state = ArticleListDisplayState(
            articles: [unreadArticle],
            showsReadArticles: false,
            temporarilyVisibleReadArticleIDs: [unreadArticle.persistentModelID]
        )

        #expect(state.visibleArticles.map(\.title) == ["Ungelesen"])
        #expect(state.hiddenReadArticleCount == 0)
    }

    @Test func displayStateBlendetHiddenArtikelAusNormalenListenAus() {
        let visibleArticle = Article(title: "Sichtbar", isRead: false)
        let hiddenArticle = Article(title: "Ausgeblendet", isRead: false, isHidden: true)

        let state = ArticleListDisplayState(
            articles: [visibleArticle, hiddenArticle],
            showsReadArticles: true
        )

        #expect(state.visibleArticles.map(\.title) == ["Sichtbar"])
        #expect(!state.shouldShowReadArticlesButton)
    }

    @Test func displayStateZeigtHiddenArtikelWennExplizitErlaubt() {
        let visibleArticle = Article(title: "Sichtbar", isRead: false)
        let hiddenArticle = Article(title: "Ausgeblendet", isRead: false, isHidden: true)

        let state = ArticleListDisplayState(
            articles: [visibleArticle, hiddenArticle],
            showsReadArticles: true,
            showsHiddenArticles: true
        )

        #expect(state.visibleArticles.map(\.title) == ["Sichtbar", "Ausgeblendet"])
        #expect(!state.shouldShowReadArticlesButton)
    }

    @Test func articleSortOptionSortiertArtikelNachBenutzerauswahl() {
        let feedA = Feed(url: "https://example.com/a.xml", title: "Alpha")
        let feedB = Feed(url: "https://example.com/b.xml", title: "Beta")
        let newest = Article(
            title: "Zebra",
            summary: Array(repeating: "wort", count: 220).joined(separator: " "),
            publishedAt: Date(timeIntervalSince1970: 300),
            feed: feedB
        )
        let oldest = Article(
            title: "Apfel",
            summary: "eins",
            publishedAt: Date(timeIntervalSince1970: 100),
            feed: feedA
        )
        let middle = Article(
            title: "Mitte",
            summary: Array(repeating: "wort", count: 420).joined(separator: " "),
            publishedAt: Date(timeIntervalSince1970: 200),
            feed: feedA
        )
        let articles = [middle, newest, oldest]

        #expect(ArticleSortOption.newestFirst.sorted(articles).map(\.title) == ["Zebra", "Mitte", "Apfel"])
        #expect(ArticleSortOption.oldestFirst.sorted(articles).map(\.title) == ["Apfel", "Mitte", "Zebra"])
        #expect(ArticleSortOption.feed.sorted(articles).map(\.title) == ["Mitte", "Apfel", "Zebra"])
        #expect(ArticleSortOption.title.sorted(articles).map(\.title) == ["Apfel", "Mitte", "Zebra"])
        #expect(ArticleSortOption.shortReadingTimeFirst.sorted(articles).map(\.title) == ["Apfel", "Zebra", "Mitte"])
    }

    @Test func articleSortOptionFaelltBeiUngueltigemRawValueAufStandardZurueck() {
        #expect(ArticleSortOption.resolved(from: "kaputt") == .newestFirst)
        #expect(ArticleSortOption.resolved(from: ArticleSortOption.title.rawValue) == .title)
    }

    @Test func articleFilterOptionFiltertArtikelNachBenutzerauswahl() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let unreadArticle = Article(title: "Ungelesen", isRead: false)
        let readArticle = Article(title: "Gelesen", isRead: true)
        let starredArticle = Article(title: "Stern", isStarred: true)
        let archivedArticle = Article(title: "Archiv", isArchived: true)
        let todayArticle = Article(title: "Heute", publishedAt: now)
        let oldArticle = Article(
            title: "Alt",
            publishedAt: calendar.date(byAdding: .day, value: -2, to: now)
        )
        let articles = [
            unreadArticle,
            readArticle,
            starredArticle,
            archivedArticle,
            todayArticle,
            oldArticle
        ]

        #expect(ArticleFilterOption.all.filtered(articles, now: now, calendar: calendar).map(\.title) == [
            "Ungelesen",
            "Gelesen",
            "Stern",
            "Archiv",
            "Heute",
            "Alt"
        ])
        #expect(ArticleFilterOption.unread.filtered(articles, now: now, calendar: calendar).map(\.title) == [
            "Ungelesen",
            "Stern",
            "Archiv",
            "Heute",
            "Alt"
        ])
        #expect(ArticleFilterOption.starred.filtered(articles, now: now, calendar: calendar).map(\.title) == ["Stern"])
        #expect(ArticleFilterOption.archived.filtered(articles, now: now, calendar: calendar).map(\.title) == ["Archiv"])
        #expect(ArticleFilterOption.today.filtered(articles, now: now, calendar: calendar).map(\.title) == ["Heute"])
    }

    @Test func articleFilterOptionFaelltBeiUngueltigemRawValueAufStandardZurueck() {
        #expect(ArticleFilterOption.resolved(from: "kaputt") == .all)
        #expect(ArticleFilterOption.resolved(from: ArticleFilterOption.archived.rawValue) == .archived)
    }

    @Test func articleSearchQuerySuchtInTitelZusammenfassungUndInhalt() {
        let titleArticle = Article(title: "SwiftUI Suche", summary: "Andere Worte", content: "Noch mehr Text")
        let summaryArticle = Article(title: "Nachrichten", summary: "Apple veröffentlicht Beta", content: "Noch mehr Text")
        let contentArticle = Article(title: "Analyse", summary: "Andere Worte", content: "Readability extrahiert Volltext")
        let unrelatedArticle = Article(title: "Sport", summary: "Fussball", content: "Resultate")
        let articles = [titleArticle, summaryArticle, contentArticle, unrelatedArticle]

        #expect(
            ArticleSearchQuery(text: "swiftui", field: .title)
                .filtered(articles)
                .map(\.title) == ["SwiftUI Suche"]
        )
        #expect(
            ArticleSearchQuery(text: "BETA", field: .summary)
                .filtered(articles)
                .map(\.title) == ["Nachrichten"]
        )
        #expect(
            ArticleSearchQuery(text: "volltext", field: .content)
                .filtered(articles)
                .map(\.title) == ["Analyse"]
        )
        #expect(
            ArticleSearchQuery(text: "apple", field: .all)
                .filtered(articles)
                .map(\.title) == ["Nachrichten"]
        )
    }

    @Test func articleSearchQueryIgnoriertLeerzeichenUndLeereSucheFiltertNicht() {
        let firstArticle = Article(title: "Erster Treffer", summary: "Swift", content: nil)
        let secondArticle = Article(title: "Zweiter Treffer", summary: "Mac", content: nil)
        let articles = [firstArticle, secondArticle]

        #expect(
            ArticleSearchQuery(text: "  swift  ", field: .all)
                .filtered(articles)
                .map(\.title) == ["Erster Treffer"]
        )
        #expect(
            ArticleSearchQuery(text: "   ", field: .all)
                .filtered(articles)
                .map(\.title) == ["Erster Treffer", "Zweiter Treffer"]
        )
    }

    @Test func articleListPreparedArticlesSortiertNurEinmalVorDemFiltern() {
        let oldUnreadArticle = Article(
            title: "Alt ungelesen",
            publishedAt: Date(timeIntervalSince1970: 100),
            isRead: false
        )
        let newReadArticle = Article(
            title: "Neu gelesen",
            publishedAt: Date(timeIntervalSince1970: 300),
            isRead: true
        )
        let middleUnreadArticle = Article(
            title: "Mitte ungelesen",
            publishedAt: Date(timeIntervalSince1970: 200),
            isRead: false
        )
        var sortCallCount = 0

        let preparedArticles = ArticleListPreparedArticles.prepare(
            articles: [oldUnreadArticle, newReadArticle, middleUnreadArticle],
            sortArticles: true,
            filterOption: .unread,
            sorter: { articles in
                sortCallCount += 1
                return ArticleSortOption.newestFirst.sorted(articles)
            }
        )

        #expect(sortCallCount == 1)
        #expect(preparedArticles.sorted.map(\.title) == [
            "Neu gelesen",
            "Mitte ungelesen",
            "Alt ungelesen"
        ])
        #expect(preparedArticles.filtered.map(\.title) == [
            "Mitte ungelesen",
            "Alt ungelesen"
        ])
    }

    @Test func articleListPreparedArticlesKombiniertFilterSortierungUndSuche() {
        let unreadNewest = Article(
            title: "Swift Suche",
            summary: "Mac",
            publishedAt: Date(timeIntervalSince1970: 300),
            isRead: false
        )
        let readMiddle = Article(
            title: "Swift gelesen",
            summary: "Mac",
            publishedAt: Date(timeIntervalSince1970: 200),
            isRead: true
        )
        let unreadOldest = Article(
            title: "Andere Meldung",
            summary: "Mac",
            publishedAt: Date(timeIntervalSince1970: 100),
            isRead: false
        )

        let preparedArticles = ArticleListPreparedArticles.prepare(
            articles: [unreadOldest, readMiddle, unreadNewest],
            sortArticles: true,
            filterOption: .unread,
            searchQuery: ArticleSearchQuery(text: "swift", field: .title),
            sorter: ArticleSortOption.newestFirst.sorted
        )

        #expect(preparedArticles.sorted.map(\.title) == [
            "Swift Suche",
            "Swift gelesen",
            "Andere Meldung"
        ])
        #expect(preparedArticles.filtered.map(\.title) == ["Swift Suche"])
    }

    @Test func articleSearchFiltersFilternNachFeedUndTag() {
        let selectedFeed = Feed(url: "https://example.com/swift.xml", title: "Swift Feed")
        let otherFeed = Feed(url: "https://example.com/mac.xml", title: "Mac Feed")
        let selectedTag = Tag(name: "Apple", colorHex: "#3B82F6")
        let feedTaggedFeed = Feed(url: "https://example.com/tagged.xml", title: "Tagged Feed")
        feedTaggedFeed.tags = [selectedTag]

        let feedArticle = Article(title: "Feed Treffer", feed: selectedFeed)
        let otherArticle = Article(title: "Anderer Feed", feed: otherFeed)
        let directTaggedArticle = Article(title: "Direktes Tag", feed: otherFeed)
        directTaggedArticle.tags = [selectedTag]
        let feedTaggedArticle = Article(title: "Feed Tag", feed: feedTaggedFeed)
        let unrelatedArticle = Article(title: "Ohne Treffer", feed: otherFeed)
        let articles = [
            feedArticle,
            otherArticle,
            directTaggedArticle,
            feedTaggedArticle,
            unrelatedArticle
        ]

        #expect(
            ArticleSearchQuery(
                filters: ArticleSearchFilters(feedID: selectedFeed.id)
            )
            .filtered(articles)
            .map(\.title) == ["Feed Treffer"]
        )
        #expect(
            ArticleSearchQuery(
                filters: ArticleSearchFilters(tagID: selectedTag.id)
            )
            .filtered(articles)
            .map(\.title) == ["Direktes Tag", "Feed Tag"]
        )
    }

    @Test func articleSearchFiltersFilternNachZeitraumUndStatus() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let todayArticle = Article(title: "Heute", publishedAt: now)
        let yesterdayArticle = Article(
            title: "Gestern",
            publishedAt: calendar.date(byAdding: .day, value: -1, to: now)
        )
        let lastWeekArticle = Article(
            title: "Letzte Woche",
            publishedAt: calendar.date(byAdding: .day, value: -8, to: now)
        )
        let readArticle = Article(title: "Gelesen", isRead: true)
        let starredArticle = Article(title: "Stern", isStarred: true)
        let archivedArticle = Article(title: "Archiv", isArchived: true)
        let articles = [
            todayArticle,
            yesterdayArticle,
            lastWeekArticle,
            readArticle,
            starredArticle,
            archivedArticle
        ]

        #expect(
            ArticleSearchQuery(
                filters: ArticleSearchFilters(date: .today),
                now: now,
                calendar: calendar
            )
            .filtered(articles)
            .map(\.title) == ["Heute"]
        )
        #expect(
            ArticleSearchQuery(
                filters: ArticleSearchFilters(date: .thisWeek),
                now: now,
                calendar: calendar
            )
            .filtered(articles)
            .map(\.title) == ["Heute", "Gestern"]
        )
        #expect(
            ArticleSearchQuery(filters: ArticleSearchFilters(status: .read))
                .filtered(articles)
                .map(\.title) == ["Gelesen"]
        )
        #expect(
            ArticleSearchQuery(filters: ArticleSearchFilters(status: .starred))
                .filtered(articles)
                .map(\.title) == ["Stern"]
        )
        #expect(
            ArticleSearchQuery(filters: ArticleSearchFilters(status: .archived))
                .filtered(articles)
                .map(\.title) == ["Archiv"]
        )
    }

    @Test func articleSearchFiltersKombinierenTextFeedTagUndStatus() {
        let feed = Feed(url: "https://example.com/swift.xml", title: "Swift Feed")
        let otherFeed = Feed(url: "https://example.com/mac.xml", title: "Mac Feed")
        let tag = Tag(name: "Release", colorHex: "#3B82F6")
        let matchingArticle = Article(
            title: "Swift Release",
            summary: "Neue Version",
            isRead: false,
            feed: feed
        )
        matchingArticle.tags = [tag]
        let readArticle = Article(
            title: "Swift Release gelesen",
            summary: "Neue Version",
            isRead: true,
            feed: feed
        )
        readArticle.tags = [tag]
        let wrongFeedArticle = Article(
            title: "Swift Release",
            summary: "Neue Version",
            isRead: false,
            feed: otherFeed
        )
        wrongFeedArticle.tags = [tag]
        let wrongTextArticle = Article(
            title: "Andere Meldung",
            summary: "Neue Version",
            isRead: false,
            feed: feed
        )
        wrongTextArticle.tags = [tag]
        let articles = [
            matchingArticle,
            readArticle,
            wrongFeedArticle,
            wrongTextArticle
        ]

        let query = ArticleSearchQuery(
            text: "swift",
            field: .title,
            filters: ArticleSearchFilters(
                feedID: feed.id,
                tagID: tag.id,
                status: .unread
            )
        )

        #expect(query.filtered(articles).map(\.title) == ["Swift Release"])
    }

    @Test func articleSearchWindowStateLiefertGlobalGefilterteUndSortierteTreffer() {
        let feed = Feed(url: "https://example.com/swift.xml", title: "Swift Feed")
        let otherFeed = Feed(url: "https://example.com/mac.xml", title: "Mac Feed")
        let tag = Tag(name: "Release", colorHex: "#3B82F6")
        let olderMatch = Article(
            title: "Swift Release alt",
            summary: "Update",
            publishedAt: Date(timeIntervalSince1970: 100),
            isRead: false,
            feed: feed
        )
        olderMatch.tags = [tag]
        let newerMatch = Article(
            title: "Swift Release neu",
            summary: "Update",
            publishedAt: Date(timeIntervalSince1970: 300),
            isRead: false,
            feed: feed
        )
        newerMatch.tags = [tag]
        let wrongFeedArticle = Article(
            title: "Swift Release anderer Feed",
            summary: "Update",
            publishedAt: Date(timeIntervalSince1970: 400),
            isRead: false,
            feed: otherFeed
        )
        wrongFeedArticle.tags = [tag]
        let readArticle = Article(
            title: "Swift Release gelesen",
            summary: "Update",
            publishedAt: Date(timeIntervalSince1970: 500),
            isRead: true,
            feed: feed
        )
        readArticle.tags = [tag]

        let state = ArticleSearchWindowState(
            searchText: "swift",
            field: .title,
            feedID: feed.id,
            tagID: tag.id,
            statusFilter: .unread
        )

        #expect(
            state.filteredArticles(from: [
                olderMatch,
                wrongFeedArticle,
                readArticle,
                newerMatch
            ])
            .map(\.title) == [
                "Swift Release neu",
                "Swift Release alt"
            ]
        )
    }

    @Test func articleInitialisiertDirekteFeedIDFuerSchnelleListenQueries() throws {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let article = Article(title: "Artikel", feed: feed)

        #expect(article.feedID == feed.id)
    }

    @MainActor
    @Test func listFetchDescriptorsLadenKeineSchwerenVolltextfelder() throws {
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let tag = Tag(name: "Swift")
        let folder = SmartFolder(
            name: "Mit Stern",
            matchMode: .all,
            conditions: [
                SmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.starred.rawValue
                )
            ]
        )

        let feedDescriptor = ArticleListQuery.feedFetchDescriptor(for: feed)
        let tagDescriptor = ArticleListQuery.tagFetchDescriptor(for: tag)
        let folderDescriptor = try #require(ArticleListQuery.smartFolderFetchDescriptor(for: folder))

        #expect(feedDescriptor.propertiesToFetch == ArticleListQuery.listPropertiesToFetch)
        #expect(tagDescriptor.propertiesToFetch == ArticleListQuery.listPropertiesToFetch)
        #expect(folderDescriptor.propertiesToFetch == ArticleListQuery.listPropertiesToFetch)
        #expect(!ArticleListQuery.listPropertiesToFetch.contains(\Article.content))
        #expect(!ArticleListQuery.listPropertiesToFetch.contains(\Article.offlineContent))
    }

    @MainActor
    @Test func feedFetchDescriptorLaedtNurArtikelDesAusgewaehltenFeedsSortiert() throws {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            FeedLogEntry.self,
            Article.self,
            Tag.self,
            Rule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let selectedFeed = Feed(url: "https://example.com/feed.xml", title: "Ausgewaehlt")
        let otherFeed = Feed(url: "https://example.com/other.xml", title: "Andere")
        let olderArticle = Article(
            title: "Aelter",
            publishedAt: Date(timeIntervalSince1970: 100),
            feed: selectedFeed
        )
        let newerArticle = Article(
            title: "Neuer",
            publishedAt: Date(timeIntervalSince1970: 300),
            feed: selectedFeed
        )
        let unrelatedArticle = Article(
            title: "Fremd",
            publishedAt: Date(timeIntervalSince1970: 500),
            feed: otherFeed
        )

        context.insert(selectedFeed)
        context.insert(otherFeed)
        context.insert(olderArticle)
        context.insert(newerArticle)
        context.insert(unrelatedArticle)
        try context.save()

        let articles = try context.fetch(
            ArticleListQuery.feedFetchDescriptor(for: selectedFeed)
        )

        #expect(articles.map(\.title) == ["Neuer", "Aelter"])
    }

    @MainActor
    @Test func feedFetchDescriptorBegrenztArtikelWennFetchLimitGesetztIst() throws {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            FeedLogEntry.self,
            Article.self,
            Tag.self,
            Rule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let selectedFeed = Feed(url: "https://example.com/feed.xml", title: "Ausgewaehlt")

        let newestArticle = Article(
            title: "Neu",
            publishedAt: Date(timeIntervalSince1970: 300),
            feed: selectedFeed
        )
        let middleArticle = Article(
            title: "Mitte",
            publishedAt: Date(timeIntervalSince1970: 200),
            feed: selectedFeed
        )
        let oldestArticle = Article(
            title: "Alt",
            publishedAt: Date(timeIntervalSince1970: 100),
            feed: selectedFeed
        )

        context.insert(selectedFeed)
        context.insert(newestArticle)
        context.insert(middleArticle)
        context.insert(oldestArticle)
        try context.save()

        let descriptor = ArticleListQuery.feedFetchDescriptor(
            for: selectedFeed,
            fetchLimit: 2
        )
        let articles = try context.fetch(descriptor)

        #expect(descriptor.fetchLimit == 2)
        #expect(descriptor.propertiesToFetch == ArticleListQuery.listPropertiesToFetch)
        #expect(articles.map(\.title) == ["Neu", "Mitte"])
    }

    @MainActor
    @Test func feedFetchDescriptorNutztDirekteFeedIDOhneRelationshipFallback() throws {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            FeedLogEntry.self,
            Article.self,
            Tag.self,
            Rule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let selectedFeed = Feed(url: "https://example.com/feed.xml", title: "Ausgewaehlt")
        let otherFeed = Feed(url: "https://example.com/other.xml", title: "Andere")
        let matchingArticle = Article(
            title: "Direkter Treffer",
            publishedAt: Date(timeIntervalSince1970: 300),
            feed: selectedFeed
        )
        let staleRelationshipArticle = Article(
            title: "Alte Relationship",
            publishedAt: Date(timeIntervalSince1970: 200),
            feed: selectedFeed
        )
        staleRelationshipArticle.feedID = otherFeed.id

        context.insert(selectedFeed)
        context.insert(otherFeed)
        context.insert(matchingArticle)
        context.insert(staleRelationshipArticle)
        try context.save()

        let articles = try context.fetch(
            ArticleListQuery.feedFetchDescriptor(for: selectedFeed)
        )

        #expect(articles.map(\.title) == ["Direkter Treffer"])
    }

    @MainActor
    @Test func tagFetchDescriptorLaedtNurArtikelMitAusgewaehltemTagSortiert() throws {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            FeedLogEntry.self,
            Article.self,
            Tag.self,
            Rule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let selectedTag = Tag(name: "Swift", colorHex: "#3B82F6")
        let otherTag = Tag(name: "Mac", colorHex: "#22C55E")
        let olderArticle = Article(
            title: "Aelter",
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        olderArticle.tags = [selectedTag]
        let newerArticle = Article(
            title: "Neuer",
            publishedAt: Date(timeIntervalSince1970: 300)
        )
        newerArticle.tags = [selectedTag, otherTag]
        let unrelatedArticle = Article(
            title: "Fremd",
            publishedAt: Date(timeIntervalSince1970: 500)
        )
        unrelatedArticle.tags = [otherTag]

        context.insert(selectedTag)
        context.insert(otherTag)
        context.insert(olderArticle)
        context.insert(newerArticle)
        context.insert(unrelatedArticle)
        try context.save()

        let articles = try context.fetch(
            ArticleListQuery.tagFetchDescriptor(for: selectedTag)
        )

        #expect(articles.map(\.title) == ["Neuer", "Aelter"])
    }

    @MainActor
    @Test func tagFetchDescriptorLaedtAuchArtikelAusGetaggtenFeedsOhneDuplikate() throws {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            FeedLogEntry.self,
            Article.self,
            Tag.self,
            Rule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let selectedTag = Tag(name: "Apple", colorHex: "#3B82F6")
        let taggedFeed = Feed(url: "https://example.com/tagged.xml", title: "Apple Feed")
        taggedFeed.tags = [selectedTag]
        let otherFeed = Feed(url: "https://example.com/other.xml", title: "Other Feed")
        let feedTaggedArticle = Article(
            title: "Feed-Tag Treffer",
            publishedAt: Date(timeIntervalSince1970: 300),
            feed: taggedFeed
        )
        let directTaggedArticle = Article(
            title: "Direkter Treffer",
            publishedAt: Date(timeIntervalSince1970: 200),
            feed: otherFeed
        )
        directTaggedArticle.tags = [selectedTag]
        let duplicateArticle = Article(
            title: "Doppelter Treffer",
            publishedAt: Date(timeIntervalSince1970: 100),
            feed: taggedFeed
        )
        duplicateArticle.tags = [selectedTag]
        let unrelatedArticle = Article(
            title: "Fremd",
            publishedAt: Date(timeIntervalSince1970: 500),
            feed: otherFeed
        )

        context.insert(selectedTag)
        context.insert(taggedFeed)
        context.insert(otherFeed)
        context.insert(feedTaggedArticle)
        context.insert(directTaggedArticle)
        context.insert(duplicateArticle)
        context.insert(unrelatedArticle)
        try context.save()

        let articles = try context.fetch(
            ArticleListQuery.tagFetchDescriptor(for: selectedTag)
        )

        #expect(articles.map(\.title) == [
            "Feed-Tag Treffer",
            "Direkter Treffer",
            "Doppelter Treffer"
        ])
    }

    @MainActor
    @Test func smartFolderFetchDescriptorLaedtFuerUngelesenAlleArtikelFuerFeedAehnlichesVerhalten() throws {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            FeedLogEntry.self,
            Article.self,
            Tag.self,
            Rule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let unreadOlderArticle = Article(
            title: "Ungelesen alt",
            publishedAt: Date(timeIntervalSince1970: 100),
            isRead: false
        )
        let unreadNewerArticle = Article(
            title: "Ungelesen neu",
            publishedAt: Date(timeIntervalSince1970: 300),
            isRead: false
        )
        let readArticle = Article(
            title: "Gelesen",
            publishedAt: Date(timeIntervalSince1970: 500),
            isRead: true
        )
        let folder = SmartFolder(
            name: "Ungelesen",
            matchMode: .all,
            conditions: [
                SmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.unread.rawValue
                )
            ]
        )

        context.insert(unreadOlderArticle)
        context.insert(unreadNewerArticle)
        context.insert(readArticle)
        try context.save()

        let descriptor = try #require(ArticleListQuery.smartFolderFetchDescriptor(for: folder))
        let articles = try context.fetch(descriptor)
        let hiddenState = ArticleListDisplayState(
            articles: articles,
            showsReadArticles: false
        )
        let selectedState = ArticleListDisplayState(
            articles: articles,
            showsReadArticles: false,
            selectedArticle: readArticle
        )

        #expect(articles.map(\.title) == ["Gelesen", "Ungelesen neu", "Ungelesen alt"])
        #expect(hiddenState.visibleArticles.map(\.title) == ["Ungelesen neu", "Ungelesen alt"])
        #expect(selectedState.visibleArticles.map(\.title) == ["Gelesen", "Ungelesen neu", "Ungelesen alt"])
    }

    @MainActor
    @Test func smartFolderFetchDescriptorLaedtGespeicherteArtikelDirektPerQuery() throws {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            FeedLogEntry.self,
            Article.self,
            Tag.self,
            Rule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let starredArticle = Article(
            title: "Stern",
            publishedAt: Date(timeIntervalSince1970: 100),
            isStarred: true
        )
        let archivedArticle = Article(
            title: "Archiv",
            publishedAt: Date(timeIntervalSince1970: 300),
            isArchived: true
        )
        let regularArticle = Article(
            title: "Normal",
            publishedAt: Date(timeIntervalSince1970: 500)
        )
        let folder = SmartFolder(
            name: "Gespeichert",
            matchMode: .any,
            conditions: [
                SmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.starred.rawValue
                ),
                SmartFolderCondition(
                    field: .status,
                    conditionOperator: .is,
                    value: SmartFolderStatusValue.archived.rawValue
                )
            ]
        )

        context.insert(starredArticle)
        context.insert(archivedArticle)
        context.insert(regularArticle)
        try context.save()

        let descriptor = try #require(ArticleListQuery.smartFolderFetchDescriptor(for: folder))
        let articles = try context.fetch(descriptor)

        #expect(articles.map(\.title) == ["Archiv", "Stern"])
    }

    @MainActor
    @Test func smartFolderFetchDescriptorFaelltFuerKomplexeTextOrdnerAufEngineZurueck() {
        let folder = SmartFolder(
            name: "Swift",
            matchMode: .all,
            conditions: [
                SmartFolderCondition(
                    field: .title,
                    conditionOperator: .contains,
                    value: "Swift"
                )
            ]
        )

        #expect(ArticleListQuery.smartFolderFetchDescriptor(for: folder) == nil)
    }

    @MainActor
    @Test func backfillSetztFehlendeDirekteFeedIDsAusDerRelationship() throws {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            FeedLogEntry.self,
            Article.self,
            Tag.self,
            Rule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let article = Article(title: "Altbestand", feed: feed)
        article.feedID = nil

        context.insert(feed)
        context.insert(article)
        try context.save()

        let updatedCount = try ArticleFeedIDBackfillService.backfillMissingFeedIDs(in: context)

        #expect(updatedCount == 1)
        #expect(article.feedID == feed.id)
    }

    @MainActor
    @Test func unreadCountBackfillSetztFeedZaehlerAusGespeichertenArtikeln() throws {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            FeedLogEntry.self,
            Article.self,
            Tag.self,
            Rule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        feed.articles = [
            Article(title: "Ungelesen", isRead: false, feed: feed),
            Article(title: "Gelesen", isRead: true, feed: feed)
        ]
        feed.unreadCount = 0

        context.insert(feed)
        try context.save()

        let testDefaults = UserDefaults(suiteName: "test-unread-backfill-\(UUID())")!
        let updatedCount = try FeedUnreadCountBackfillService.backfillUnreadCounts(
            in: context,
            defaults: testDefaults
        )

        #expect(updatedCount == 1)
        #expect(feed.unreadCount == 1)
    }

    @MainActor
    @Test func unreadCountBackfillZaehltArtikelUeberFeedIDOderRelationship() throws {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            FeedLogEntry.self,
            Article.self,
            Tag.self,
            Rule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let articleWithOnlyFeedID = Article(title: "Nur FeedID", isRead: false)
        articleWithOnlyFeedID.feedID = feed.id
        feed.unreadCount = 0

        context.insert(feed)
        context.insert(articleWithOnlyFeedID)
        try context.save()

        let testDefaults = UserDefaults(suiteName: "test-unread-backfill-feedid-\(UUID())")!
        let updatedCount = try FeedUnreadCountBackfillService.backfillUnreadCounts(
            in: context,
            defaults: testDefaults
        )

        #expect(updatedCount == 1)
        #expect(feed.unreadCount == 1)
    }

    @MainActor
    @Test func orphanedArticleCleanupEntferntArtikelOhneExistierendenFeed() throws {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            FeedLogEntry.self,
            Article.self,
            Tag.self,
            Rule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let validArticle = Article(title: "Gueltig", feed: feed)
        let staleArticle = Article(title: "Alter Offline-Rest")
        staleArticle.feedID = UUID()
        staleArticle.offlineState = .feedContent
        let articleWithoutFeed = Article(title: "Ohne Feed")

        context.insert(feed)
        context.insert(validArticle)
        context.insert(staleArticle)
        context.insert(articleWithoutFeed)
        try context.save()

        let removedCount = try OrphanedArticleCleanupService.removeArticlesWithoutExistingFeed(in: context)
        let articles = try context.fetch(FetchDescriptor<Article>())

        #expect(removedCount == 2)
        #expect(articles.map(\.title) == ["Gueltig"])
    }

    @MainActor
    @Test func orphanedArticleCleanupBewahrtArtikelMitIntakterFeedRelationship() throws {
        let container = try ModelContainer(
            for: Feed.self,
            FeedFolder.self,
            FeedLogEntry.self,
            Article.self,
            Tag.self,
            Rule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let article = Article(title: "Relationship intakt", feed: feed)
        article.feedID = nil

        context.insert(feed)
        context.insert(article)
        try context.save()

        let removedCount = try OrphanedArticleCleanupService.removeArticlesWithoutExistingFeed(in: context)
        let articles = try context.fetch(FetchDescriptor<Article>())

        #expect(removedCount == 0)
        #expect(articles.map(\.title) == ["Relationship intakt"])
    }
}
