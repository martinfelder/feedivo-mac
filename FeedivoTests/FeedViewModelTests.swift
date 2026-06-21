import Foundation
import SwiftData
import Testing
@testable import Feedivo

struct FeedViewModelTests {

    @MainActor
    @Test func importOPMLFeedsLegtNeueFeedsAnUndUeberspringtDuplikate() async throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let existingFeed = Feed(
            url: "https://example.com/existing.xml",
            title: "Schon da"
        )
        context.insert(existingFeed)
        try context.save()

        let viewModel = FeedViewModel(
            fetchFeed: { urlString in
                ParsedFeed(
                    sourceURL: urlString,
                    title: "Neu",
                    description: nil,
                    siteURL: "https://example.com/new",
                    articles: []
                )
            },
            discoverFaviconURL: { _ in nil }
        )
        let result = try await viewModel.importOPMLFeeds(
            [
                OPMLFeed(
                    title: "Schon da aus OPML",
                    xmlURL: "https://example.com/existing.xml",
                    htmlURL: "https://example.com/",
                    folderName: "Tech"
                ),
                OPMLFeed(
                    title: "Neu",
                    xmlURL: "https://example.com/new.xml",
                    htmlURL: "https://example.com/new",
                    folderName: "News"
                )
            ],
            existingFeeds: [existingFeed],
            context: context
        )

