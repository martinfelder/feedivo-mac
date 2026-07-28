import Foundation
import GRDB
import Testing
@testable import Feedivo

struct ArticleListSQLTests {
    @Test func selectColumnsUndStandardFromJoinLiefernAlleSnapshotFelder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let articleStore = ArticleStore(database: database)

        try feedStore.save(FeedRecord(
            id: "feed-a",
            url: "https://a.example.com/feed",
            title: "Feed A",
            faviconURL: "https://a.example.com/favicon.ico"
        ))
        let articleID = try articleStore.upsert(ArticleUpsertInput(
            feedID: "feed-a",
            sourceID: "article-1",
            title: "Artikel 1",
            summary: "Kurzfassung",
            arrivedAt: Date(timeIntervalSince1970: 100)
        ))

        let snapshot = try database.read { db in
            try ArticleListSnapshot.fetchOne(db, sql: """
                SELECT
                    \(ArticleListSQL.selectColumns)
                \(ArticleListSQL.standardFromJoin)
                WHERE a.id = ?
                """, arguments: [articleID])
        }

        let unwrapped = try #require(snapshot)
        #expect(unwrapped.id == articleID)
        #expect(unwrapped.feedID == "feed-a")
        #expect(unwrapped.feedTitle == "Feed A")
        #expect(unwrapped.faviconURL == "https://a.example.com/favicon.ico")
        #expect(unwrapped.title == "Artikel 1")
        #expect(unwrapped.summary == "Kurzfassung")
        #expect(unwrapped.isRead == false)
    }
}
