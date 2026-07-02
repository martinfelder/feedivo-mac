import Foundation
import SwiftData
import Testing
@testable import Feedivo

@Suite(.serialized)
struct FeedViewModelTests {
    private let articleRetentionDefaults: UserDefaults

    init() {
        let suiteName = "FeedivoTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        self.articleRetentionDefaults = defaults
    }

    private func makeViewModel(
        fetchFeed: @escaping (String) async throws -> ParsedFeed = FeedService.fetchFeed,
        fetchFeedConditionally: (@Sendable (String, FeedHTTPValidators) async throws -> ConditionalFeedFetchResult)? = nil,
        discoverFaviconURL: @escaping (URL) async -> String? = { siteURL in
            await FaviconService.discoverFaviconURL(siteURL: siteURL)
        },
        enrichArticleImages: @escaping ([ParsedArticle]) async -> [ParsedArticle] = { articles in
            await FeedService.enrichArticleImagesIfNeeded(in: articles)
        },
        notifyFeedRefresh: @escaping ([FeedRefreshNotificationResult]) async -> Void = { results in
            await FeedNotificationService.presentRefreshSummary(for: results)
        },
        notifyRuleNotifications: @escaping ([RuleNotificationResult]) async -> Void = { results in
            await FeedNotificationService.presentRuleSummary(for: results)
        },
        minimumRefreshStatusDuration: Duration = .zero
    ) -> FeedViewModel {
        FeedViewModel(
            fetchFeed: fetchFeed,
            fetchFeedConditionally: fetchFeedConditionally ?? { urlString, _ in
                .updated(try await fetchFeed(urlString), FeedHTTPValidators())
            },
            discoverFaviconURL: discoverFaviconURL,
            enrichArticleImages: enrichArticleImages,
            notifyFeedRefresh: notifyFeedRefresh,
            notifyRuleNotifications: notifyRuleNotifications,
            articleRetentionDefaults: articleRetentionDefaults,
            minimumRefreshStatusDuration: minimumRefreshStatusDuration
        )
    }

    @MainActor
    @Test func addFeedLehntDuplikatMitBekannterUrlAb() async throws {
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
        let existingFeed = Feed(url: "https://example.com/feed.xml", title: "Schon da")
        context.insert(existingFeed)
        try context.save()

        let viewModel = makeViewModel(
            fetchFeed: { _ in
                ParsedFeed(
                    sourceURL: "https://example.com/feed.xml",
                    title: "Duplikat",
                    description: nil,
                    siteURL: "https://example.com/",
                    articles: []
                )
            },
            discoverFaviconURL: { _ in nil }
        )

        await viewModel.addFeed(urlString: "https://example.com/feed.xml", context: context)

        #expect(try context.fetch(FetchDescriptor<Feed>()).count == 1)
        #expect(viewModel.errorMessage == L10n.feedErrorDuplicate)
    }

