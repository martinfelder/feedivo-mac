import Foundation
import Testing
@testable import Feedivo

struct SQLiteTimelineStoreTests {
    @Test func timelineFetchesNewestUnreadVisibleSnapshotsForFeed() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        let oldID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "old",
                title: "Old",
                publishedAt: Date(timeIntervalSince1970: 100),
                arrivedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let newID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "new",
                title: "New",
                publishedAt: Date(timeIntervalSince1970: 200),
                arrivedAt: Date(timeIntervalSince1970: 200)
            )
        )
        try statusStore.setRead(true, articleID: oldID, at: Date(timeIntervalSince1970: 300))

        let snapshots = try timelineStore.articles(
            scope: .feed("feed-1"),
            includeRead: false,
            includeHidden: false,
            limit: 20
        )

        #expect(snapshots.map(\.id) == [newID])
        #expect(snapshots.first?.feedTitle == "Example")
    }

    @Test func timelineHonorsLimitAndSortsByPublishedThenArrivedDate() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        _ = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "one",
                title: "One",
                publishedAt: Date(timeIntervalSince1970: 100),
                arrivedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let twoID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "two",
                title: "Two",
                publishedAt: Date(timeIntervalSince1970: 200),
                arrivedAt: Date(timeIntervalSince1970: 200)
            )
        )
        let threeID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "three",
                title: "Three",
                publishedAt: nil,
                arrivedAt: Date(timeIntervalSince1970: 300)
            )
        )

        let snapshots = try timelineStore.articles(
            scope: .all,
            includeRead: true,
            includeHidden: false,
            limit: 2
        )

        #expect(snapshots.map(\.id) == [threeID, twoID])
    }

    @Test func unreadCountIgnoresReadAndHiddenArticles() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        _ = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "unread", title: "Unread")
        )
        let readID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "read", title: "Read")
        )
        let hiddenID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "hidden", title: "Hidden")
        )
        try statusStore.setRead(true, articleID: readID, at: Date(timeIntervalSince1970: 200))
        try statusStore.setHidden(true, articleID: hiddenID, at: Date(timeIntervalSince1970: 300))

        let count = try timelineStore.unreadCount(feedID: "feed-1")

        #expect(count == 1)
    }

    @Test func markReadForFeedScopeErfasstAuchNichtGeladeneArtikelJenseitsDesListenLimits() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))

        for index in 0..<6 {
            _ = try articleStore.upsert(
                ArticleUpsertInput(
                    feedID: "feed-1",
                    sourceID: "article-\(index)",
                    title: "Article \(index)",
                    publishedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                    arrivedAt: Date(timeIntervalSince1970: TimeInterval(index))
                )
            )
        }

        let visibleRows = try timelineStore.articles(
            scope: .feed("feed-1"),
            includeRead: true,
            includeHidden: false,
            limit: 2
        )

        let changedCount = try timelineStore.markRead(
            scope: .feed("feed-1"),
            searchText: nil,
            includeHidden: false,
            option: .allVisible
        )

        #expect(visibleRows.count == 2)
        #expect(changedCount == 6)
        #expect(try timelineStore.unreadCount(feedID: "feed-1") == 0)
        #expect(try feedStore.feed(id: "feed-1")?.unreadCount == 0)
    }

    @Test func timelineFetchesDirectlyTaggedAndFeedTaggedArticlesFromSQLite() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let tagStore = TagStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try feedStore.save(FeedRecord(id: "feed-2", url: "https://example.com/other.xml", title: "Other"))
        try tagStore.save(TagRecord(id: "tag-swift", name: "Swift", colorHex: "#ff0000"))
        try tagStore.save(TagRecord(id: "tag-other", name: "Other", colorHex: "#00ff00"))
        let olderTaggedID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "older-tagged",
                title: "Older Tagged",
                publishedAt: Date(timeIntervalSince1970: 100),
                arrivedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let newerTaggedID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "newer-tagged",
                title: "Newer Tagged",
                publishedAt: Date(timeIntervalSince1970: 300),
                arrivedAt: Date(timeIntervalSince1970: 300)
            )
        )
        let hiddenTaggedID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "hidden-tagged",
                title: "Hidden Tagged",
                publishedAt: Date(timeIntervalSince1970: 400),
                arrivedAt: Date(timeIntervalSince1970: 400)
            )
        )
        let otherTagID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "other-tag",
                title: "Other Tag",
                publishedAt: Date(timeIntervalSince1970: 500),
                arrivedAt: Date(timeIntervalSince1970: 500)
            )
        )
        let feedTaggedID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-2",
                sourceID: "feed-tagged",
                title: "Feed Tagged",
                publishedAt: Date(timeIntervalSince1970: 600),
                arrivedAt: Date(timeIntervalSince1970: 600)
            )
        )

        try tagStore.assignTag(tagID: "tag-swift", toArticleID: olderTaggedID, at: Date(timeIntervalSince1970: 110))
        try tagStore.assignTag(tagID: "tag-swift", toArticleID: newerTaggedID, at: Date(timeIntervalSince1970: 310))
        try tagStore.assignTag(tagID: "tag-swift", toArticleID: hiddenTaggedID, at: Date(timeIntervalSince1970: 410))
        try tagStore.assignTag(tagID: "tag-other", toArticleID: otherTagID, at: Date(timeIntervalSince1970: 510))
        try tagStore.assignTag(tagID: "tag-swift", toFeedID: "feed-2", at: Date(timeIntervalSince1970: 605))
        try statusStore.setHidden(true, articleID: hiddenTaggedID, at: Date(timeIntervalSince1970: 420))

        let snapshots = try timelineStore.articles(
            scope: .tag("tag-swift"),
            includeRead: true,
            includeHidden: false,
            limit: 20
        )

        #expect(snapshots.map(\.id) == [feedTaggedID, newerTaggedID, olderTaggedID])
        #expect(snapshots.map(\.feedTitle) == ["Other", "Example", "Example"])
    }

    @Test func timelineFetchesUnreadSmartFilterFromSQLite() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let (readID, unreadID, hiddenID) = try makeSmartFilterFixture(database: database)
        let timelineStore = TimelineStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        try statusStore.setRead(true, articleID: readID, at: Date(timeIntervalSince1970: 500))
        try statusStore.setHidden(true, articleID: hiddenID, at: Date(timeIntervalSince1970: 600))

        let snapshots = try timelineStore.articles(
            scope: .smartFilter(.unread),
            includeRead: true,
            includeHidden: false,
            limit: 20
        )

        #expect(snapshots.map(\.id) == [unreadID])
    }

    @Test func timelineFetchesStarredSmartFilterFromSQLite() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let (_, unreadID, hiddenID) = try makeSmartFilterFixture(database: database)
        let timelineStore = TimelineStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        try statusStore.setStarred(true, articleID: unreadID, at: Date(timeIntervalSince1970: 500))
        try statusStore.setStarred(true, articleID: hiddenID, at: Date(timeIntervalSince1970: 600))
        try statusStore.setHidden(true, articleID: hiddenID, at: Date(timeIntervalSince1970: 700))

        let snapshots = try timelineStore.articles(
            scope: .smartFilter(.starred),
            includeRead: true,
            includeHidden: false,
            limit: 20
        )

        #expect(snapshots.map(\.id) == [unreadID])
    }

    @Test func timelineFetchesTodaySmartFilterFromSQLite() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let timelineStore = TimelineStore(database: database)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date()).addingTimeInterval(60 * 60)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let todayID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "today", title: "Today", publishedAt: today, arrivedAt: today)
        )
        _ = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "yesterday", title: "Yesterday", publishedAt: yesterday, arrivedAt: yesterday)
        )

        let snapshots = try timelineStore.articles(
            scope: .smartFilter(.today),
            includeRead: true,
            includeHidden: false,
            limit: 20
        )

        #expect(snapshots.map(\.id) == [todayID])
    }

    @Test func timelineFetchesHiddenSmartFilterFromSQLite() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let (_, _, hiddenID) = try makeSmartFilterFixture(database: database)
        let timelineStore = TimelineStore(database: database)
        let statusStore = ArticleStatusStore(database: database)
        try statusStore.setHidden(true, articleID: hiddenID, at: Date(timeIntervalSince1970: 600))

        let snapshots = try timelineStore.articles(
            scope: .smartFilter(.hidden),
            includeRead: true,
            includeHidden: true,
            limit: 20
        )

        #expect(snapshots.map(\.id) == [hiddenID])
    }

    @Test func timelineSearchFiltersFeedScopeWithFTSIndex() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try feedStore.save(FeedRecord(id: "feed-2", url: "https://example.com/other.xml", title: "Other"))
        let matchingID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "match", title: "SQLite performance", summary: "Fast local search")
        )
        _ = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "miss", title: "Different title", summary: "No matching token")
        )
        _ = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-2", sourceID: "other", title: "SQLite performance", summary: "Wrong feed")
        )

        let snapshots = try timelineStore.articles(
            scope: .feed("feed-1"),
            searchText: "performance",
            includeRead: true,
            includeHidden: false,
            limit: 20
        )

        #expect(snapshots.map(\.id) == [matchingID])
    }

    @Test func timelineSearchCombinesTagScopeAndSummaryContent() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let tagStore = TagStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try tagStore.save(TagRecord(id: "tag-swift", name: "Swift", colorHex: "#ff0000"))
        let matchingID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "match", title: "One", content: "NetNewsWire style storage")
        )
        let untaggedID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "untagged", title: "Two", content: "NetNewsWire style storage")
        )
        try tagStore.assignTag(tagID: "tag-swift", toArticleID: matchingID, at: Date())

        let snapshots = try timelineStore.articles(
            scope: .tag("tag-swift"),
            searchText: "netnewswire storage",
            includeRead: true,
            includeHidden: false,
            limit: 20
        )

        #expect(snapshots.map(\.id) == [matchingID])
        #expect(!snapshots.map(\.id).contains(untaggedID))
    }

    @Test func timelineSearchSanitizesPunctuationBeforeFTSMatch() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let articleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "swift-beta", title: "Swift beta improves search")
        )

        let snapshots = try timelineStore.articles(
            scope: .feed("feed-1"),
            searchText: "Swift's beta?",
            includeRead: true,
            includeHidden: false,
            limit: 20
        )

        #expect(snapshots.map(\.id) == [articleID])
    }

    @Test func customSmartFolderMatchesAllStatusAndTitleConditions() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let fixture = try makeCustomSmartFolderFixture(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let timelineStore = TimelineStore(database: database)
        try statusStore.setStarred(true, articleID: fixture.swiftArticleID, at: Date(timeIntervalSince1970: 500))
        try statusStore.setStarred(true, articleID: fixture.otherArticleID, at: Date(timeIntervalSince1970: 600))

        let folder = SQLiteSmartFolderSnapshot(
            id: "smart-starred-swift",
            name: "Starred Swift",
            matchMode: .all,
            conditions: [
                SQLiteSmartFolderConditionSnapshot(field: .status, conditionOperator: .is, value: SmartFolderStatusValue.starred.rawValue),
                SQLiteSmartFolderConditionSnapshot(field: .title, conditionOperator: .contains, value: "Swift")
            ]
        )

        let snapshots = try timelineStore.articles(
            scope: .smartFolder(folder),
            includeRead: true,
            includeHidden: false,
            limit: 20
        )

        #expect(snapshots.map(\.id) == [fixture.swiftArticleID])
    }

    @Test func customSmartFolderMatchesAnyTagOrFeedFolderCondition() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let fixture = try makeCustomSmartFolderFixture(database: database)
        let tagStore = TagStore(database: database)
        let timelineStore = TimelineStore(database: database)
        try tagStore.assignTag(tagID: "tag-swift", toArticleID: fixture.swiftArticleID, at: Date(timeIntervalSince1970: 500))
        try tagStore.assignTag(tagID: "tag-swift", toFeedID: "feed-2", at: Date(timeIntervalSince1970: 600))

        let folder = SQLiteSmartFolderSnapshot(
            id: "smart-tag-or-folder",
            name: "Tagged or Folder",
            matchMode: .any,
            conditions: [
                SQLiteSmartFolderConditionSnapshot(field: .tag, conditionOperator: .is, value: "tag-swift"),
                SQLiteSmartFolderConditionSnapshot(field: .feedFolder, conditionOperator: .is, value: "News")
            ]
        )

        let snapshots = try timelineStore.articles(
            scope: .smartFolder(folder),
            includeRead: true,
            includeHidden: false,
            limit: 20
        )

        #expect(snapshots.map(\.id) == [fixture.newsArticleID, fixture.swiftArticleID])
    }

    @Test func customSmartFolderMatchesFeedDateAuthorAndTextConditions() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let fixture = try makeCustomSmartFolderFixture(database: database)
        let timelineStore = TimelineStore(database: database)

        let folder = SQLiteSmartFolderSnapshot(
            id: "smart-feed-date-author-text",
            name: "Feed Date Author Text",
            matchMode: .all,
            conditions: [
                SQLiteSmartFolderConditionSnapshot(field: .feed, conditionOperator: .is, value: "Example"),
                SQLiteSmartFolderConditionSnapshot(field: .date, conditionOperator: .olderThanDays, value: "3"),
                SQLiteSmartFolderConditionSnapshot(field: .author, conditionOperator: .contains, value: "Martin"),
                SQLiteSmartFolderConditionSnapshot(field: .text, conditionOperator: .contains, value: "database")
            ]
        )

        let snapshots = try timelineStore.articles(
            scope: .smartFolder(folder),
            includeRead: true,
            includeHidden: false,
            limit: 20
        )

        #expect(snapshots.map(\.id) == [fixture.oldArticleID])
    }

    @Test func customSmartFolderSupportsIsNotAndHiddenInclusion() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let fixture = try makeCustomSmartFolderFixture(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let timelineStore = TimelineStore(database: database)
        try statusStore.setHidden(true, articleID: fixture.hiddenArticleID, at: Date(timeIntervalSince1970: 700))

        let folder = SQLiteSmartFolderSnapshot(
            id: "smart-hidden-not-other",
            name: "Hidden Not Other",
            matchMode: .all,
            conditions: [
                SQLiteSmartFolderConditionSnapshot(field: .status, conditionOperator: .is, value: SmartFolderStatusValue.hidden.rawValue),
                SQLiteSmartFolderConditionSnapshot(field: .feed, conditionOperator: .isNot, value: "Other")
            ]
        )

        let excluded = try timelineStore.articles(
            scope: .smartFolder(folder),
            includeRead: true,
            includeHidden: false,
            limit: 20
        )
        let included = try timelineStore.articles(
            scope: .smartFolder(folder),
            includeRead: true,
            includeHidden: true,
            limit: 20
        )

        #expect(excluded.isEmpty)
        #expect(included.map(\.id) == [fixture.hiddenArticleID])
    }

    @Test func customSmartFolderWithNoConditionsMatchesVisibleArticles() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let fixture = try makeCustomSmartFolderFixture(database: database)
        let statusStore = ArticleStatusStore(database: database)
        let timelineStore = TimelineStore(database: database)
        try statusStore.setHidden(true, articleID: fixture.hiddenArticleID, at: Date(timeIntervalSince1970: 700))

        let folder = SQLiteSmartFolderSnapshot(
            id: "smart-empty",
            name: "Empty",
            matchMode: .all,
            conditions: []
        )

        let snapshots = try timelineStore.articles(
            scope: .smartFolder(folder),
            includeRead: true,
            includeHidden: false,
            limit: 20
        )

        #expect(snapshots.map(\.id) == [
            fixture.newsArticleID,
            fixture.otherArticleID,
            fixture.swiftArticleID,
            fixture.oldArticleID
        ])
    }

    @Test func customSmartFolderCountUsesSQLiteConditionsWithoutMaterializingArticles() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let fixture = try makeCustomSmartFolderFixture(database: database)
        try TagStore(database: database).assignTag(
            tagID: "tag-swift",
            toArticleID: fixture.swiftArticleID,
            at: Date(timeIntervalSince1970: 800)
        )
        let timelineStore = TimelineStore(database: database)
        let folder = SQLiteSmartFolderSnapshot(
            id: "smart-count",
            name: "Swift oder News",
            matchMode: .any,
            conditions: [
                SQLiteSmartFolderConditionSnapshot(
                    field: .tag,
                    conditionOperator: .is,
                    value: "tag-swift"
                ),
                SQLiteSmartFolderConditionSnapshot(
                    field: .feedFolder,
                    conditionOperator: .is,
                    value: "News"
                )
            ]
        )

        let count = try timelineStore.count(
            scope: .smartFolder(folder),
            includeRead: true,
            includeHidden: false
        )

        #expect(count == 2)
    }

    @Test func timelineUsesMinimumLimitOfOne() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let timelineStore = TimelineStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let articleID = try articleStore.upsert(
            ArticleUpsertInput(feedID: "feed-1", sourceID: "one", title: "One")
        )

        let snapshots = try timelineStore.articles(
            scope: .all,
            includeRead: true,
            includeHidden: true,
            limit: 0
        )

        #expect(snapshots.map(\.id) == [articleID])
    }

    private func makeSmartFilterFixture(database: FeedivoDatabase) throws -> (String, String, String) {
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        let readID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "read",
                title: "Read",
                publishedAt: Date(timeIntervalSince1970: 100),
                arrivedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let unreadID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "unread",
                title: "Unread",
                publishedAt: Date(timeIntervalSince1970: 200),
                arrivedAt: Date(timeIntervalSince1970: 200)
            )
        )
        let hiddenID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "hidden",
                title: "Hidden",
                publishedAt: Date(timeIntervalSince1970: 300),
                arrivedAt: Date(timeIntervalSince1970: 300)
            )
        )

        return (readID, unreadID, hiddenID)
    }

    private func makeCustomSmartFolderFixture(database: FeedivoDatabase) throws -> CustomSmartFolderFixture {
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)
        let tagStore = TagStore(database: database)
        let now = Date()
        let oldDate = Calendar.current.date(byAdding: .day, value: -7, to: now)!

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example", folderName: "Tech"))
        try feedStore.save(FeedRecord(id: "feed-2", url: "https://example.com/news.xml", title: "Newsroom", folderName: "News"))
        try tagStore.save(TagRecord(id: "tag-swift", name: "Swift", colorHex: "#ff0000"))

        let swiftArticleID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "swift",
                title: "Swift SQLite Bridge",
                summary: "Fast local snapshots",
                content: "Timeline storage",
                author: "Martin",
                publishedAt: now,
                arrivedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let oldArticleID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "old",
                title: "Database Archive",
                summary: "Long term storage",
                content: "database history",
                author: "Martin",
                publishedAt: oldDate,
                arrivedAt: Date(timeIntervalSince1970: 200)
            )
        )
        let otherArticleID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "other",
                title: "Other Topic",
                summary: "General update",
                content: "No match",
                author: "Alex",
                publishedAt: now,
                arrivedAt: Date(timeIntervalSince1970: 300)
            )
        )
        let newsArticleID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-2",
                sourceID: "news",
                title: "Morning Briefing",
                summary: "News folder item",
                content: "Daily notes",
                author: "News Desk",
                publishedAt: now,
                arrivedAt: Date(timeIntervalSince1970: 400)
            )
        )
        let hiddenArticleID = try articleStore.upsert(
            ArticleUpsertInput(
                feedID: "feed-1",
                sourceID: "hidden",
                title: "Hidden Example",
                summary: "Invisible",
                content: "Hidden text",
                author: "Martin",
                publishedAt: now,
                arrivedAt: Date(timeIntervalSince1970: 500)
            )
        )

        return CustomSmartFolderFixture(
            swiftArticleID: swiftArticleID,
            oldArticleID: oldArticleID,
            otherArticleID: otherArticleID,
            newsArticleID: newsArticleID,
            hiddenArticleID: hiddenArticleID
        )
    }
}

private struct CustomSmartFolderFixture {
    let swiftArticleID: String
    let oldArticleID: String
    let otherArticleID: String
    let newsArticleID: String
    let hiddenArticleID: String
}