        let feeds = try context.fetch(FetchDescriptor<Feed>())
        #expect(result.total == 2)
        #expect(result.imported == 1)
        #expect(result.skippedDuplicates == 1)
        #expect(feeds.count == 2)
        #expect(feeds.contains { $0.url == "https://example.com/existing.xml" && $0.title == "Schon da" })
        #expect(feeds.contains { $0.url == "https://example.com/new.xml" && $0.title == "Neu" && $0.folderName == "News" })
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func importOPMLFeedsAktualisiertNeueFeedsDirektNachDemImport() async throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let viewModel = FeedViewModel(
            fetchFeed: { urlString in
                #expect(urlString == "https://example.com/imported.xml")
                return ParsedFeed(
                    sourceURL: urlString,
                    title: "Aktualisierter Import Feed",
                    description: "Beschreibung aus Feed",
                    siteURL: "https://example.com/",
                    articles: [
                        ParsedArticle(
                            title: "Importierter Artikel",
                            link: "https://example.com/article",
                            summary: "Kurzfassung",
                            content: "Volltext",
                            publishedAt: Date(timeIntervalSince1970: 500),
                            imageURL: "https://example.com/image.jpg"
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in
                "https://example.com/favicon.png"
            }
        )

        let result = try await viewModel.importOPMLFeeds(
            [
                OPMLFeed(
                    title: "Titel aus OPML",
                    xmlURL: "https://example.com/imported.xml",
                    htmlURL: "https://example.com/old",
                    folderName: "News"
                )
            ],
            existingFeeds: [],
            context: context
        )

        let feeds = try context.fetch(FetchDescriptor<Feed>())
        let importedFeed = try #require(feeds.first)
        #expect(result.imported == 1)
        #expect(importedFeed.title == "Aktualisierter Import Feed")
        #expect(importedFeed.feedDescription == "Beschreibung aus Feed")
        #expect(importedFeed.siteURL == "https://example.com/")
        #expect(importedFeed.folderName == "News")
        #expect(importedFeed.faviconURL == "https://example.com/favicon.png")
        #expect(importedFeed.lastRefreshed != nil)
        #expect(importedFeed.articles.count == 1)
        #expect(importedFeed.unreadCount == 1)
        #expect(importedFeed.articles.first?.title == "Importierter Artikel")
        #expect(importedFeed.logEntries.contains { $0.kind == "info" && $0.message.contains("1") })
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isLoading)
    }

    @MainActor
    @Test func opmlFeedsForExportNutztAktuelleFeedMetadaten() {
        let feeds = [
            Feed(
                url: "https://example.com/feed.xml",
                title: "Example",
                siteURL: "https://example.com/",
                folderName: "Tech"
            )
        ]
        let viewModel = FeedViewModel()

        let opmlFeeds = viewModel.opmlFeedsForExport(from: feeds)

        #expect(opmlFeeds == [
            OPMLFeed(
                title: "Example",
                xmlURL: "https://example.com/feed.xml",
                htmlURL: "https://example.com/",
                folderName: "Tech"
            )
        ])
    }

    @MainActor
    @Test func renameFeedSpeichertAnzeigenamenUndBehältOriginalnamen() throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Original Feed")
        let viewModel = FeedViewModel()
        context.insert(feed)
        try context.save()

        viewModel.renameFeed(feed, displayTitle: "  Mein Feed  ", context: context)

        #expect(feed.title == "Mein Feed")
        #expect(feed.originalTitle == "Original Feed")
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func restoreOriginalFeedTitleSetztAnzeigenamenZurueck() throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let feed = Feed(
            url: "https://example.com/feed.xml",
            title: "Mein Feed",
            originalTitle: "Original Feed"
        )
        let viewModel = FeedViewModel()
        context.insert(feed)
        try context.save()

        viewModel.restoreOriginalFeedTitle(feed, context: context)

        #expect(feed.title == "Original Feed")
        #expect(feed.originalTitle == "Original Feed")
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func addFeedSpeichertEntdecktesFavicon() async throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let viewModel = FeedViewModel(
            fetchFeed: { urlString in
                ParsedFeed(
                    sourceURL: urlString,
                    title: "Feed mit Icon",
                    description: nil,
                    siteURL: "https://example.com/",
                    articles: []
                )
            },
            discoverFaviconURL: { siteURL in
                #expect(siteURL.absoluteString == "https://example.com/")
                return "https://example.com/apple-touch-icon.png"
            }
        )

        await viewModel.addFeed(urlString: "https://example.com/feed.xml", context: context)

        let feeds = try context.fetch(FetchDescriptor<Feed>())
        #expect(feeds.first?.faviconURL == "https://example.com/apple-touch-icon.png")
        #expect(feeds.first?.siteURL == "https://example.com/")
        #expect(feeds.first?.followedAt != nil)
        #expect(feeds.first?.logEntries.count == 1)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func refreshAllFeedsAktualisiertWeiterWennEinFeedFehlschlaegt() async throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let failingFeed = Feed(url: "https://example.com/fail.xml", title: "Fehler Feed")
        let successfulFeed = Feed(url: "https://example.com/success.xml", title: "Erfolgreicher Feed")
        let viewModel = FeedViewModel(
            fetchFeed: { urlString in
                if urlString == failingFeed.url {
                    throw TestFeedRefreshError()
                }

                return ParsedFeed(
                    sourceURL: urlString,
                    title: "Aktualisierter Feed",
                    description: "Neue Beschreibung",
                    siteURL: "https://example.com/",
                    articles: [
                        ParsedArticle(
                            title: "Neuer Artikel",
                            link: "https://example.com/new",
                            summary: "Neu",
                            content: nil,
                            publishedAt: Date(timeIntervalSince1970: 300),
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in
                "https://example.com/favicon.png"
            }
        )

        context.insert(failingFeed)
        context.insert(successfulFeed)
        try context.save()

        await viewModel.refreshAllFeeds([failingFeed, successfulFeed], context: context)

        #expect(failingFeed.articles.isEmpty)
        #expect(failingFeed.logEntries.contains { $0.kind == "error" })
        #expect(successfulFeed.title == "Aktualisierter Feed")
        #expect(successfulFeed.siteURL == "https://example.com/")
        #expect(successfulFeed.faviconURL == "https://example.com/favicon.png")
        #expect(successfulFeed.articles.contains { $0.link == "https://example.com/new" })
        #expect(successfulFeed.unreadCount == 1)
        #expect(successfulFeed.logEntries.contains { $0.kind == "info" })
        #expect(viewModel.errorMessage?.contains("Fehler Feed") == true)
        #expect(!viewModel.isLoading)
    }

    @MainActor
    @Test func refreshFeedFuegtNurNeueArtikelHinzuUndAktualisiertMetadaten() async throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let oldRefreshDate = Date(timeIntervalSince1970: 1)
        let existingPublishedAt = Date(timeIntervalSince1970: 100)
        let newPublishedAt = Date(timeIntervalSince1970: 200)
        let feed = Feed(
            url: "https://example.com/feed.xml",
            title: "Alter Titel",
            feedDescription: "Alte Beschreibung",
            lastRefreshed: oldRefreshDate
        )
        let existingArticle = Article(
            title: "Vorhandener Artikel",
            link: "https://example.com/1",
            summary: "Bleibt lokal erhalten",
            publishedAt: existingPublishedAt,
            isRead: true,
            feed: feed
        )
        feed.articles = [existingArticle]
        let viewModel = FeedViewModel(
            fetchFeed: { urlString in
                #expect(urlString == feed.url)
                return ParsedFeed(
                    sourceURL: urlString,
                    title: "Neuer Titel",
                    description: "Neue Beschreibung",
                    siteURL: "https://example.com/",
                    articles: [
                        ParsedArticle(
                            title: "Vorhandener Artikel aus Feed",
                            link: "https://example.com/1",
                            summary: "Soll nicht dupliziert werden",
                            content: nil,
                            publishedAt: existingPublishedAt,
                            imageURL: "https://example.com/existing-image.jpg"
                        ),
                        ParsedArticle(
                            title: "Neuer Artikel",
                            link: "https://example.com/2",
                            summary: "Neu",
                            content: "Inhalt",
                            publishedAt: newPublishedAt,
                            imageURL: "https://example.com/image.jpg"
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in
                "https://example.com/favicon.png"
            }
        )

        context.insert(feed)
        try context.save()

        await viewModel.refreshFeed(feed, context: context)

        #expect(feed.title == "Neuer Titel")
        #expect(feed.feedDescription == "Neue Beschreibung")
        #expect(feed.siteURL == "https://example.com/")
        #expect(feed.faviconURL == "https://example.com/favicon.png")
        #expect(feed.lastRefreshed ?? .distantPast > oldRefreshDate)
        #expect(feed.articles.count == 2)
        #expect(feed.unreadCount == 1)
        #expect(existingArticle.isRead)
        #expect(existingArticle.imageURL == "https://example.com/existing-image.jpg")
        #expect(feed.articles.contains { $0.link == "https://example.com/2" })
        #expect(feed.logEntries.contains { $0.kind == "info" && $0.message.contains("1") })
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isLoading)
    }

    @MainActor
    @Test func refreshFeedReichertNurNeueUndBildloseBestehendeArtikelMitSeitenbildernAn() async throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let existingWithImage = Article(
            title: "Bereits mit Bild",
            link: "https://example.com/has-image",
            imageURL: "https://example.com/existing.jpg",
            feed: feed
        )
        let existingWithoutImage = Article(
            title: "Noch ohne Bild",
            link: "https://example.com/missing-image",
            feed: feed
        )
        feed.articles = [existingWithImage, existingWithoutImage]
        context.insert(feed)
        try context.save()

        var enrichedArticleLinks: [String] = []
        let viewModel = FeedViewModel(
            fetchFeed: { urlString in
                ParsedFeed(
                    sourceURL: urlString,
                    title: "Feed",
                    description: nil,
                    siteURL: nil,
                    articles: [
                        ParsedArticle(
                            title: "Bereits mit Bild",
                            link: "https://example.com/has-image",
                            summary: nil,
                            content: nil,
                            publishedAt: nil,
                            imageURL: nil
                        ),
                        ParsedArticle(
                            title: "Noch ohne Bild",
                            link: "https://example.com/missing-image",
                            summary: nil,
                            content: nil,
                            publishedAt: nil,
                            imageURL: nil
                        ),
                        ParsedArticle(
                            title: "Neu ohne Bild",
                            link: "https://example.com/new",
                            summary: nil,
                            content: nil,
                            publishedAt: nil,
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in nil },
            enrichArticleImages: { articles in
                enrichedArticleLinks.append(contentsOf: articles.compactMap(\.link))
                return articles.map { article in
                    article.copy(imageURL: "\(article.link ?? "missing")/image.jpg")
                }
            }
        )

        await viewModel.refreshFeed(feed, context: context)

        #expect(enrichedArticleLinks == [
            "https://example.com/missing-image",
            "https://example.com/new"
        ])
        #expect(existingWithImage.imageURL == "https://example.com/existing.jpg")
        #expect(existingWithoutImage.imageURL == "https://example.com/missing-image/image.jpg")
        #expect(feed.articles.first { $0.link == "https://example.com/new" }?.imageURL == "https://example.com/new/image.jpg")
    }

    @MainActor
    @Test func refreshFeedBewahrtManuellenAnzeigenamenUndAktualisiertOriginalnamen() async throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let feed = Feed(
            url: "https://example.com/feed.xml",
            title: "Mein eigener Name",
            originalTitle: "Alter Feedname"
        )
        let viewModel = FeedViewModel(
            fetchFeed: { urlString in
                ParsedFeed(
                    sourceURL: urlString,
                    title: "Neuer Originalname",
                    description: nil,
                    siteURL: nil,
                    articles: []
                )
            },
            discoverFaviconURL: { _ in nil }
        )
        context.insert(feed)
        try context.save()

        await viewModel.refreshFeed(feed, context: context)

        #expect(feed.title == "Mein eigener Name")
        #expect(feed.originalTitle == "Neuer Originalname")
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func deleteFeedEntferntFeedAusSwiftData() throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Test Feed")
        let viewModel = FeedViewModel()

        context.insert(feed)
        try context.save()

        viewModel.deleteFeed(feed, context: context)

        let feeds = try context.fetch(FetchDescriptor<Feed>())
        #expect(feeds.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func deleteFeedIgnoriertFehlendeAuswahl() throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let viewModel = FeedViewModel()

        viewModel.deleteFeed(nil, context: context)

        let feeds = try context.fetch(FetchDescriptor<Feed>())
        #expect(feeds.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }
    @MainActor
    @Test func refreshAllFeedsAktualisiertFeedsParallel() async throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let feed1 = Feed(url: "https://example.com/1.xml", title: "Feed 1")
        let feed2 = Feed(url: "https://example.com/2.xml", title: "Feed 2")
        let feed3 = Feed(url: "https://example.com/3.xml", title: "Feed 3")
        context.insert(feed1)
        context.insert(feed2)
        context.insert(feed3)
        try context.save()

        actor ConcurrencyTracker {
            var active = 0
            var peak = 0
            func fetchStarted() { active += 1; peak = max(peak, active) }
            func fetchEnded() { active -= 1 }
        }
        let tracker = ConcurrencyTracker()

        let viewModel = FeedViewModel(
            fetchFeed: { urlString in
                await tracker.fetchStarted()
                try await Task.sleep(for: .milliseconds(100))
                await tracker.fetchEnded()
                return ParsedFeed(
                    sourceURL: urlString,
                    title: "Feed",
                    description: nil,
                    articles: []
                )
            },
            discoverFaviconURL: { _ in nil }
        )

        await viewModel.refreshAllFeeds([feed1, feed2, feed3], context: context)

        let peak = await tracker.peak
        #expect(peak > 1, "Feeds sollten parallel aktualisiert werden, nicht nacheinander")
    }
}

private struct TestFeedRefreshError: LocalizedError {
    var errorDescription: String? {
        "Test refresh failed"
    }
}
