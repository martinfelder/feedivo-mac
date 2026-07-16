import Foundation
import Testing
@testable import Feedivo

struct SQLiteFeedLogStoreTests {
    @Test func appendLogPersistsNewestFirst() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try logStore.append(FeedLogRecord(
            id: "old",
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            level: "info",
            message: "Old",
            newArticleCount: 1
        ))
        try logStore.append(FeedLogRecord(
            id: "new",
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 2_000),
            level: "error",
            message: "New",
            httpStatusCode: 500,
            newArticleCount: 0
        ))

        let logs = try logStore.logs(feedID: "feed-1", limit: 10)

        #expect(logs.map(\.id) == ["new", "old"])
        #expect(logs.first?.level == "error")
        #expect(logs.first?.httpStatusCode == 500)
    }

    @Test func deleteOlderThanEntferntNurAeltereEintraege() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let logStore = FeedLogStore(database: database)

        try feedStore.save(FeedRecord(id: "feed-1", url: "https://example.com/feed.xml", title: "Example"))
        try logStore.append(FeedLogRecord(
            id: "old",
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            level: "info",
            message: "Old"
        ))
        try logStore.append(FeedLogRecord(
            id: "new",
            feedID: "feed-1",
            createdAt: Date(timeIntervalSince1970: 5_000),
            level: "info",
            message: "New"
        ))

        let deletedCount = try logStore.deleteOlderThan(Date(timeIntervalSince1970: 3_000))

        #expect(deletedCount == 1)
        let remaining = try logStore.logs(feedID: "feed-1", limit: 10)
        #expect(remaining.map(\.id) == ["new"])
    }

    @Test func deleteOlderThanFunktioniertBeiLeererTabelle() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let logStore = FeedLogStore(database: database)

        let deletedCount = try logStore.deleteOlderThan(Date())

        #expect(deletedCount == 0)
    }
}
