import Foundation
import GRDB
import Testing
@testable import Feedivo

struct SQLiteArticleStoreTests {
    @Test func feedPropertiesMetricsUseLatestDatedArticleAndRecentCount() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let now = Date(timeIntervalSince1970: 20_000)
        let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try feedStore.save(FeedRecord(id: "feed-2", url: "https://other.example/feed.xml", title: "Other"))

        _ = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "old",
            title: "Alter Artikel",
            publishedAt: cutoff.addingTimeInterval(-60),
            arrivedAt: cutoff.addingTimeInterval(-60)
        ))
        _ = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "undated",
            title: "Ohne Datum",
            publishedAt: nil,
            arrivedAt: now.addingTimeInterval(60)
        ))
        _ = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "newest",
            title: "Neuester datierter Artikel",
            publishedAt: now.addingTimeInterval(-120),
            arrivedAt: now.addingTimeInterval(-120)
        ))
        _ = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-2",
            sourceID: "other-feed",
            title: "Fremder Feed",
            publishedAt: now,
            arrivedAt: now
        ))

        let metrics = try articleStore.feedPropertiesMetrics(
            feedID: "feed-1",
            recentCutoffDate: cutoff,
            now: now
        )

        #expect(metrics.latestArticle?.title == "Neuester datierter Artikel")
        #expect(metrics.recentArticleCount == 1)
    }

    @Test func feedPropertiesMetricsFallsBackToUndatedArticle() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let now = Date(timeIntervalSince1970: 20_000)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        _ = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "undated",
            title: "Undatierter Artikel",
            publishedAt: nil,
            arrivedAt: now
        ))

        let metrics = try articleStore.feedPropertiesMetrics(
            feedID: "feed-1",
            recentCutoffDate: now.addingTimeInterval(-7 * 24 * 60 * 60),
            now: now
        )

        #expect(metrics.latestArticle?.title == "Undatierter Artikel")
        #expect(metrics.recentArticleCount == 0)
    }

    @Test func upsertInsertsArticleAndCreatesStatus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let publishedAt = Date(timeIntervalSince1970: 1_000)
        let arrivedAt = Date(timeIntervalSince1970: 2_000)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let articleID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "source-1",
                link: "https://example.com/articles/1",
                title: "First Article",
                summary: "Summary",
                content: "Full content",
                imageURL: "https://example.com/image.jpg",
                author: "Author",
                publishedAt: publishedAt,
                arrivedAt: arrivedAt,
                estimatedReadingMinutes: 4
            )
        )

        let readerArticle = try articleStore.readerArticle(id: articleID)
        let status = try statusStore.status(articleID: articleID)

        #expect(readerArticle?.title == "First Article")
        #expect(readerArticle?.feedTitle == "Example")
        #expect(readerArticle?.content == "Full content")
        #expect(status?.isRead == false)
    }

    @Test func readerArticleLaedtFeedOrdnerUndKombinierteTags() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let tagStore = TagStore(database: database)

        try feedStore.save(FeedRecord(
            id: "feed-1",
            url: "https://example.com/feed.xml",
            title: "Example",
            folderName: "News"
        ))
        let articleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "article-1", title: "First Article")
        )
        try tagStore.save(TagRecord(id: "tag-feed", name: "FeedTag", colorHex: "#111111"))
        try tagStore.save(TagRecord(id: "tag-article", name: "ArticleTag", colorHex: "#222222"))
        try tagStore.assignTag(tagID: "tag-feed", toFeedID: "feed-1", at: Date(timeIntervalSince1970: 100))
        try tagStore.assignTag(tagID: "tag-article", toArticleID: articleID, at: Date(timeIntervalSince1970: 200))

        let readerArticle = try articleStore.readerArticle(id: articleID)

        #expect(readerArticle?.folderName == "News")
        #expect(readerArticle?.tags.map(\.name) == ["ArticleTag", "FeedTag"])
        #expect(readerArticle?.tags.map(\.colorHex) == ["#222222", "#111111"])
    }

    @Test func upsertRestoresStatusFromIdentityHistory() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let firstSeenAt = Date(timeIntervalSince1970: 1_000)
        let readAt = Date(timeIntervalSince1970: 2_000)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        var history = ArticleIdentityHistoryRecord(
            id: "history-1",
            feedID: "feed-1",
            sourceID: "source-1",
            link: "https://example.com/articles/1",
            titleHash: ArticleStore.titleHash("Alter Artikel"),
            publishedAt: nil,
            firstSeenAt: firstSeenAt,
            lastSeenAt: firstSeenAt,
            lastArticleID: "deleted-article",
            isRead: true,
            isStarred: false,
            isArchived: false,
            isHidden: false,
            readAt: readAt,
            starredAt: nil,
            archivedAt: nil,
            hiddenAt: nil
        )
        try database.write { db in
            try history.insert(db)
        }

        let articleID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "source-1",
            link: "https://example.com/articles/1",
            title: "Alter Artikel",
            arrivedAt: Date(timeIntervalSince1970: 9_000)
        ))
        let status = try statusStore.status(articleID: articleID)

        #expect(status?.isRead == true)
        #expect(status?.readAt == readAt)
        #expect(status?.dateArrived == firstSeenAt)
    }

    @Test func upsertUeberspringtArtikelDerDurchBereinigungEntferntWurdeUndWeiterhinAbgelaufenIst() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let oldPublishedAt = Date().addingTimeInterval(-100 * 24 * 60 * 60)

        try feedStore.save(FeedRecord(
            id: "feed-1",
            url: "https://example.com/feed.xml",
            title: "Example",
            articleRetentionOverridesGlobalSetting: true,
            articleRetentionIsEnabled: true,
            articleRetentionDays: 90
        ))

        var history = ArticleIdentityHistoryRecord(
            id: "history-1",
            feedID: "feed-1",
            sourceID: "source-1",
            link: "https://example.com/articles/1",
            titleHash: ArticleStore.titleHash("Alter Artikel"),
            publishedAt: oldPublishedAt,
            firstSeenAt: oldPublishedAt,
            lastSeenAt: oldPublishedAt,
            lastArticleID: "deleted-article",
            isRead: false,
            isStarred: false,
            isArchived: false,
            isHidden: false,
            readAt: nil,
            starredAt: nil,
            archivedAt: nil,
            hiddenAt: nil,
            wasRemovedByRetention: true
        )
        try database.write { db in
            try history.insert(db)
        }

        let result = try articleStore.upsert([ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "source-1",
            link: "https://example.com/articles/1",
            title: "Alter Artikel",
            publishedAt: oldPublishedAt,
            arrivedAt: Date()
        )])

        #expect(result.articleIDs.isEmpty)
        #expect(result.insertedArticleIDs.isEmpty)
        let articleCount = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM articles") ?? 0
        }
        #expect(articleCount == 0)
    }

    @Test func upsertUeberspringtArtikelOhnePublishedAtDerDurchBereinigungEntferntWurdeUndFirstSeenAtWeiterhinAbgelaufenIst() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let oldFirstSeenAt = Date().addingTimeInterval(-100 * 24 * 60 * 60)

        try feedStore.save(FeedRecord(
            id: "feed-1",
            url: "https://example.com/feed.xml",
            title: "Example",
            articleRetentionOverridesGlobalSetting: true,
            articleRetentionIsEnabled: true,
            articleRetentionDays: 90
        ))

        var history = ArticleIdentityHistoryRecord(
            id: "history-1",
            feedID: "feed-1",
            sourceID: "source-1",
            link: "https://example.com/articles/1",
            titleHash: ArticleStore.titleHash("Alter Artikel Ohne PublishedAt"),
            publishedAt: nil,
            firstSeenAt: oldFirstSeenAt,
            lastSeenAt: oldFirstSeenAt,
            lastArticleID: "deleted-article",
            isRead: false,
            isStarred: false,
            isArchived: false,
            isHidden: false,
            readAt: nil,
            starredAt: nil,
            archivedAt: nil,
            hiddenAt: nil,
            wasRemovedByRetention: true
        )
        try database.write { db in
            try history.insert(db)
        }

        // Artikel wird "erneut zugestellt" (Feed liefert weiterhin kein publishedAt) —
        // arrivedAt ist bewusst JETZT (frischer Refresh-Durchlauf), nicht der alte
        // firstSeenAt-Zeitpunkt. Vor dem Fix nutzte die Skip-Prüfung fälschlich
        // input.arrivedAt (= jetzt) als effectiveDate und fügte den Artikel trotz
        // wasRemovedByRetention sofort wieder ein.
        let result = try articleStore.upsert([ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "source-1",
            link: "https://example.com/articles/1",
            title: "Alter Artikel Ohne PublishedAt",
            publishedAt: nil,
            arrivedAt: Date()
        )])

        #expect(result.articleIDs.isEmpty)
        #expect(result.insertedArticleIDs.isEmpty)
        let articleCount = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM articles") ?? 0
        }
        #expect(articleCount == 0)
    }

    @Test func upsertFuegtArtikelWiederEinWennBereinigungNichtMehrGreiftUndSetztFlagZurueck() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let oldPublishedAt = Date().addingTimeInterval(-100 * 24 * 60 * 60)
        let readAt = Date().addingTimeInterval(-90 * 24 * 60 * 60)

        try feedStore.save(FeedRecord(
            id: "feed-1",
            url: "https://example.com/feed.xml",
            title: "Example",
            articleRetentionOverridesGlobalSetting: true,
            articleRetentionIsEnabled: false,
            articleRetentionDays: 90
        ))

        var history = ArticleIdentityHistoryRecord(
            id: "history-1",
            feedID: "feed-1",
            sourceID: "source-1",
            link: "https://example.com/articles/1",
            titleHash: ArticleStore.titleHash("Alter Artikel"),
            publishedAt: oldPublishedAt,
            firstSeenAt: oldPublishedAt,
            lastSeenAt: oldPublishedAt,
            lastArticleID: "deleted-article",
            isRead: true,
            isStarred: false,
            isArchived: false,
            isHidden: false,
            readAt: readAt,
            starredAt: nil,
            archivedAt: nil,
            hiddenAt: nil,
            wasRemovedByRetention: true
        )
        try database.write { db in
            try history.insert(db)
        }

        let result = try articleStore.upsert([ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "source-1",
            link: "https://example.com/articles/1",
            title: "Alter Artikel",
            publishedAt: oldPublishedAt,
            arrivedAt: Date()
        )])

        #expect(result.insertedArticleIDs.count == 1)
        let articleID = try #require(result.insertedArticleIDs.first)
        let restoredHistory = try database.read { db in
            try ArticleIdentityHistoryRecord.fetchOne(db, sql: """
                SELECT * FROM article_identity_history WHERE feedID = ? AND sourceID = ? LIMIT 1
                """, arguments: ["feed-1", "source-1"])
        }

        #expect(restoredHistory?.wasRemovedByRetention == false)
        #expect(restoredHistory?.lastArticleID == articleID)
        let status = try ArticleStatusStore(database: database).status(articleID: articleID)
        #expect(status?.isRead == true)
    }

    @Test func upsertUpdatesExistingArticleBySourceIDWithoutOverwritingStatus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let originalArrivedAt = Date(timeIntervalSince1970: 2_000)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let firstID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "source-1",
                link: "https://example.com/articles/old",
                title: "Old Title",
                summary: "Old summary",
                content: "Old content",
                publishedAt: Date(timeIntervalSince1970: 1_000),
                arrivedAt: originalArrivedAt,
                estimatedReadingMinutes: 3
            )
        )
        try statusStore.setRead(true, articleID: firstID, at: Date(timeIntervalSince1970: 3_000))

        let secondID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "source-1",
                link: "https://example.com/articles/new",
                title: "New Title",
                summary: "New summary",
                content: "New content",
                publishedAt: Date(timeIntervalSince1970: 4_000),
                arrivedAt: Date(timeIntervalSince1970: 5_000),
                estimatedReadingMinutes: 7
            )
        )

        let readerArticle = try articleStore.readerArticle(id: firstID)
        let status = try statusStore.status(articleID: firstID)

        #expect(secondID == firstID)
        #expect(readerArticle?.title == "New Title")
        #expect(readerArticle?.summary == "New summary")
        #expect(readerArticle?.content == "New content")
        #expect(readerArticle?.estimatedReadingMinutes == 7)
        #expect(status?.isRead == true)
        #expect(status?.dateArrived == originalArrivedAt)
        #expect(readerArticle?.arrivedAt == originalArrivedAt)
    }

    @Test func upsertFallsBackToLinkWhenSourceIDIsMissing() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let firstID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: nil,
                link: "https://example.com/articles/1",
                title: "Old Title"
            )
        )
        let secondID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: nil,
                link: "https://example.com/articles/1",
                title: "New Title"
            )
        )

        let readerArticle = try articleStore.readerArticle(id: firstID)

        #expect(secondID == firstID)
        #expect(readerArticle?.title == "New Title")
    }

    @Test func upsertPersistsLaterSourceIDAfterLinkFallbackMatch() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let firstID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: nil,
                link: "https://example.com/articles/original",
                title: "Original"
            )
        )
        let secondID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "source-1",
                link: "https://example.com/articles/original",
                title: "With Source"
            )
        )
        let thirdID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "source-1",
                link: "https://example.com/articles/changed",
                title: "Changed Link"
            )
        )

        let readerArticle = try articleStore.readerArticle(id: firstID)

        #expect(secondID == firstID)
        #expect(thirdID == firstID)
        #expect(readerArticle?.link == "https://example.com/articles/changed")
        #expect(readerArticle?.title == "Changed Link")
    }

    @Test func readerArticleUsesArticleArrivedAtInsteadOfStatusDateArrived() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let articleArrivedAt = Date(timeIntervalSince1970: 2_000)
        let statusDateArrived = Date(timeIntervalSince1970: 9_000)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let articleID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "source-1",
                link: "https://example.com/articles/1",
                title: "First Article",
                arrivedAt: articleArrivedAt
            )
        )
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE article_statuses
                    SET dateArrived = ?
                    WHERE articleID = ?
                    """,
                arguments: [statusDateArrived, articleID]
            )
        }

        let readerArticle = try articleStore.readerArticle(id: articleID)
        let status = try statusStore.status(articleID: articleID)

        #expect(readerArticle?.arrivedAt == articleArrivedAt)
        #expect(status?.dateArrived == statusDateArrived)
    }

    @Test func upsertIgnoresWhitespaceSourceIDForExistingMatch() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let firstID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "source-1",
                link: "https://example.com/articles/1",
                title: "Old Title"
            )
        )
        let secondID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "   ",
                link: "https://example.com/articles/2",
                title: "New Title"
            )
        )

        #expect(secondID != firstID)
    }

    @Test func batchUpsertReturnsInsertedAndUpdatedIDs() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let existingID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "existing", title: "Old Title")
        )

        let result = try articleStore.upsert([
            ArticleUpsertInput(feedID: "feed-1", sourceID: "existing", title: "Updated Title"),
            ArticleUpsertInput(feedID: "feed-1", sourceID: "new", title: "New Title")
        ])

        let updatedArticle = try articleStore.readerArticle(id: existingID)
        let articleCount = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM articles") ?? 0
        }

        #expect(result.updatedArticleIDs == [existingID])
        #expect(result.insertedArticleIDs.count == 1)
        #expect(result.articleIDs.count == 2)
        #expect(updatedArticle?.title == "Updated Title")
        #expect(articleCount == 2)
    }

    @Test func batchUpsertRunsInOneTransactionAndPreservesStatus() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let originalArrivedAt = Date(timeIntervalSince1970: 1_000)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let articleID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "existing",
                title: "Old Title",
                arrivedAt: originalArrivedAt
            )
        )
        try statusStore.setRead(true, articleID: articleID, at: Date(timeIntervalSince1970: 2_000))

        let result = try articleStore.upsert([
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "existing",
                title: "Updated Title",
                arrivedAt: Date(timeIntervalSince1970: 3_000)
            )
        ])

        let status = try statusStore.status(articleID: articleID)
        let readerArticle = try articleStore.readerArticle(id: articleID)

        #expect(result.insertedArticleIDs.isEmpty)
        #expect(result.updatedArticleIDs == [articleID])
        #expect(status?.isRead == true)
        #expect(status?.dateArrived == originalArrivedAt)
        #expect(readerArticle?.arrivedAt == originalArrivedAt)
    }

    @Test func searchWindowQueryHonorsFieldFeedTagAndStatusFilters() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let tagStore = TagStore(database: database)
        let feedID = UUID()
        let otherFeedID = UUID()
        let tagID = UUID()

        try feedStore.save(FeedRecord(id: feedID.uuidString, url: "https://example.com/feed.xml", title: "Example"))
        try feedStore.save(FeedRecord(id: otherFeedID.uuidString, url: "https://example.com/other.xml", title: "Other"))
        try tagStore.save(TagRecord(id: tagID.uuidString, name: "Swift", colorHex: "#ff0000"))

        let olderMatchID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: feedID.uuidString,
                sourceID: "older",
                title: "Swift Release alt",
                summary: "Update",
                publishedAt: Date(timeIntervalSince1970: 100),
                arrivedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let newerMatchID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: feedID.uuidString,
                sourceID: "newer",
                title: "Swift Release neu",
                summary: "Update",
                publishedAt: Date(timeIntervalSince1970: 300),
                arrivedAt: Date(timeIntervalSince1970: 300)
            )
        )
        let wrongFeedID = try articleStore.upsert(
            ArticleUpsertInput(feedID: otherFeedID.uuidString, sourceID: "wrong-feed", title: "Swift Release anderer Feed")
        )
        let readID = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID.uuidString, sourceID: "read", title: "Swift Release gelesen")
        )
        let summaryOnlyID = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID.uuidString, sourceID: "summary", title: "Andere Meldung", summary: "Swift Release nur Summary")
        )

        try tagStore.assignTag(tagID: tagID.uuidString, toArticleID: olderMatchID, at: Date())
        try tagStore.assignTag(tagID: tagID.uuidString, toArticleID: newerMatchID, at: Date())
        try tagStore.assignTag(tagID: tagID.uuidString, toArticleID: wrongFeedID, at: Date())
        try tagStore.assignTag(tagID: tagID.uuidString, toArticleID: readID, at: Date())
        try tagStore.assignTag(tagID: tagID.uuidString, toArticleID: summaryOnlyID, at: Date())
        try statusStore.setRead(true, articleID: readID, at: Date())

        let state = ArticleSearchWindowState(
            searchText: "swift",
            field: .title,
            feedID: feedID,
            tagIDs: [tagID],
            statusFilter: .unread
        )

        let snapshots = try articleStore.searchArticles(state: state, limit: 20)

        #expect(snapshots.map(\.id) == [newerMatchID, olderMatchID])
    }

    @Test func searchArticlesMitEinzelnemTagVerhaeltSichWieBisher() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let tagStore = TagStore(database: database)
        let feedID = UUID()
        let tagID = UUID()

        try feedStore.save(FeedRecord(id: feedID.uuidString, url: "https://example.com/feed.xml", title: "Example"))
        try tagStore.save(TagRecord(id: tagID.uuidString, name: "Swift", colorHex: "#ff0000"))

        let taggedID = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID.uuidString, sourceID: "tagged", title: "Tagged Article")
        )
        _ = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID.uuidString, sourceID: "untagged", title: "Untagged Article")
        )
        try tagStore.assignTag(tagID: tagID.uuidString, toArticleID: taggedID, at: Date())

        let state = ArticleSearchWindowState(feedID: feedID, tagIDs: [tagID])
        let snapshots = try articleStore.searchArticles(state: state, limit: 20)

        #expect(snapshots.map(\.id) == [taggedID])
    }

    @Test func searchArticlesMitMindEinemTagFindetArtikelMitBeliebigemDerAusgewaehltenTags() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let tagStore = TagStore(database: database)
        let feedID = UUID()
        let techTagID = UUID()
        let newsTagID = UUID()
        let sportTagID = UUID()

        try feedStore.save(FeedRecord(id: feedID.uuidString, url: "https://example.com/feed.xml", title: "Example"))
        try tagStore.save(TagRecord(id: techTagID.uuidString, name: "Tech", colorHex: "#ff0000"))
        try tagStore.save(TagRecord(id: newsTagID.uuidString, name: "News", colorHex: "#00ff00"))
        try tagStore.save(TagRecord(id: sportTagID.uuidString, name: "Sport", colorHex: "#0000ff"))

        let techArticleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID.uuidString, sourceID: "tech", title: "Tech Artikel")
        )
        let newsArticleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID.uuidString, sourceID: "news", title: "News Artikel")
        )
        let sportArticleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID.uuidString, sourceID: "sport", title: "Sport Artikel")
        )

        try tagStore.assignTag(tagID: techTagID.uuidString, toArticleID: techArticleID, at: Date())
        try tagStore.assignTag(tagID: newsTagID.uuidString, toArticleID: newsArticleID, at: Date())
        try tagStore.assignTag(tagID: sportTagID.uuidString, toArticleID: sportArticleID, at: Date())

        let state = ArticleSearchWindowState(
            feedID: feedID,
            tagIDs: [techTagID, newsTagID],
            tagMatchMode: .any
        )

        let snapshots = try articleStore.searchArticles(state: state, limit: 20)

        #expect(Set(snapshots.map(\.id)) == [techArticleID, newsArticleID])
    }

    @Test func searchArticlesMitAlleTagsFindetNurArtikelMitAllenAusgewaehltenTags() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let tagStore = TagStore(database: database)
        let feedID = UUID()
        let techTagID = UUID()
        let newsTagID = UUID()

        try feedStore.save(FeedRecord(id: feedID.uuidString, url: "https://example.com/feed.xml", title: "Example"))
        try tagStore.save(TagRecord(id: techTagID.uuidString, name: "Tech", colorHex: "#ff0000"))
        try tagStore.save(TagRecord(id: newsTagID.uuidString, name: "News", colorHex: "#00ff00"))

        let bothTagsArticleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID.uuidString, sourceID: "both", title: "Beide Tags")
        )
        let onlyTechArticleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID.uuidString, sourceID: "only-tech", title: "Nur Tech")
        )

        try tagStore.assignTag(tagID: techTagID.uuidString, toArticleID: bothTagsArticleID, at: Date())
        try tagStore.assignTag(tagID: newsTagID.uuidString, toArticleID: bothTagsArticleID, at: Date())
        try tagStore.assignTag(tagID: techTagID.uuidString, toArticleID: onlyTechArticleID, at: Date())

        let state = ArticleSearchWindowState(
            feedID: feedID,
            tagIDs: [techTagID, newsTagID],
            tagMatchMode: .all
        )

        let snapshots = try articleStore.searchArticles(state: state, limit: 20)

        #expect(snapshots.map(\.id) == [bothTagsArticleID])
    }

    @Test func searchArticlesBeruecksichtigtFeedEbeneTagsInBeidenModi() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let tagStore = TagStore(database: database)
        let feedID = UUID()
        let feedTagID = UUID()
        let articleTagID = UUID()

        try feedStore.save(FeedRecord(id: feedID.uuidString, url: "https://example.com/feed.xml", title: "Example"))
        try tagStore.save(TagRecord(id: feedTagID.uuidString, name: "FeedTag", colorHex: "#ff0000"))
        try tagStore.save(TagRecord(id: articleTagID.uuidString, name: "ArticleTag", colorHex: "#00ff00"))
        try tagStore.assignTag(tagID: feedTagID.uuidString, toFeedID: feedID.uuidString, at: Date())

        let articleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID.uuidString, sourceID: "article", title: "Artikel")
        )
        try tagStore.assignTag(tagID: articleTagID.uuidString, toArticleID: articleID, at: Date())

        let anyState = ArticleSearchWindowState(
            feedID: feedID,
            tagIDs: [feedTagID, articleTagID],
            tagMatchMode: .any
        )
        #expect(try articleStore.searchArticles(state: anyState, limit: 20).map(\.id) == [articleID])

        let allState = ArticleSearchWindowState(
            feedID: feedID,
            tagIDs: [feedTagID, articleTagID],
            tagMatchMode: .all
        )
        #expect(try articleStore.searchArticles(state: allState, limit: 20).map(\.id) == [articleID])
    }

    @Test func searchArticlesMitLeererTagAuswahlFiltertNicht() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let feedID = UUID()

        try feedStore.save(FeedRecord(id: feedID.uuidString, url: "https://example.com/feed.xml", title: "Example"))

        let firstID = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID.uuidString, sourceID: "first", title: "Erster Artikel")
        )
        let secondID = try articleStore.upsert(
            ArticleUpsertInput(feedID: feedID.uuidString, sourceID: "second", title: "Zweiter Artikel")
        )

        let state = ArticleSearchWindowState(feedID: feedID, tagIDs: [])
        let snapshots = try articleStore.searchArticles(state: state, limit: 20)

        #expect(Set(snapshots.map(\.id)) == [firstID, secondID])
    }

    @Test func searchWindowQuerySupportsFiltersWithoutSearchText() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let normalID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "normal", title: "Normal")
        )
        let starredID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "starred",
                title: "Starred",
                publishedAt: Date(timeIntervalSince1970: 200),
                arrivedAt: Date(timeIntervalSince1970: 200)
            )
        )
        try statusStore.setStarred(true, articleID: starredID, at: Date())

        let state = ArticleSearchWindowState(statusFilter: .starred)

        let snapshots = try articleStore.searchArticles(state: state, limit: 20)

        #expect(snapshots.map(\.id) == [starredID])
        #expect(!snapshots.map(\.id).contains(normalID))
    }

    @Test func recentlyPublishedCountCountsOnlyArticlesWithinWindowAndIgnoresUndated() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let since = now.addingTimeInterval(-48 * 60 * 60)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let recentID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "recent",
            title: "Kuerzlich veroeffentlicht",
            publishedAt: now.addingTimeInterval(-60),
            arrivedAt: now
        ))
        let oldID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "old",
            title: "Alt veroeffentlicht",
            publishedAt: since.addingTimeInterval(-60),
            arrivedAt: now
        ))
        let undatedID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-1",
            sourceID: "undated",
            title: "Ohne Datum",
            publishedAt: nil,
            arrivedAt: now
        ))

        let count = try articleStore.recentlyPublishedCount(
            articleIDs: [recentID, oldID, undatedID],
            since: since
        )

        #expect(count == 1)
    }

    @Test func recentlyPublishedCountReturnsZeroForEmptyIDs() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let articleStore = ArticleStore(database: database)

        let count = try articleStore.recentlyPublishedCount(articleIDs: [], since: Date())

        #expect(count == 0)
    }

    @Test func upsertWendetWartendenVerwaistenStatusAn() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Feed"))
        let articleID = "artikel-vorab-bekannt"
        try database.write { db in
            var orphan = OrphanedArticleStatusUpdateRecord(
                articleID: articleID,
                isRead: true,
                isStarred: true,
                readAt: Date(timeIntervalSince1970: 100),
                starredAt: Date(timeIntervalSince1970: 200),
                receivedAt: Date(timeIntervalSince1970: 300)
            )
            try orphan.insert(db)
        }

        // Simuliert den Reconciliation-Aufruf, den `ArticleStore.upsert()` intern direkt nach
        // dem Einfügen einer neuen `article_statuses`-Zeile ausführt (siehe Step 4) — hier
        // isoliert getestet, ohne den kompletten Upsert-Pfad (der eine neue UUID vergäbe,
        // nicht `articleID`) durchlaufen zu müssen.
        try database.write { db in
            var article = ArticleRecord(
                id: articleID,
                feedID: "feed-1",
                title: "Titel",
                arrivedAt: Date(),
                updatedAt: Date()
            )
            try article.insert(db)
            var status = ArticleStatusRecord(articleID: articleID, dateArrived: Date())
            try status.insert(db)
            try ArticleStore.applyOrphanedStatusUpdateIfPresent(articleID: articleID, syncStableID: articleID, db: db)
        }

        let status = try ArticleStatusStore(database: database).status(articleID: articleID)
        #expect(status?.isRead == true)
        #expect(status?.isStarred == true)
        #expect(status?.statusSyncUpdatedAt != nil)

        let orphan = try database.read { db in
            try OrphanedArticleStatusUpdateRecord.fetchOne(db, key: articleID)
        }
        #expect(orphan == nil)
    }

    @Test func upsertBerechnetSyncStableIDFuerNeuenArtikel() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Feed"))

        let articleID = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "guid-abc", title: "Titel")
        )

        let status = try ArticleStatusStore(database: database).status(articleID: articleID)
        let expected = CloudSyncArticleStatusMapping.stableRecordName(
            feedID: "feed-1",
            sourceID: "guid-abc",
            link: nil,
            titleHash: ArticleStore.titleHash("Titel")
        )
        #expect(status?.syncStableID == expected)
    }

    @Test func upsertWendetVerwaistenStatusUeberSyncStableIDAn() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedStore(database: database).save(FeedRecord(id: "feed-1", url: "https://example.com/feed", title: "Feed"))
        let stableID = CloudSyncArticleStatusMapping.stableRecordName(
            feedID: "feed-1",
            sourceID: "guid-xyz",
            link: nil,
            titleHash: ArticleStore.titleHash("Anderer Titel")
        )
        try database.write { db in
            var orphan = OrphanedArticleStatusUpdateRecord(
                articleID: stableID,
                isRead: true,
                isStarred: true,
                readAt: Date(timeIntervalSince1970: 100),
                starredAt: Date(timeIntervalSince1970: 200),
                receivedAt: Date(timeIntervalSince1970: 300)
            )
            try orphan.insert(db)
        }

        // Simuliert ein zweites, unabhängiges Gerät: derselbe logische Artikel (gleicher
        // feedID+sourceID), aber der Upsert-Aufruf selbst vergibt intern eine FRISCHE,
        // von der wartenden Orphan-Zeile komplett unabhängige lokale articleID-UUID —
        // genau das Szenario, das den ursprünglichen Bug ausmachte.
        let articleID = try ArticleStore(database: database).upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "guid-xyz", title: "Anderer Titel")
        )

        let status = try ArticleStatusStore(database: database).status(articleID: articleID)
        #expect(status?.isRead == true)
        #expect(status?.isStarred == true)
        #expect(status?.syncStableID == stableID)

        let orphan = try database.read { db in
            try OrphanedArticleStatusUpdateRecord.fetchOne(db, key: stableID)
        }
        #expect(orphan == nil)
    }
}
