import Foundation
import GRDB
import Testing
@testable import Feedivo

struct OrphanedArticleStatusUpdateStoreTests {
    @Test func deleteOlderThanEntferntNurAeltereEintraege() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = OrphanedArticleStatusUpdateStore(database: database)
        try database.write { db in
            var alt = OrphanedArticleStatusUpdateRecord(
                articleID: "alt",
                isRead: true,
                isStarred: false,
                readAt: Date(timeIntervalSince1970: 0),
                starredAt: nil,
                receivedAt: Date(timeIntervalSince1970: 0)
            )
            try alt.insert(db)
            var neu = OrphanedArticleStatusUpdateRecord(
                articleID: "neu",
                isRead: false,
                isStarred: true,
                readAt: nil,
                starredAt: Date(timeIntervalSince1970: 1_000_000),
                receivedAt: Date(timeIntervalSince1970: 1_000_000)
            )
            try neu.insert(db)
        }

        let deletedCount = try store.deleteOlderThan(Date(timeIntervalSince1970: 500_000))

        #expect(deletedCount == 1)
        let remaining = try database.read { db in
            try OrphanedArticleStatusUpdateRecord.fetchAll(db)
        }
        #expect(remaining.map(\.articleID) == ["neu"])
    }

    @Test func deleteAllLeertDieGesamteTabelleUnabhaengigVomAlter() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let store = OrphanedArticleStatusUpdateStore(database: database)
        try database.write { db in
            var eintrag = OrphanedArticleStatusUpdateRecord(
                articleID: "artikel-1",
                isRead: true,
                isStarred: false,
                readAt: Date(),
                starredAt: nil,
                receivedAt: Date()
            )
            try eintrag.insert(db)
        }

        let deletedCount = try store.deleteAll()

        #expect(deletedCount == 1)
        let remaining = try database.read { db in
            try OrphanedArticleStatusUpdateRecord.fetchAll(db)
        }
        #expect(remaining.isEmpty)
    }
}