    @MainActor
    @Test func addFeedLegtNeuenFeedAnWennUrlNochUnbekannt() async throws {
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

        let viewModel = makeViewModel(
            fetchFeed: { _ in
                ParsedFeed(
                    sourceURL: "https://example.com/new.xml",
                    title: "Neu",
                    description: nil,
                    siteURL: "https://example.com/",
                    articles: []
                )
            },
            discoverFaviconURL: { _ in nil },
            enrichArticleImages: { articles in articles }
        )

        await viewModel.addFeed(urlString: "https://example.com/new.xml", context: context)

        #expect(try context.fetch(FetchDescriptor<Feed>()).count == 1)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func addFeedSpiegeltFeedUndArtikelNachSQLite() async throws {
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
        let sqliteDatabase = try FeedivoDatabase.inMemoryForTests()

        let viewModel = makeViewModel(
            fetchFeed: { _ in
                ParsedFeed(
                    sourceURL: "https://example.com/feed.xml",
                    title: "Example",
                    description: nil,
                    siteURL: "https://example.com/",
                    articles: [
                        ParsedArticle(
                            title: "First",
                            sourceID: "first",
                            link: "https://example.com/first",
                            summary: "Kurz",
                            content: "Inhalt",
                            publishedAt: Date(timeIntervalSince1970: 100),
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in nil },
            enrichArticleImages: { articles in articles }
        )

        await viewModel.addFeed(
            urlString: "https://example.com/feed.xml",
            context: context,
            sqliteDatabase: sqliteDatabase
        )

        let sqliteFeedResult = try FeedStore(database: sqliteDatabase).feed(url: "https://example.com/feed.xml")
        let sqliteFeed = try #require(sqliteFeedResult)
        let rows = try TimelineStore(database: sqliteDatabase).articles(
            scope: .feed(sqliteFeed.id),
            includeRead: true,
            includeHidden: false,
            limit: 20
        )

        #expect(sqliteFeed.title == "Example")
        #expect(sqliteFeed.websiteURL == "https://example.com/")
        #expect(sqliteFeed.unreadCount == 1)
        #expect(rows.map(\.title) == ["First"])
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func importOPMLFeedsLegtNeueFeedsAnUndUeberspringtDuplikate() async throws {
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
        let existingFeed = Feed(
            url: "https://example.com/existing.xml",
            title: "Schon da"
        )
        context.insert(existingFeed)
        try context.save()

        let viewModel = makeViewModel(
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
    @Test func importOPMLFeedsWirftWennBereitsEinImportLaeuft() async throws {
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
        let viewModel = makeViewModel()

        // isLoading simuliert einen laufenden Import/Refresh — der Aufruf darf
        // keinen vorgetäuschten Erfolg (imported: 0) zurückgeben, sondern muss
        // werfen, damit die Aufrufer den Zustand sichtbar melden.
        viewModel.isLoading = true

        await #expect(throws: FeedImportError.self) {
            try await viewModel.importOPMLFeeds(
                [OPMLFeed(title: "Blockiert", xmlURL: "https://example.com/x.xml", htmlURL: nil, folderName: nil)],
                existingFeeds: [],
                refreshAfterImport: false,
                context: context
            )
        }
    }

    @MainActor
    @Test func importOPMLFeedsAktualisiertNeueFeedsDirektNachDemImport() async throws {
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
        let viewModel = makeViewModel(
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
        #expect((importedFeed.articles ?? []).count == 1)
        #expect(importedFeed.unreadCount == 1)
        #expect((importedFeed.articles ?? []).first?.title == "Importierter Artikel")
        #expect((importedFeed.logEntries ?? []).contains { $0.kind == "info" && $0.message.contains("1") })
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isLoading)
        #expect(viewModel.operationProgress == nil)
    }

    @MainActor
    @Test func importOPMLFeedsSpeichertGewaehltesAktualisierungsintervall() async throws {
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
        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                ParsedFeed(sourceURL: urlString, title: "Import Feed", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )

        _ = try await viewModel.importOPMLFeeds(
            [
                OPMLFeed(
                    title: "Intervall Feed",
                    xmlURL: "https://example.com/interval.xml",
                    htmlURL: nil,
                    folderName: nil
                )
            ],
            existingFeeds: [],
            refreshIntervalMinutes: 15,
            context: context
        )

        let feeds = try context.fetch(FetchDescriptor<Feed>())
        let importedFeed = try #require(feeds.first)
        #expect(importedFeed.refreshIntervalMinutes == 15)
    }

    @MainActor
    @Test func importOPMLFeedsSetztSichtbarenFortschrittZurueck() async throws {
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
        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                ParsedFeed(sourceURL: urlString, title: "Import Feed", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )

        _ = try await viewModel.importOPMLFeeds(
            [
                OPMLFeed(title: "Feed 1", xmlURL: "https://example.com/1.xml", htmlURL: nil, folderName: nil),
                OPMLFeed(title: "Feed 2", xmlURL: "https://example.com/2.xml", htmlURL: nil, folderName: nil)
            ],
            existingFeeds: [],
            context: context
        )

        #expect(viewModel.operationProgress == nil)
    }

    @MainActor
    @Test func opmlImportPreviewMarkiertDuplikateUndNichtErreichbareFeeds() async throws {
        let existingFeed = Feed(url: "https://example.com/existing.xml", title: "Schon da")
        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                if urlString == "https://example.com/broken.xml" {
                    throw FeedServiceError.parsingFailed
                }

                return ParsedFeed(sourceURL: urlString, title: "OK", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )

        let rows = await viewModel.opmlImportPreviewRows(
            for: [
                OPMLFeed(title: "Neu", xmlURL: "https://example.com/new.xml", htmlURL: nil, folderName: "News"),
                OPMLFeed(title: "Schon da", xmlURL: "https://example.com/existing.xml", htmlURL: nil, folderName: "Tech"),
                OPMLFeed(title: "Kaputt", xmlURL: "https://example.com/broken.xml", htmlURL: nil, folderName: "News")
            ],
            existingFeeds: [existingFeed]
        )

        #expect(rows.map(\.status) == [.available, .duplicate, .unreachable])
        #expect(rows.map(\.isSelected) == [true, false, false])
    }

    @MainActor
    @Test func opmlImportPreviewMeldetSichtbarenPrueffortschrittInBeidePhasen() async throws {
        // Phase 1 (Duplikat-Schau) feuert onProgress pro Feed in Eingabe-Reihenfolge
        // (deterministisch: Titel + currentIndex 1..n). Phase 2 (paralleler Abruf)
        // feuert pro Completion einen Event; da die Completion-Reihenfolge nicht
        // deterministisch ist, wird hier nur die Anzahl (= Anzahl nicht-Duplikat-
        // Feeds) und das Set der currentIndex-Werte (1..k) geprüft — nicht die
        // Titel-Reihenfolge.
        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                ParsedFeed(sourceURL: urlString, title: "OK", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )
        var progressEvents: [OPMLImportPreviewProgress] = []

        _ = await viewModel.opmlImportPreviewRows(
            for: [
                OPMLFeed(title: "Erster Feed", xmlURL: "https://example.com/1.xml", htmlURL: nil, folderName: nil),
                OPMLFeed(title: "Zweiter Feed", xmlURL: "https://example.com/2.xml", htmlURL: nil, folderName: nil)
            ],
            existingFeeds: [],
            onProgress: { progressEvents.append($0) }
        )

        // Phase 1: beide Feeds sind keine Duplikate → zwei Events in
        // Eingabe-Reihenfolge mit currentIndex 1 und 2.
        let phase1Events = progressEvents.prefix(2)
        #expect(phase1Events.map(\.currentFeedTitle) == ["Erster Feed", "Zweiter Feed"])
        #expect(phase1Events.map(\.currentIndex) == [1, 2])
        #expect(phase1Events.map(\.displayText) == [
            "Feed 1 von 2 wird geprüft: Erster Feed",
            "Feed 2 von 2 wird geprüft: Zweiter Feed"
        ])

        // Phase 2: zwei Abrufe → zwei weitere Events. Titel-Reihenfolge nicht
        // deterministisch (parallele Tasks), daher nur Anzahl und das Set der
        // currentIndex-Werte (1, 2 — deterministischer MainActor-Zähler, der
        // pro Completion hochzählt). totalCount bleibt über beide Phasen 2.
        let phase2Events = progressEvents.dropFirst(2)
        #expect(phase2Events.count == 2)
        #expect(Set(phase2Events.map(\.currentIndex)) == Set(1...2))
        #expect(phase2Events.allSatisfy { $0.totalCount == 2 })
    }

    @MainActor
    @Test func importOPMLFeedsKannDuplikateBewusstImportierenUndRefreshUeberspringen() async throws {
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
        let existingFeed = Feed(url: "https://example.com/existing.xml", title: "Schon da")
        context.insert(existingFeed)
        try context.save()
        var refreshCallCount = 0
        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                refreshCallCount += 1
                return ParsedFeed(sourceURL: urlString, title: "Soll nicht aktualisieren", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )

        let result = try await viewModel.importOPMLFeeds(
            [
                OPMLFeed(
                    title: "Duplikat bewusst",
                    xmlURL: "https://example.com/existing.xml",
                    htmlURL: nil,
                    folderName: "Tech"
                )
            ],
            existingFeeds: [existingFeed],
            allowsDuplicates: true,
            refreshAfterImport: false,
            context: context
        )

        let feeds = try context.fetch(FetchDescriptor<Feed>())
        #expect(result.imported == 1)
        #expect(result.skippedDuplicates == 0)
        #expect(refreshCallCount == 0)
        #expect(feeds.count == 2)
        #expect(feeds.contains { $0.title == "Duplikat bewusst" && $0.url == "https://example.com/existing.xml" })
    }

    @MainActor
    @Test func opmlFeedsForExportNutztAktuelleFeedMetadaten() {
        let feeds = [
            Feed(
                url: "https://example.com/feed.xml",
                title: "Example",
                feedDescription: "Example Feed",
                siteURL: "https://example.com/",
                folderName: "Tech"
            )
        ]
        feeds[0].tags = [
            Tag(name: "Swift"),
            Tag(name: "Apple")
        ]
        let opmlFeeds = FeedViewModel.opmlFeedsForExport(from: feeds)

        #expect(opmlFeeds == [
            OPMLFeed(
                title: "Example",
                xmlURL: "https://example.com/feed.xml",
                htmlURL: "https://example.com/",
                folderName: "Tech",
                description: "Example Feed",
                tagNames: ["Apple", "Swift"]
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
            RuleCondition.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Original Feed")
        let viewModel = makeViewModel()
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
            RuleCondition.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let feed = Feed(
            url: "https://example.com/feed.xml",
            title: "Mein Feed",
            originalTitle: "Original Feed"
        )
        let viewModel = makeViewModel()
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
            RuleCondition.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let viewModel = makeViewModel(
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
        #expect((feeds.first?.logEntries ?? []).count == 1)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func refreshAllFeedsAktualisiertWeiterWennEinFeedFehlschlaegt() async throws {
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
        let failingFeed = Feed(url: "https://example.com/fail.xml", title: "Fehler Feed")
        let successfulFeed = Feed(url: "https://example.com/success.xml", title: "Erfolgreicher Feed")
        let viewModel = makeViewModel(
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

        #expect((failingFeed.articles ?? []).isEmpty)
        #expect((failingFeed.logEntries ?? []).contains { $0.kind == "error" })
        #expect(successfulFeed.title == "Aktualisierter Feed")
        #expect(successfulFeed.siteURL == "https://example.com/")
        #expect(successfulFeed.faviconURL == "https://example.com/favicon.png")
        #expect((successfulFeed.articles ?? []).contains { $0.link == "https://example.com/new" })
        #expect(successfulFeed.unreadCount == 1)
        #expect((successfulFeed.logEntries ?? []).contains { $0.kind == "info" })
        #expect(viewModel.errorMessage?.contains("Fehler Feed") == true)
        #expect(!viewModel.isLoading)
        #expect(viewModel.operationProgress == nil)
        #expect(viewModel.recentRefreshStatus?.newArticleCount == 1)
        #expect(viewModel.recentRefreshStatus?.failedFeedCount == 1)
        #expect(viewModel.recentRefreshStatus?.totalFeedCount == 2)
        #expect(viewModel.recentRefreshStatus?.hasFailures == true)
        #expect(viewModel.recentRefreshStatus?.isFullFailure == false)
        #expect(viewModel.refreshItems.first { $0.feedID == failingFeed.id }?.status == .failed)
        #expect(viewModel.refreshItems.first { $0.feedID == successfulFeed.id }?.status == .succeeded)
    }

    @MainActor
    @Test func refreshAllFeedsSetztSichtbarenFortschrittZurueck() async throws {
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
        let feed1 = Feed(url: "https://example.com/1.xml", title: "Feed 1")
        let feed2 = Feed(url: "https://example.com/2.xml", title: "Feed 2")
        context.insert(feed1)
        context.insert(feed2)
        try context.save()
        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                ParsedFeed(sourceURL: urlString, title: "Feed", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )

        await viewModel.refreshAllFeeds([feed1, feed2], context: context)

        #expect(viewModel.operationProgress == nil)
        #expect(viewModel.recentRefreshStatus?.newArticleCount == 0)
        #expect(viewModel.recentRefreshStatus?.failedFeedCount == 0)
        #expect(viewModel.recentRefreshStatus?.totalFeedCount == 2)
    }

    @MainActor
    @Test func refreshAllFeedsMerktAbschlussStatusMitNeuenArtikeln() async throws {
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
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        context.insert(feed)
        try context.save()
        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                ParsedFeed(
                    sourceURL: urlString,
                    title: "Feed",
                    description: nil,
                    articles: [
                        ParsedArticle(
                            title: "Artikel 1",
                            link: "https://example.com/1",
                            summary: nil,
                            content: nil,
                            publishedAt: Date(timeIntervalSince1970: 1),
                            imageURL: nil
                        ),
                        ParsedArticle(
                            title: "Artikel 2",
                            link: "https://example.com/2",
                            summary: nil,
                            content: nil,
                            publishedAt: Date(timeIntervalSince1970: 2),
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in nil }
        )

        await viewModel.refreshAllFeeds([feed], context: context)

        #expect(viewModel.recentRefreshStatus?.newArticleCount == 2)
        #expect(viewModel.recentRefreshStatus?.failedFeedCount == 0)
        #expect(viewModel.recentRefreshStatus?.totalFeedCount == 1)

        viewModel.clearRecentRefreshStatus()

        #expect(viewModel.recentRefreshStatus == nil)
    }

    @MainActor
    @Test func refreshAllFeedsHaeltFortschrittsstatusKurzSichtbar() async throws {
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
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        context.insert(feed)
        try context.save()
        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                ParsedFeed(sourceURL: urlString, title: "Feed", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil },
            minimumRefreshStatusDuration: .milliseconds(200)
        )
        let start = ContinuousClock().now

        await viewModel.refreshAllFeeds([feed], context: context)

        let elapsed = start.duration(to: ContinuousClock().now)
        #expect(elapsed >= .milliseconds(150))
        #expect(viewModel.operationProgress == nil)
        #expect(viewModel.recentRefreshStatus?.newArticleCount == 0)
    }

    @MainActor
    @Test func refreshAllFeedsMarkiertFeedWaehrendAbrufAlsAktualisierend() async throws {
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
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        context.insert(feed)
        try context.save()
        var viewModel: FeedViewModel!
        viewModel = makeViewModel(
            fetchFeed: { urlString in
                let item = viewModel.refreshItems.first { $0.feedURL == urlString }
                #expect(item?.status == .refreshing)

                return ParsedFeed(sourceURL: urlString, title: "Feed", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )

        await viewModel.refreshAllFeeds([feed], context: context)

        #expect(viewModel.refreshItems.first?.status == .succeeded)
    }

    @Test func refreshItemBatchStatusUpdateMarkiertMehrereFeedsInEinemSchritt() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let items = [
            FeedRefreshItem(feedID: firstID, feedTitle: "Feed 1", feedURL: "https://example.com/1.xml", status: .pending),
            FeedRefreshItem(feedID: secondID, feedTitle: "Feed 2", feedURL: "https://example.com/2.xml", status: .pending),
            FeedRefreshItem(feedID: thirdID, feedTitle: "Feed 3", feedURL: "https://example.com/3.xml", status: .failed)
        ]

        let updatedItems = FeedRefreshItemStatusBatch.updatedItems(
            items,
            feedIDs: Set([firstID, thirdID]),
            status: .refreshing
        )

        #expect(updatedItems.map(\.status) == [.refreshing, .pending, .refreshing])
    }

    @MainActor
    @Test func refreshFeedFuegtNurNeueArtikelHinzuUndAktualisiertMetadaten() async throws {
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
        let viewModel = makeViewModel(
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
        #expect((feed.articles ?? []).count == 2)
        #expect(feed.unreadCount == 1)
        #expect(existingArticle.isRead)
        #expect(existingArticle.imageURL == "https://example.com/existing-image.jpg")
        #expect((feed.articles ?? []).contains { $0.link == "https://example.com/2" })
        #expect((feed.logEntries ?? []).contains { $0.kind == "info" && $0.message.contains("1") })
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isLoading)
    }

    @MainActor
    @Test func refreshFeedSchreibtAktualisierteArtikelNachSQLite() async throws {
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
        let sqliteDatabase = try FeedivoDatabase.inMemoryForTests()
        let feed = Feed(
            url: "https://example.com/feed.xml",
            title: "Alter Titel",
            lastRefreshed: Date(timeIntervalSince1970: 1)
        )
        context.insert(feed)
        try context.save()
        try FeedStore(database: sqliteDatabase).save(
            FeedRecord(
                id: feed.id.uuidString,
                url: feed.url,
                title: feed.title,
                lastRefreshedAt: feed.lastRefreshed
            )
        )

        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                ParsedFeed(
                    sourceURL: urlString,
                    title: "Neuer Titel",
                    description: nil,
                    siteURL: "https://example.com/",
                    articles: [
                        ParsedArticle(
                            title: "SQLite Neuer Artikel",
                            sourceID: "sqlite-new",
                            link: "https://example.com/sqlite-new",
                            summary: "Neu",
                            content: "Inhalt",
                            publishedAt: Date(timeIntervalSince1970: 200),
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in nil },
            enrichArticleImages: { articles in articles }
        )

        await viewModel.refreshFeed(
            feed,
            context: context,
            sqliteDatabase: sqliteDatabase
        )

        let sqliteFeedResult = try FeedStore(database: sqliteDatabase).feed(url: feed.url)
        let sqliteFeed = try #require(sqliteFeedResult)
        let rows = try TimelineStore(database: sqliteDatabase).articles(
            scope: .feed(sqliteFeed.id),
            includeRead: true,
            includeHidden: false,
            limit: 20
        )

        #expect(sqliteFeed.title == "Neuer Titel")
        #expect(sqliteFeed.unreadCount == 1)
        #expect(rows.map(\.title) == ["SQLite Neuer Artikel"])
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func refreshFeedUeberspringtArtikelarbeitWennServerUnveraendertMeldet() async throws {
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
        let oldRefreshDate = Date(timeIntervalSince1970: 1)
        let feed = Feed(
            url: "https://example.com/feed.xml",
            title: "Stabiler Feed",
            lastRefreshed: oldRefreshDate,
            httpETag: "\"alt\"",
            httpLastModified: "Wed, 01 Jul 2026 10:00:00 GMT",
            httpContentHash: "alter-hash",
            lastHTTPStatusCode: 200
        )
        let existingArticle = Article(
            title: "Vorhandener Artikel",
            link: "https://example.com/1",
            summary: "Bleibt",
            publishedAt: Date(timeIntervalSince1970: 100),
            feed: feed
        )
        feed.articles = [existingArticle]
        feed.unreadCount = 1
        context.insert(feed)
        try context.save()

        let viewModel = makeViewModel(
            fetchFeed: { _ in
                Issue.record("Der normale Feed-Abruf darf bei diesem Test nicht genutzt werden.")
                return ParsedFeed(sourceURL: "", title: "", description: nil, articles: [])
            },
            fetchFeedConditionally: { urlString, validators in
                #expect(urlString == feed.url)
                #expect(validators.eTag == "\"alt\"")
                #expect(validators.lastModified == "Wed, 01 Jul 2026 10:00:00 GMT")
                #expect(validators.contentHash == "alter-hash")
                return .notModified(
                    FeedHTTPValidators(
                        eTag: "\"neu\"",
                        lastModified: "Thu, 02 Jul 2026 10:00:00 GMT",
                        contentHash: "alter-hash",
                        lastStatusCode: 304
                    )
                )
            },
            enrichArticleImages: { articles in
                Issue.record("Bildanreicherung muss bei unverändertem Feed übersprungen werden.")
                return articles
            }
        )

        await viewModel.refreshFeed(feed, context: context)

        #expect(feed.lastRefreshed ?? .distantPast > oldRefreshDate)
        #expect(feed.httpETag == "\"neu\"")
        #expect(feed.httpLastModified == "Thu, 02 Jul 2026 10:00:00 GMT")
        #expect(feed.httpContentHash == "alter-hash")
        #expect(feed.lastHTTPStatusCode == 304)
        #expect((feed.articles ?? []).count == 1)
        #expect(feed.unreadCount == 1)
        #expect((feed.logEntries ?? []).isEmpty)
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isLoading)
    }

    @MainActor
    @Test func refreshFeedLaesstUnveraendertenFeedOhneValidatorAenderungUnberuehrt() async throws {
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
        let oldRefreshDate = Date(timeIntervalSince1970: 1)
        let feed = Feed(
            url: "https://example.com/feed.xml",
            title: "Stabiler Feed",
            lastRefreshed: oldRefreshDate,
            httpETag: "\"stabil\"",
            httpLastModified: "Thu, 02 Jul 2026 10:00:00 GMT",
            httpContentHash: "stabiler-hash",
            lastHTTPStatusCode: 304
        )
        context.insert(feed)
        try context.save()

        let viewModel = makeViewModel(
            fetchFeed: { _ in
                Issue.record("Der normale Feed-Abruf darf bei unverändertem Conditional-Ergebnis nicht genutzt werden.")
                return ParsedFeed(sourceURL: "", title: "", description: nil, articles: [])
            },
            fetchFeedConditionally: { _, validators in
                #expect(validators.eTag == "\"stabil\"")
                #expect(validators.lastModified == "Thu, 02 Jul 2026 10:00:00 GMT")
                #expect(validators.contentHash == "stabiler-hash")
                #expect(validators.lastStatusCode == 304)
                return .notModified(validators)
            }
        )

        await viewModel.refreshFeed(feed, context: context)

        #expect(feed.lastRefreshed == oldRefreshDate)
        #expect(feed.httpETag == "\"stabil\"")
        #expect(feed.httpLastModified == "Thu, 02 Jul 2026 10:00:00 GMT")
        #expect(feed.httpContentHash == "stabiler-hash")
        #expect(feed.lastHTTPStatusCode == 304)
        #expect((feed.logEntries ?? []).isEmpty)
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isLoading)
    }

    @MainActor
    @Test func refreshFeedErkenntBestehendeArtikelUeberFeedIDOhneRelationshipScan() async throws {
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
        let publishedAt = Date(timeIntervalSince1970: 100)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let existingArticle = Article(
            title: "Schon vorhanden",
            link: "https://example.com/1",
            summary: "Alt",
            publishedAt: publishedAt
        )
        existingArticle.feedID = feed.id

        do {
            let setupContext = ModelContext(container)
            setupContext.insert(feed)
            setupContext.insert(existingArticle)
            try setupContext.save()
        }

        let feedID = feed.id
        let feedDescriptor = FetchDescriptor<Feed>(
            predicate: #Predicate<Feed> { storedFeed in
                storedFeed.id == feedID
            }
        )
        let refreshFeed = try #require(context.fetch(feedDescriptor).first)
        let optionalFeedID = Optional(feedID)
        let articleDescriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.feedID == optionalFeedID
            }
        )
        let storedExistingArticle = try #require(context.fetch(articleDescriptor).first)

        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                ParsedFeed(
                    sourceURL: urlString,
                    title: "Feed",
                    description: nil,
                    articles: [
                        ParsedArticle(
                            title: "Schon vorhanden",
                            link: "https://example.com/1",
                            summary: "Aktualisiert",
                            content: nil,
                            publishedAt: publishedAt,
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in nil }
        )

        await viewModel.refreshFeed(refreshFeed, context: context)

        let articles = try context.fetch(FetchDescriptor<Article>())
        #expect(articles.count == 1)
        #expect(storedExistingArticle.summary == "Aktualisiert")
    }

    @Test func refreshLookupLaedtKeineSchwerenArtikeltexte() {
        #expect(Article.refreshLookupPropertiesToFetch.contains(\.summary))
        #expect(!Article.refreshLookupPropertiesToFetch.contains(\.content))
        #expect(!Article.refreshLookupPropertiesToFetch.contains(\.offlineContent))
    }

    @Test func storedArticleRefreshFieldUpdateSchreibtNurEchteAenderungen() {
        #expect(StoredArticleRefreshFieldUpdate.replacement(for: "Kurzfassung", from: "Kurzfassung") == nil)
        #expect(StoredArticleRefreshFieldUpdate.replacement(for: "Kurzfassung", from: "Neue Kurzfassung") == "Neue Kurzfassung")
        #expect(StoredArticleRefreshFieldUpdate.missingReplacement(for: "Vorhanden", from: "Nachtrag") == nil)
        #expect(StoredArticleRefreshFieldUpdate.missingReplacement(for: nil, from: "Nachtrag") == "Nachtrag")

        var didReadExistingContent = false
        let contentUpdate = StoredArticleRefreshFieldUpdate.missingReplacement(
            for: {
                didReadExistingContent = true
                return nil
            }(),
            from: nil
        )

        #expect(contentUpdate == nil)
        #expect(!didReadExistingContent)
    }

    @MainActor
    @Test func refreshFeedBewahrtGelesenStatusBeiStabilerQuelleUndGeaendertemLink() async throws {
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
        let publishedAt = Date(timeIntervalSince1970: 100)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let existingArticle = Article(
            title: "Schon gelesener Artikel",
            link: "https://example.com/1?utm_source=feedivo",
            summary: "Lokale Kurzfassung",
            publishedAt: publishedAt,
            sourceID: "artikel-1",
            isRead: true,
            feed: feed
        )
        feed.articles = [existingArticle]
        feed.unreadCount = 0

        context.insert(feed)
        try context.save()

        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                ParsedFeed(
                    sourceURL: urlString,
                    title: "Feed",
                    description: nil,
                    articles: [
                        ParsedArticle(
                            title: "Schon gelesener Artikel",
                            sourceID: "artikel-1",
                            link: "https://example.com/1?utm_source=newsletter",
                            summary: "Aktualisierte Kurzfassung",
                            content: nil,
                            publishedAt: publishedAt,
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in nil }
        )

        await viewModel.refreshFeed(feed, context: context)

        #expect((feed.articles ?? []).count == 1)
        #expect(existingArticle.isRead)
        #expect(existingArticle.summary == "Aktualisierte Kurzfassung")
        #expect(feed.unreadCount == 0)
    }

    @MainActor
    @Test func refreshFeedErkenntAltbestandOhneQuellenIDUeberTitelUndDatum() async throws {
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
        let publishedAt = Date(timeIntervalSince1970: 100)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let existingArticle = Article(
            title: "Schon gelesener Artikel",
            link: "https://example.com/1?utm_source=alt",
            summary: "Lokale Kurzfassung",
            publishedAt: publishedAt,
            isRead: true,
            feed: feed
        )
        feed.articles = [existingArticle]
        feed.unreadCount = 0

        context.insert(feed)
        try context.save()

        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                ParsedFeed(
                    sourceURL: urlString,
                    title: "Feed",
                    description: nil,
                    articles: [
                        ParsedArticle(
                            title: "Schon gelesener Artikel",
                            sourceID: "artikel-1",
                            link: "https://example.com/1?utm_source=neu",
                            summary: "Aktualisierte Kurzfassung",
                            content: nil,
                            publishedAt: publishedAt,
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in nil }
        )

        await viewModel.refreshFeed(feed, context: context)

        #expect((feed.articles ?? []).count == 1)
        #expect(existingArticle.isRead)
        #expect(existingArticle.sourceID == "artikel-1")
        #expect(existingArticle.summary == "Aktualisierte Kurzfassung")
        #expect(feed.unreadCount == 0)
    }

    @MainActor
    @Test func refreshFeedImportiertAbgelaufeneArtikelBeiAktiverAufbewahrungNicht() async throws {
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
        let now = Date(timeIntervalSince1970: 10_000_000)
        let oldPublishedAt = now.addingTimeInterval(-40 * 24 * 60 * 60)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        feed.articleRetentionOverridesGlobalSetting = true
        feed.articleRetentionIsEnabled = true
        feed.articleRetentionDays = 30
        feed.unreadCount = 0

        context.insert(feed)
        try context.save()

        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                ParsedFeed(
                    sourceURL: urlString,
                    title: "Feed",
                    description: nil,
                    articles: [
                        ParsedArticle(
                            title: "Alter gelesener Artikel",
                            sourceID: "old-1",
                            link: "https://example.com/old",
                            summary: "Noch im Feed enthalten",
                            content: nil,
                            publishedAt: oldPublishedAt,
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in nil }
        )

        await viewModel.refreshFeed(feed, context: context)

        let feedID = feed.id
        let articlesAfterRefresh = try context.fetch(
            FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.feedID == feedID
                }
            )
        )
        #expect(articlesAfterRefresh.isEmpty)
        #expect(feed.unreadCount == 0)
    }

    @MainActor
    @Test func refreshFeedImportiertAbgelaufeneArtikelBeiGlobalAktiverAufbewahrungNicht() async throws {
        articleRetentionDefaults.set(true, forKey: ArticleRetentionSettings.isEnabledKey)
        articleRetentionDefaults.set(30, forKey: ArticleRetentionSettings.retentionDaysKey)

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
        let oldPublishedAt = Date().addingTimeInterval(-40 * 24 * 60 * 60)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")

        context.insert(feed)
        try context.save()

        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                ParsedFeed(
                    sourceURL: urlString,
                    title: "Feed",
                    description: nil,
                    articles: [
                        ParsedArticle(
                            title: "Alter Artikel aus globaler Aufbewahrung",
                            sourceID: "old-global-1",
                            link: "https://example.com/old-global",
                            summary: "Noch im Feed enthalten",
                            content: nil,
                            publishedAt: oldPublishedAt,
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in nil }
        )

        await viewModel.refreshFeed(feed, context: context)

        #expect((feed.articles ?? []).isEmpty)
        #expect(feed.unreadCount == 0)
    }

    @MainActor
    @Test func refreshFeedTraegtSpaeterGeliefertenOfflineContentBeiBestehendenArtikelnNach() async throws {
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
        let publishedAt = Date(timeIntervalSince1970: 100)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Feed")
        let existingArticle = Article(
            title: "Vorhandener Artikel",
            link: "https://example.com/1",
            summary: "Kurzfassung",
            content: nil,
            publishedAt: publishedAt,
            feed: feed
        )
        feed.articles = [existingArticle]
        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                ParsedFeed(
                    sourceURL: urlString,
                    title: "Feed",
                    description: nil,
                    articles: [
                        ParsedArticle(
                            title: "Vorhandener Artikel",
                            link: "https://example.com/1",
                            summary: "Aktualisierte Kurzfassung",
                            content: "<p>Nachgelieferter Volltext</p>",
                            publishedAt: publishedAt,
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in nil }
        )

        context.insert(feed)
        try context.save()

        await viewModel.refreshFeed(feed, context: context)

        #expect((feed.articles ?? []).count == 1)
        #expect(existingArticle.content == "<p>Nachgelieferter Volltext</p>")
        #expect(existingArticle.summary == "Aktualisierte Kurzfassung")
    }

    @MainActor
    @Test func refreshFeedWendetRegelnAufNeueArtikelAn() async throws {
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
        let feed = Feed(url: "https://example.com/feed.xml", title: "Alter Feed")
        let existingArticle = Article(
            title: "Swift Altbestand",
            link: "https://example.com/old",
            feed: feed
        )
        feed.articles = [existingArticle]
        let tag = Tag(name: "Swift", colorHex: "#3B82F6")
        let rule = Rule(name: "Swift Titel")
        rule.conditions = [
            RuleCondition(field: "title", conditionOperator: "contains", value: "swift")
        ]
        rule.assignTag = tag
        context.insert(feed)
        context.insert(tag)
        context.insert(rule)
        try context.save()

        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                ParsedFeed(
                    sourceURL: urlString,
                    title: "Neuer Feed",
                    description: nil,
                    siteURL: nil,
                    articles: [
                        ParsedArticle(
                            title: "Swift Altbestand",
                            link: "https://example.com/old",
                            summary: nil,
                            content: nil,
                            publishedAt: nil,
                            imageURL: nil
                        ),
                        ParsedArticle(
                            title: "Swift Neuer Artikel",
                            link: "https://example.com/new",
                            summary: nil,
                            content: nil,
                            publishedAt: nil,
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in nil }
        )

        await viewModel.refreshFeed(feed, context: context)

        let newArticle = try #require((feed.articles ?? []).first { $0.link == "https://example.com/new" })
        #expect((newArticle.tags ?? []).map(\.name) == ["Swift"])
        #expect((existingArticle.tags ?? []).isEmpty)
    }

    @MainActor
    @Test func refreshFeedReichertNurNeueUndBildloseBestehendeArtikelMitSeitenbildernAn() async throws {
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
        let viewModel = makeViewModel(
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
        #expect((feed.articles ?? []).first { $0.link == "https://example.com/new" }?.imageURL == "https://example.com/new/image.jpg")
    }

    @MainActor
    @Test func refreshFeedBewahrtManuellenAnzeigenamenUndAktualisiertOriginalnamen() async throws {
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
        let feed = Feed(
            url: "https://example.com/feed.xml",
            title: "Mein eigener Name",
            originalTitle: "Alter Feedname"
        )
        let viewModel = makeViewModel(
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
            RuleCondition.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let feed = Feed(url: "https://example.com/feed.xml", title: "Test Feed")
        let viewModel = makeViewModel()

        context.insert(feed)
        try context.save()

        viewModel.deleteFeed(feed, context: context)

        let feeds = try context.fetch(FetchDescriptor<Feed>())
        #expect(feeds.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func deleteFeedEntferntZugehoerigeArtikelAusSwiftData() throws {
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
        let feed = Feed(url: "https://example.com/feed.xml", title: "Test Feed")
        let article = Article(title: "Offline Rest", feed: feed)
        article.offlineState = .feedContent
        feed.articles = [article]
        let viewModel = makeViewModel()

        context.insert(feed)
        try context.save()

        viewModel.deleteFeed(feed, context: context)

        let articles = try context.fetch(FetchDescriptor<Article>())
        #expect(articles.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func deleteFeedEntferntAuchArtikelMitNurDirekterFeedID() throws {
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
        let feed = Feed(url: "https://example.com/feed.xml", title: "Test Feed")
        let article = Article(title: "Direkter Rest")
        article.feedID = feed.id
        article.offlineState = .feedContent
        let viewModel = makeViewModel()

        context.insert(feed)
        context.insert(article)
        try context.save()

        viewModel.deleteFeed(feed, context: context)

        let articles = try context.fetch(FetchDescriptor<Article>())
        #expect(articles.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func deleteFeedIgnoriertFehlendeAuswahl() throws {
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
        let viewModel = makeViewModel()

        viewModel.deleteFeed(nil, context: context)

        let feeds = try context.fetch(FetchDescriptor<Feed>())
        #expect(feeds.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }
    @MainActor
    @Test func importOPMLFeedsAktualisiertNeueFeedsMitBegrenzterParallelitaet() async throws {
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

        actor ConcurrencyTracker {
            var active = 0
            var peak = 0
            func fetchStarted() { active += 1; peak = max(peak, active) }
            func fetchEnded() { active -= 1 }
        }
        let tracker = ConcurrencyTracker()

        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                await tracker.fetchStarted()
                try await Task.sleep(for: .milliseconds(100))
                await tracker.fetchEnded()
                return ParsedFeed(sourceURL: urlString, title: "Feed", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )

        _ = try await viewModel.importOPMLFeeds(
            (1 ... 10).map { index in
                OPMLFeed(
                    title: "Feed \(index)",
                    xmlURL: "https://example.com/\(index).xml",
                    htmlURL: nil,
                    folderName: nil
                )
            },
            existingFeeds: [],
            context: context
        )

        let peak = await tracker.peak
        #expect(peak > 1, "OPML-Import sollte Feeds weiterhin parallel abrufen.")
        #expect(peak <= FeedViewModel.maxConcurrentFeedRefreshes, "OPML-Import darf nicht alle Feeds gleichzeitig abrufen.")
    }

    @MainActor
    @Test func refreshAllFeedsAktualisiertFeedsMitBegrenzterParallelitaet() async throws {
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

        let feeds = (1 ... 10).map { index in
            Feed(url: "https://example.com/\(index).xml", title: "Feed \(index)")
        }
        for feed in feeds {
            context.insert(feed)
        }
        try context.save()

        actor ConcurrencyTracker {
            var active = 0
            var peak = 0
            func fetchStarted() { active += 1; peak = max(peak, active) }
            func fetchEnded() { active -= 1 }
        }
        let tracker = ConcurrencyTracker()

        let viewModel = makeViewModel(
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

        await viewModel.refreshAllFeeds(feeds, context: context)

        let peak = await tracker.peak
        #expect(peak > 1, "Feeds sollten weiterhin parallel aktualisiert werden.")
        #expect(peak <= FeedViewModel.maxConcurrentFeedRefreshes, "Refresh darf nicht alle Feeds gleichzeitig abrufen.")
    }

    @MainActor
    @Test func refreshAllFeedsKannUeberEigenenModelContainerLaufen() async throws {
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
        let feed = Feed(url: "https://example.com/feed.xml", title: "Alter Titel")
        context.insert(feed)
        try context.save()

        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                ParsedFeed(
                    sourceURL: urlString,
                    title: "Neuer Titel",
                    description: "Neue Beschreibung",
                    siteURL: "https://example.com/",
                    articles: [
                        ParsedArticle(
                            title: "Neuer Artikel",
                            link: "https://example.com/new",
                            summary: "Kurz",
                            content: nil,
                            publishedAt: Date(timeIntervalSince1970: 1),
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in nil }
        )

        await viewModel.refreshAllFeeds([feed], modelContainer: container)

        let verificationContext = ModelContext(container)
        let refreshedFeeds = try verificationContext.fetch(FetchDescriptor<Feed>())
        let refreshedFeed = try #require(refreshedFeeds.first)
        #expect(refreshedFeed.title == "Neuer Titel")
        #expect(refreshedFeed.feedDescription == "Neue Beschreibung")
        #expect(refreshedFeed.unreadCount == 1)
        #expect(viewModel.recentRefreshStatus?.newArticleCount == 1)
        #expect(viewModel.recentRefreshStatus?.failedFeedCount == 0)
    }

    @MainActor
    @Test func refreshAllFeedsMitSQLiteDatabaseNutztSQLiteFirstOhneDoppeltenAbruf() async throws {
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
        let feed = Feed(url: "https://example.com/feed.xml", title: "Alter Titel")
        context.insert(feed)
        try context.save()

        let sqliteDatabase = try FeedivoDatabase.inMemoryForTests()
        try FeedStore(database: sqliteDatabase).save(
            FeedRecord(
                id: feed.id.uuidString,
                url: feed.url,
                title: feed.title
            )
        )

        actor FetchCounter {
            var count = 0
            func increment() {
                count += 1
            }
        }
        let fetchCounter = FetchCounter()

        let viewModel = makeViewModel(
            fetchFeed: { _ in
                Issue.record("Der direkte Feed-Abruf darf im SQLite-first Sammelrefresh nicht genutzt werden.")
                return ParsedFeed(sourceURL: "", title: "", description: nil, articles: [])
            },
            fetchFeedConditionally: { urlString, _ in
                await fetchCounter.increment()
                let parsedFeed = await MainActor.run {
                    ParsedFeed(
                        sourceURL: urlString,
                        title: "Neuer Titel",
                        description: nil,
                        siteURL: "https://example.com/",
                        articles: [
                            ParsedArticle(
                                title: "SQLite-first Artikel",
                                sourceID: "sqlite-first",
                                link: "https://example.com/sqlite-first",
                                summary: nil,
                                content: nil,
                                publishedAt: Date(timeIntervalSince1970: 100),
                                imageURL: nil
                            )
                        ]
                    )
                }
                let validators = await MainActor.run {
                    FeedHTTPValidators(lastStatusCode: 200)
                }
                return .updated(parsedFeed, validators)
            }
        )

        await viewModel.refreshAllFeeds(
            [feed],
            modelContainer: container,
            sqliteDatabase: sqliteDatabase
        )

        let sqliteFeed = try #require(try FeedStore(database: sqliteDatabase).feed(id: feed.id.uuidString))
        let rows = try TimelineStore(database: sqliteDatabase).articles(
            scope: .feed(sqliteFeed.id),
            includeRead: true,
            includeHidden: false,
            limit: 20
        )
        let verificationContext = ModelContext(container)
        let swiftDataArticles = try verificationContext.fetch(FetchDescriptor<Article>())
        let fetchCount = await fetchCounter.count

        #expect(fetchCount == 1)
        #expect(sqliteFeed.title == "Neuer Titel")
        #expect(sqliteFeed.unreadCount == 1)
        #expect(rows.map(\.title) == ["SQLite-first Artikel"])
        #expect(swiftDataArticles.isEmpty)
        #expect(viewModel.recentRefreshStatus?.newArticleCount == 1)
        #expect(viewModel.recentRefreshStatus?.failedFeedCount == 0)
    }

    @MainActor
    @Test func refreshAllFeedsUeberspringtLogEintraegeFuerUnveraenderteFeedsImBackgroundPfad() async throws {
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
        let oldRefreshDate = Date(timeIntervalSince1970: 1)
        let feed = Feed(
            url: "https://example.com/feed.xml",
            title: "Stabiler Feed",
            lastRefreshed: oldRefreshDate,
            httpETag: "\"alt\"",
            httpContentHash: "alter-hash",
            lastHTTPStatusCode: 200
        )
        context.insert(feed)
        try context.save()

        let viewModel = makeViewModel(
            fetchFeed: { _ in
                Issue.record("Der direkte Feed-Abruf darf im Conditional-Background-Pfad nicht genutzt werden.")
                return ParsedFeed(sourceURL: "", title: "", description: nil, articles: [])
            },
            fetchFeedConditionally: { _, validators in
                #expect(validators.eTag == "\"alt\"")
                #expect(validators.contentHash == "alter-hash")
                return .notModified(
                    FeedHTTPValidators(
                        eTag: "\"neu\"",
                        contentHash: "alter-hash",
                        lastStatusCode: 304
                    )
                )
            }
        )

        await viewModel.refreshAllFeeds([feed], modelContainer: container)

        let verificationContext = ModelContext(container)
        let refreshedFeed = try #require(try verificationContext.fetch(FetchDescriptor<Feed>()).first)
        let logEntries = try verificationContext.fetch(FetchDescriptor<FeedLogEntry>())
        #expect(refreshedFeed.title == "Stabiler Feed")
        #expect(refreshedFeed.lastRefreshed ?? .distantPast > oldRefreshDate)
        #expect(refreshedFeed.httpETag == "\"neu\"")
        #expect(refreshedFeed.lastHTTPStatusCode == 304)
        #expect(logEntries.isEmpty)
        #expect(viewModel.recentRefreshStatus?.newArticleCount == 0)
        #expect(viewModel.recentRefreshStatus?.failedFeedCount == 0)
    }

    @MainActor
    @Test func refreshAllFeedsSpeichertUnveraendertenBackgroundFeedOhneValidatorAenderungNicht() async throws {
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
        let oldRefreshDate = Date(timeIntervalSince1970: 1)
        let feed = Feed(
            url: "https://example.com/feed.xml",
            title: "Stabiler Feed",
            lastRefreshed: oldRefreshDate,
            httpETag: "\"stabil\"",
            httpLastModified: "Thu, 02 Jul 2026 10:00:00 GMT",
            httpContentHash: "stabiler-hash",
            lastHTTPStatusCode: 304
        )
        context.insert(feed)
        try context.save()

        let viewModel = makeViewModel(
            fetchFeed: { _ in
                Issue.record("Der direkte Feed-Abruf darf im unveränderten Background-Pfad nicht genutzt werden.")
                return ParsedFeed(sourceURL: "", title: "", description: nil, articles: [])
            },
            fetchFeedConditionally: { _, validators in
                #expect(validators.eTag == "\"stabil\"")
                #expect(validators.lastModified == "Thu, 02 Jul 2026 10:00:00 GMT")
                #expect(validators.contentHash == "stabiler-hash")
                #expect(validators.lastStatusCode == 304)
                return .notModified(validators)
            }
        )

        await viewModel.refreshAllFeeds([feed], modelContainer: container)

        let verificationContext = ModelContext(container)
        let refreshedFeed = try #require(try verificationContext.fetch(FetchDescriptor<Feed>()).first)
        let logEntries = try verificationContext.fetch(FetchDescriptor<FeedLogEntry>())
        #expect(refreshedFeed.lastRefreshed == oldRefreshDate)
        #expect(refreshedFeed.httpETag == "\"stabil\"")
        #expect(refreshedFeed.httpLastModified == "Thu, 02 Jul 2026 10:00:00 GMT")
        #expect(refreshedFeed.httpContentHash == "stabiler-hash")
        #expect(refreshedFeed.lastHTTPStatusCode == 304)
        #expect(logEntries.isEmpty)
        #expect(viewModel.recentRefreshStatus?.newArticleCount == 0)
        #expect(viewModel.recentRefreshStatus?.failedFeedCount == 0)
    }

    @MainActor
    @Test func refreshFeedMeldetNeueArtikelFuerFeedBenachrichtigung() async throws {
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
        let feed = Feed(url: "https://example.com/feed.xml", title: "Alter Titel")
        feed.isNotificationEnabled = true
        context.insert(feed)
        try context.save()

        var capturedResults: [FeedRefreshNotificationResult] = []
        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                ParsedFeed(
                    sourceURL: urlString,
                    title: "Aktueller Titel",
                    description: nil,
                    articles: [
                        ParsedArticle(
                            title: "Neuer Artikel 1",
                            link: "https://example.com/1",
                            summary: nil,
                            content: nil,
                            publishedAt: Date(timeIntervalSince1970: 100),
                            imageURL: nil
                        ),
                        ParsedArticle(
                            title: "Neuer Artikel 2",
                            link: "https://example.com/2",
                            summary: nil,
                            content: nil,
                            publishedAt: Date(timeIntervalSince1970: 200),
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in nil },
            notifyFeedRefresh: { results in
                capturedResults = results
            }
        )

        await viewModel.refreshFeed(feed, context: context)

        #expect(capturedResults == [
            FeedRefreshNotificationResult(
                feedTitle: "Aktueller Titel",
                newArticleCount: 2,
                isNotificationEnabled: true
            )
        ])
    }

    @MainActor
    @Test func refreshFeedMeldetRegelBenachrichtigungenFuerNeueArtikel() async throws {
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
        let feed = Feed(url: "https://example.com/feed.xml", title: "Mac News")
        let rule = Rule(name: "Breaking")
        rule.actionRaw = RuleAction.notify.rawValue
        rule.notificationTemplate = "Breaking: {Titel}"
        rule.notificationPriorityRaw = RuleNotificationPriority.critical.rawValue
        rule.conditions = [
            RuleCondition(
                field: RuleConditionField.title.rawValue,
                conditionOperator: RuleConditionOperator.contains.rawValue,
                value: "Swift",
                sortOrder: 0
            )
        ]
        context.insert(feed)
        context.insert(rule)
        try context.save()

        var capturedRuleNotifications: [RuleNotificationResult] = []
        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                ParsedFeed(
                    sourceURL: urlString,
                    title: "Mac News",
                    description: nil,
                    articles: [
                        ParsedArticle(
                            title: "Swift 7 ist da",
                            link: "https://example.com/swift",
                            summary: nil,
                            content: nil,
                            publishedAt: Date(timeIntervalSince1970: 100),
                            imageURL: nil
                        )
                    ]
                )
            },
            discoverFaviconURL: { _ in nil },
            notifyFeedRefresh: { _ in },
            notifyRuleNotifications: { results in
                capturedRuleNotifications = results
            }
        )

        await viewModel.refreshFeed(feed, context: context)

        #expect(capturedRuleNotifications == [
            RuleNotificationResult(
                ruleID: rule.id,
                ruleName: "Breaking",
                message: "Breaking: Swift 7 ist da",
                articleTitle: "Swift 7 ist da",
                feedTitle: "Mac News",
                priority: .critical
            )
        ])
    }

    @MainActor
    @Test func deleteFeedEntferntAuchZugehoerigeLogEntries() throws {
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
        let feed = Feed(url: "https://example.com/feed.xml", title: "Test Feed")
        feed.logEntries = [
            FeedLogEntry(createdAt: Date(), kind: .info, message: "Abruf ok"),
            FeedLogEntry(createdAt: Date(), kind: .error, message: "Abruf fehlerhaft")
        ]
        context.insert(feed)
        try context.save()
        let viewModel = makeViewModel()

        viewModel.deleteFeed(feed, context: context)

        let entries = try context.fetch(FetchDescriptor<FeedLogEntry>())
        #expect(entries.isEmpty, "LogEntries müssen mit dem Feed gelöscht werden")
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func unreadIncrementZaehltKeineGelesenenOderVerstecktenArtikel() {
        // Konsistenz mit dem addFeed-Pfad (Z. 400: `!isRead && !isHidden`):
        // Gelesene und versteckte Artikel dürfen den Ungelesen-Zähler nicht
        // erhöhen — nur frische, ungelesene Artikel zählen.
        let readArticle = Article(title: "Gelesen", isRead: true)
        let hiddenArticle = Article(title: "Versteckt", isHidden: true)
        let freshArticle = Article(title: "Neu")

        #expect(FeedViewModel.unreadIncrement(for: [readArticle]) == 0)
        #expect(FeedViewModel.unreadIncrement(for: [hiddenArticle]) == 0)
        #expect(FeedViewModel.unreadIncrement(for: [freshArticle]) == 1)
        #expect(FeedViewModel.unreadIncrement(for: [readArticle, hiddenArticle, freshArticle]) == 1)
    }

    @MainActor
    @Test func addFeedLehntAbWennBereitsEinLaufenderRefreshAktivIst() async throws {
        let container = try ModelContainer(
            for: Feed.self, Article.self, Tag.self, Rule.self,
            RuleCondition.self, FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let viewModel = makeViewModel()
        viewModel.isLoading = true  // simuliert laufenden Hintergrund-Refresh

        await viewModel.addFeed(urlString: "https://example.com/feed.xml", context: context)

        // Guard triggert: kein Fetch, Fehlermeldung gesetzt, isLoading bleibt true.
        #expect(viewModel.errorMessage == L10n.feedErrorAlreadyRunning)
        #expect(try context.fetch(FetchDescriptor<Feed>()).count == 0)
    }

    @MainActor
    @Test func opmlImportPreviewRowsParalleelisiertBehaeltReihenfolgeUndStatus() async throws {
        // Charakterisierungs-Test: Die Vorschau muss Reihenfolge und Status pro
        // Zeile bewahren, auch wenn der Abruf parallelisiert in Batches läuft.
        // 6 Feeds, einer ("fail://broken") ist nicht erreichbar, Rest available.
        let viewModel = makeViewModel(
            fetchFeed: { urlString in
                if urlString.hasPrefix("fail://") {
                    throw FeedServiceError.parsingFailed
                }
                return ParsedFeed(
                    sourceURL: urlString,
                    title: urlString,
                    description: nil,
                    articles: []
                )
            },
            discoverFaviconURL: { _ in nil }
        )
        // F3 (Index 2) ist nicht erreichbar — xmlURL ist `let`, daher wird der
        // dritte Eintrag direkt mit der fail://-URL erzeugt statt nachträglich
        // mutiert.
        let opmlFeeds: [OPMLFeed] = [
            OPMLFeed(title: "F1", xmlURL: "https://f1.example.com/feed.xml", htmlURL: nil, folderName: nil),
            OPMLFeed(title: "F2", xmlURL: "https://f2.example.com/feed.xml", htmlURL: nil, folderName: nil),
            OPMLFeed(title: "F3", xmlURL: "fail://broken", htmlURL: nil, folderName: nil),
            OPMLFeed(title: "F4", xmlURL: "https://f4.example.com/feed.xml", htmlURL: nil, folderName: nil),
            OPMLFeed(title: "F5", xmlURL: "https://f5.example.com/feed.xml", htmlURL: nil, folderName: nil),
            OPMLFeed(title: "F6", xmlURL: "https://f6.example.com/feed.xml", htmlURL: nil, folderName: nil)
        ]

        let rows = await viewModel.opmlImportPreviewRows(for: opmlFeeds, existingFeeds: [])

        #expect(rows.count == 6)
        #expect(rows.map(\.feed.title) == ["F1", "F2", "F3", "F4", "F5", "F6"])
        #expect(rows[0].status == .available)
        #expect(rows[1].status == .available)
        #expect(rows[2].status == .unreachable)
        #expect(rows[3].status == .available)
        #expect(rows[4].status == .available)
        #expect(rows[5].status == .available)
        #expect(rows.allSatisfy { $0.status != .duplicate })
    }
}

private struct TestFeedRefreshError: LocalizedError {
    var errorDescription: String? {
        "Test refresh failed"
    }
}
