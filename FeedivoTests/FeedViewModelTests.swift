import Foundation
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

    @Test func importOPMLFeedsSpiegeltNeueFeedsNachSQLite() async throws {
        let sqliteDatabase = try FeedivoDatabase.inMemoryForTests()
        let viewModel = makeViewModel(fetchFeed: { urlString in
            ParsedFeed(
                sourceURL: urlString,
                title: "Importiert",
                description: nil,
                siteURL: "https://example.com/",
                articles: [
                    ParsedArticle(
                        title: "Erster Artikel",
                        sourceID: "one",
                        link: "https://example.com/1",
                        summary: "Kurz",
                        content: "<p>Inhalt</p>",
                        publishedAt: Date(timeIntervalSince1970: 1_000),
                        imageURL: nil
                    )
                ]
            )
        })

        let result = try await viewModel.importOPMLFeeds(
            [
                OPMLFeed(
                    title: "Feed aus OPML",
                    xmlURL: "https://example.com/feed.xml",
                    htmlURL: "https://example.com/",
                    folderName: "News"
                )
            ],
            refreshAfterImport: true,
            sqliteDatabase: sqliteDatabase
        )

        let feed = try #require(try FeedStore(database: sqliteDatabase).feed(url: "https://example.com/feed.xml"))
        let rows = try TimelineStore(database: sqliteDatabase).articles(
            scope: .feed(feed.id),
            includeRead: true,
            includeHidden: true,
            limit: 10
        )

        #expect(result.imported == 1)
        #expect(feed.folderName == "News")
        #expect(rows.map(\.title) == ["Erster Artikel"])
    }

    @MainActor
    @Test func importOPMLFeedsWirftWennBereitsEinImportLaeuft() async throws {
        let viewModel = makeViewModel()

        // isLoading simuliert einen laufenden Import/Refresh — der Aufruf darf
        // keinen vorgetäuschten Erfolg (imported: 0) zurückgeben, sondern muss
        // werfen, damit die Aufrufer den Zustand sichtbar melden.
        viewModel.isLoading = true

        await #expect(throws: FeedImportError.self) {
            try await viewModel.importOPMLFeeds(
                [OPMLFeed(title: "Blockiert", xmlURL: "https://example.com/x.xml", htmlURL: nil, folderName: nil)],
                refreshAfterImport: false
            )
        }
    }

    @MainActor
    @Test func importOPMLFeedsAktualisiertNeueFeedsDirektNachDemImport() async throws {
        let defaults = UserDefaults.standard
        let previousStatusVersion = defaults.object(forKey: SQLiteDataInvalidation.statusVersionKey) as? Int
        let initialStatusVersion = defaults.integer(forKey: SQLiteDataInvalidation.statusVersionKey)
        defer {
            if let previousStatusVersion {
                defaults.set(previousStatusVersion, forKey: SQLiteDataInvalidation.statusVersionKey)
            } else {
                defaults.removeObject(forKey: SQLiteDataInvalidation.statusVersionKey)
            }
        }
        let sqliteDatabase = try FeedivoDatabase.inMemoryForTests()
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
            sqliteDatabase: sqliteDatabase
        )

        let sqliteFeed = try #require(try FeedStore(database: sqliteDatabase).feed(url: "https://example.com/imported.xml"))
        let rows = try TimelineStore(database: sqliteDatabase).articles(
            scope: .feed(sqliteFeed.id),
            includeRead: true,
            includeHidden: true,
            limit: 10
        )

        #expect(result.imported == 1)
        #expect(sqliteFeed.title == "Aktualisierter Import Feed")
        #expect(sqliteFeed.websiteURL == "https://example.com/")
        #expect(sqliteFeed.folderName == "News")
        #expect(sqliteFeed.lastRefreshedAt != nil)
        #expect(sqliteFeed.unreadCount == 1)
        #expect(rows.map(\.title) == ["Importierter Artikel"])
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isLoading)
        #expect(viewModel.operationProgress == nil)
        #expect(defaults.integer(forKey: SQLiteDataInvalidation.statusVersionKey) > initialStatusVersion)
    }

    @Test func opmlImportPreviewDelegiertAnSQLiteSubscriptionService() async throws {
        // Phase-6-Reduktion: `FeedViewModel` hält nur noch UI-State; die echte
        // Vorschau-Logik liegt im `SQLiteFeedSubscriptionService`. Dieser Test
        // prüft nur die Delegation — Duplikat-/Erreichbarkeits-Erwartungen liegen
        // in `SQLiteFeedSubscriptionServiceTests`.
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedStore(database: database).save(
            FeedRecord(id: "existing", url: "https://example.com/existing.xml", title: "Schon da")
        )
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
            sqliteDatabase: database
        )

        #expect(rows.map(\.status) == [.available, .duplicate, .unreachable])
        #expect(rows.map(\.isSelected) == [true, false, false])
    }

    @MainActor
    @Test func opmlImportPreviewOhneSQLiteDatabaseLiefertLeereListe() async throws {
        // Ohne SQLite-Datenbank gibt es keinen produktiven Bestand, gegen den ein
        // Duplikat geprüft werden könnte — die Vorschau bleibt leer statt einen
        // SwiftData-Fallback zu bemühen.
        let viewModel = makeViewModel(
            fetchFeed: { _ in
                ParsedFeed(sourceURL: "https://example.com", title: "OK", description: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil }
        )

        let rows = await viewModel.opmlImportPreviewRows(
            for: [OPMLFeed(title: "F1", xmlURL: "https://example.com/1.xml", htmlURL: nil, folderName: nil)],
            sqliteDatabase: nil
        )

        #expect(rows.isEmpty)
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
    @Test func refreshAllFeedsMitSQLiteDatabaseNutztSQLiteFirstOhneDoppeltenAbruf() async throws {
        let sqliteDatabase = try FeedivoDatabase.inMemoryForTests()
        let feedID = UUID().uuidString
        try FeedStore(database: sqliteDatabase).save(
            FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Alter Titel")
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

        await viewModel.refreshAllFeeds(sqliteDatabase: sqliteDatabase)

        let sqliteFeed = try #require(try FeedStore(database: sqliteDatabase).feed(id: feedID))
        let rows = try TimelineStore(database: sqliteDatabase).articles(
            scope: .feed(sqliteFeed.id),
            includeRead: true,
            includeHidden: false,
            limit: 20
        )
        let fetchCount = await fetchCounter.count

        #expect(fetchCount == 1)
        #expect(sqliteFeed.title == "Neuer Titel")
        #expect(sqliteFeed.unreadCount == 1)
        #expect(rows.map(\.title) == ["SQLite-first Artikel"])
        #expect(viewModel.recentRefreshStatus?.newArticleCount == 1)
        #expect(viewModel.recentRefreshStatus?.failedFeedCount == 0)
    }

    @MainActor
    @Test func refreshAllFeedsMitSQLiteDatabaseMeldetFeedBenachrichtigungen() async throws {
        let sqliteDatabase = try FeedivoDatabase.inMemoryForTests()
        let feedID = UUID().uuidString
        try FeedStore(database: sqliteDatabase).save(
            FeedRecord(
                id: feedID,
                url: "https://example.com/feed.xml",
                title: "Alter Titel",
                isNotificationEnabled: true
            )
        )

        var capturedResults: [FeedRefreshNotificationResult] = []
        let viewModel = makeViewModel(
            fetchFeedConditionally: { urlString, _ in
                let parsedFeed = await MainActor.run {
                    ParsedFeed(
                        sourceURL: urlString,
                        title: "Aktueller Titel",
                        description: nil,
                        articles: [
                            ParsedArticle(
                                title: "Benachrichtigter Artikel",
                                sourceID: "notify-1",
                                link: "https://example.com/notify-1",
                                summary: nil,
                                content: nil,
                                publishedAt: Date(timeIntervalSince1970: 100),
                                imageURL: nil
                            )
                        ]
                    )
                }
                return .updated(parsedFeed, FeedHTTPValidators(lastStatusCode: 200))
            },
            notifyFeedRefresh: { results in
                capturedResults = results
            }
        )

        await viewModel.refreshAllFeeds(sqliteDatabase: sqliteDatabase)

        #expect(capturedResults == [
            FeedRefreshNotificationResult(
                feedTitle: "Aktueller Titel",
                newArticleCount: 1,
                isNotificationEnabled: true
            )
        ])
    }

    @MainActor
    @Test func refreshAllFeedsMitSQLiteDatabaseWendetHideUndNotifyRegelnAn() async throws {
        // Produktiver SQLite-Pfad: Regeln liegen in `SQLiteRuleStore`, Refresh
        // läuft über `refreshAllFeeds(sqliteDatabase:)` — kein SwiftData-Container
        // mehr nötig.
        let sqliteDatabase = try FeedivoDatabase.inMemoryForTests()
        let feedID = UUID().uuidString
        try FeedStore(database: sqliteDatabase).save(
            FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Mac News")
        )
        let ruleStore = SQLiteRuleStore(database: sqliteDatabase)
        let hideRuleID = UUID().uuidString
        try ruleStore.save(
            RuleRecord(
                id: hideRuleID,
                name: "Gerüchte ausblenden",
                action: RuleAction.hideArticle.rawValue,
                sortOrder: 0
            ),
            conditions: [
                RuleConditionRecord(
                    ruleID: hideRuleID,
                    field: RuleConditionField.title.rawValue,
                    conditionOperator: RuleConditionOperator.contains.rawValue,
                    value: "Gerücht"
                )
            ]
        )
        let notifyRuleID = UUID().uuidString
        try ruleStore.save(
            RuleRecord(
                id: notifyRuleID,
                name: "Swift melden",
                action: RuleAction.notify.rawValue,
                notificationTemplate: "Neu: {Titel}",
                notificationPriority: RuleNotificationPriority.critical.rawValue,
                sortOrder: 1
            ),
            conditions: [
                RuleConditionRecord(
                    ruleID: notifyRuleID,
                    field: RuleConditionField.title.rawValue,
                    conditionOperator: RuleConditionOperator.contains.rawValue,
                    value: "Swift"
                )
            ]
        )

        var capturedRuleNotifications: [RuleNotificationResult] = []
        let viewModel = makeViewModel(
            fetchFeedConditionally: { urlString, _ in
                let parsedFeed = await MainActor.run {
                    ParsedFeed(
                        sourceURL: urlString,
                        title: "Mac News",
                        description: nil,
                        articles: [
                            ParsedArticle(
                                title: "Gerücht: neues MacBook",
                                sourceID: "hidden-1",
                                link: "https://example.com/hidden-1",
                                summary: nil,
                                content: nil,
                                publishedAt: Date(timeIntervalSince1970: 100),
                                imageURL: nil
                            ),
                            ParsedArticle(
                                title: "Swift 7 ist da",
                                sourceID: "notify-1",
                                link: "https://example.com/notify-1",
                                summary: nil,
                                content: nil,
                                publishedAt: Date(timeIntervalSince1970: 200),
                                imageURL: nil
                            )
                        ]
                    )
                }
                return .updated(parsedFeed, FeedHTTPValidators(lastStatusCode: 200))
            },
            notifyRuleNotifications: { results in
                capturedRuleNotifications = results
            }
        )

        await viewModel.refreshAllFeeds(sqliteDatabase: sqliteDatabase)

        let sqliteFeed = try #require(try FeedStore(database: sqliteDatabase).feed(id: feedID))
        let visibleRows = try TimelineStore(database: sqliteDatabase).articles(
            scope: .feed(sqliteFeed.id),
            includeRead: true,
            includeHidden: false,
            limit: 20
        )
        let allRows = try TimelineStore(database: sqliteDatabase).articles(
            scope: .feed(sqliteFeed.id),
            includeRead: true,
            includeHidden: true,
            limit: 20
        )
        let hiddenRow = try #require(allRows.first { $0.title == "Gerücht: neues MacBook" })
        let hiddenStatus = try ArticleStatusStore(database: sqliteDatabase).status(articleID: hiddenRow.id)

        #expect(visibleRows.map(\.title) == ["Swift 7 ist da"])
        #expect(hiddenStatus?.isHidden == true)
        #expect(sqliteFeed.unreadCount == 1)
        #expect(capturedRuleNotifications == [
            RuleNotificationResult(
                ruleID: UUID(uuidString: notifyRuleID) ?? UUID(),
                ruleName: "Swift melden",
                message: "Neu: Swift 7 ist da",
                articleTitle: "Swift 7 ist da",
                feedTitle: "Mac News",
                priority: .critical
            )
        ])
    }

    @MainActor
    @Test func refreshAllFeedsMitSQLiteDatabaseWendetAssignTagRegelnAn() async throws {
        // Produktiver SQLite-Pfad: Tag und Regel liegen in SQLite, Refresh läuft
        // über `refreshAllFeeds(sqliteDatabase:)`.
        let sqliteDatabase = try FeedivoDatabase.inMemoryForTests()
        let feedID = UUID().uuidString
        try FeedStore(database: sqliteDatabase).save(
            FeedRecord(id: feedID, url: "https://example.com/feed.xml", title: "Mac News")
        )
        let tagID = UUID().uuidString
        try TagStore(database: sqliteDatabase).save(
            TagRecord(id: tagID, name: "Swift", colorHex: "#ff0000")
        )
        let ruleID = UUID().uuidString
        try SQLiteRuleStore(database: sqliteDatabase).save(
            RuleRecord(
                id: ruleID,
                name: "Swift taggen",
                action: RuleAction.assignTag.rawValue,
                assignTagID: tagID,
                sortOrder: 0
            ),
            conditions: [
                RuleConditionRecord(
                    ruleID: ruleID,
                    field: RuleConditionField.title.rawValue,
                    conditionOperator: RuleConditionOperator.contains.rawValue,
                    value: "Swift"
                )
            ]
        )

        let viewModel = makeViewModel(
            fetchFeedConditionally: { urlString, _ in
                let parsedFeed = await MainActor.run {
                    ParsedFeed(
                        sourceURL: urlString,
                        title: "Mac News",
                        description: nil,
                        articles: [
                            ParsedArticle(
                                title: "Swift 7 ist da",
                                sourceID: "swift-1",
                                link: "https://example.com/swift-1",
                                summary: nil,
                                content: nil,
                                publishedAt: Date(timeIntervalSince1970: 100),
                                imageURL: nil
                            ),
                            ParsedArticle(
                                title: "MacBook Gerücht",
                                sourceID: "mac-1",
                                link: "https://example.com/mac-1",
                                summary: nil,
                                content: nil,
                                publishedAt: Date(timeIntervalSince1970: 200),
                                imageURL: nil
                            )
                        ]
                    )
                }
                return .updated(parsedFeed, FeedHTTPValidators(lastStatusCode: 200))
            }
        )

        await viewModel.refreshAllFeeds(sqliteDatabase: sqliteDatabase)

        let sqliteFeed = try #require(try FeedStore(database: sqliteDatabase).feed(id: feedID))
        let rows = try TimelineStore(database: sqliteDatabase).articles(
            scope: .feed(sqliteFeed.id),
            includeRead: true,
            includeHidden: false,
            limit: 20
        )
        let swiftArticle = try #require(rows.first { $0.title == "Swift 7 ist da" })
        let otherArticle = try #require(rows.first { $0.title == "MacBook Gerücht" })
        let tagStore = TagStore(database: sqliteDatabase)

        #expect(try tagStore.tags(articleID: swiftArticle.id).map(\.name) == ["Swift"])
        #expect(try tagStore.tags(articleID: otherArticle.id).isEmpty)
    }

    @Test func opmlImportPreviewBehaeltReihenfolgeUndStatusUeberDelegation() async throws {
        // Delegations-Test: Die Reihenfolge-/Status-Erwartung wird über den
        // produktiven Pfad (SQLite-Service) geprüft, nicht mehr über eine inline-
        // Implementierung im ViewModel. Die eigentliche Charakterisierung liegt
        // in `SQLiteFeedSubscriptionServiceTests`.
        let database = try FeedivoDatabase.inMemoryForTests()
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
        let opmlFeeds: [OPMLFeed] = [
            OPMLFeed(title: "F1", xmlURL: "https://f1.example.com/feed.xml", htmlURL: nil, folderName: nil),
            OPMLFeed(title: "F2", xmlURL: "https://f2.example.com/feed.xml", htmlURL: nil, folderName: nil),
            OPMLFeed(title: "F3", xmlURL: "fail://broken", htmlURL: nil, folderName: nil),
            OPMLFeed(title: "F4", xmlURL: "https://f4.example.com/feed.xml", htmlURL: nil, folderName: nil),
            OPMLFeed(title: "F5", xmlURL: "https://f5.example.com/feed.xml", htmlURL: nil, folderName: nil),
            OPMLFeed(title: "F6", xmlURL: "https://f6.example.com/feed.xml", htmlURL: nil, folderName: nil)
        ]

        let rows = await viewModel.opmlImportPreviewRows(for: opmlFeeds, sqliteDatabase: database)

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
