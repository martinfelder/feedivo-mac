import Foundation
import Testing
@testable import Feedivo

struct FeedFolderStoreTests {
    @Test func renameFolderUpdatesExplicitFolderRecord() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let folderStore = FeedFolderStore(database: database)
        try folderStore.save(FeedFolderRecord(id: "folder-1", name: "Tech"))

        try folderStore.renameFolder(from: "Tech", to: "Technology")

        let folders = try folderStore.folders()
        #expect(folders.map(\.name) == ["Technology"])
    }

    @Test func renameFolderUpdatesFeedsForImplicitFolder() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let folderStore = FeedFolderStore(database: database)

        try feedStore.save(
            FeedRecord(id: "feed-1", url: "https://a.example/feed.xml", title: "A", folderName: "News")
        )

        try folderStore.renameFolder(from: "News", to: "World News")

        let feed = try feedStore.feed(id: "feed-1")
        #expect(feed?.folderName == "World News")
    }

    @Test func renameFolderUpdatesAllFeedsInSameFolderButNotOthers() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let folderStore = FeedFolderStore(database: database)

        try feedStore.save(
            FeedRecord(id: "feed-1", url: "https://a.example/feed.xml", title: "A", folderName: "Tech")
        )
        try feedStore.save(
            FeedRecord(id: "feed-2", url: "https://b.example/feed.xml", title: "B", folderName: "Tech")
        )
        try feedStore.save(
            FeedRecord(id: "feed-3", url: "https://c.example/feed.xml", title: "C", folderName: "Other")
        )

        try folderStore.renameFolder(from: "Tech", to: "Technology")

        let feeds = try feedStore.feeds()
        let renamedFeedNames = feeds
            .filter { $0.id == "feed-1" || $0.id == "feed-2" }
            .map(\.folderName)
        let untouchedFeed = feeds.first { $0.id == "feed-3" }

        #expect(renamedFeedNames == ["Technology", "Technology"])
        #expect(untouchedFeed?.folderName == "Other")
    }

    @Test func renameFolderRejectsEmptyName() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let folderStore = FeedFolderStore(database: database)
        try folderStore.save(FeedFolderRecord(id: "folder-1", name: "Tech"))

        #expect(throws: FeedFolderRenameError.emptyName) {
            try folderStore.renameFolder(from: "Tech", to: "   ")
        }

        let folders = try folderStore.folders()
        #expect(folders.map(\.name) == ["Tech"])
    }

    @Test func renameFolderRejectsCollisionWithAnotherFolderCaseInsensitively() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let folderStore = FeedFolderStore(database: database)
        try folderStore.save(FeedFolderRecord(id: "folder-1", name: "Tech"))
        try folderStore.save(FeedFolderRecord(id: "folder-2", name: "News"))

        #expect(throws: FeedFolderRenameError.duplicateName) {
            try folderStore.renameFolder(from: "Tech", to: "news")
        }

        let folders = try folderStore.folders()
        #expect(Set(folders.map(\.name)) == ["Tech", "News"])
    }

    @Test func renameFolderAllowsCaseOnlyCorrectionOfOwnName() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let folderStore = FeedFolderStore(database: database)
        try folderStore.save(FeedFolderRecord(id: "folder-1", name: "tech"))

        try folderStore.renameFolder(from: "tech", to: "Tech")

        let folders = try folderStore.folders()
        #expect(folders.map(\.name) == ["Tech"])
    }

    @Test func materializeImplicitFoldersLegtDatensatzFuerReinImplizitenOrdnerAn() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let folderStore = FeedFolderStore(database: database)

        try feedStore.save(
            FeedRecord(id: "feed-1", url: "https://a.example/feed.xml", title: "A", folderName: "News")
        )

        try folderStore.materializeImplicitFolders()

        let folders = try folderStore.folders()
        #expect(folders.map(\.name) == ["News"])
        #expect(folders.first?.sortIndex == 0)
    }

    @Test func materializeImplicitFoldersIstIdempotent() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let folderStore = FeedFolderStore(database: database)

        try feedStore.save(
            FeedRecord(id: "feed-1", url: "https://a.example/feed.xml", title: "A", folderName: "News")
        )

        try folderStore.materializeImplicitFolders()
        try folderStore.materializeImplicitFolders()

        let folders = try folderStore.folders()
        #expect(folders.map(\.name) == ["News"])
    }

    @Test func materializeImplicitFoldersUeberspringtBereitsExplizitenOrdner() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let folderStore = FeedFolderStore(database: database)

        try folderStore.save(FeedFolderRecord(id: "folder-1", name: "Tech", sortIndex: 0))
        try feedStore.save(
            FeedRecord(id: "feed-1", url: "https://a.example/feed.xml", title: "A", folderName: "Tech")
        )

        try folderStore.materializeImplicitFolders()

        let folders = try folderStore.folders()
        #expect(folders.count == 1)
        #expect(folders.first?.id == "folder-1")
    }

    @Test func moveFolderVerschiebtOrdnerAnNeuePosition() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let folderStore = FeedFolderStore(database: database)
        try folderStore.save(FeedFolderRecord(id: "folder-a", name: "Alpha", sortIndex: 0))
        try folderStore.save(FeedFolderRecord(id: "folder-b", name: "Bravo", sortIndex: 1))
        try folderStore.save(FeedFolderRecord(id: "folder-c", name: "Charlie", sortIndex: 2))

        try folderStore.moveFolder(name: "Charlie", targetIndex: 0)

        let orderedNames = try folderStore.folders()
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.name)
        #expect(orderedNames == ["Charlie", "Alpha", "Bravo"])
    }

    @Test func moveFolderMaterialisiertReinImplizitenOrdnerVorDemVerschieben() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedStore = FeedStore(database: database)
        let folderStore = FeedFolderStore(database: database)
        try folderStore.save(FeedFolderRecord(id: "folder-a", name: "Alpha", sortIndex: 0))
        try feedStore.save(
            FeedRecord(id: "feed-1", url: "https://a.example/feed.xml", title: "A", folderName: "News")
        )

        try folderStore.moveFolder(name: "News", targetIndex: 0)

        let orderedNames = try folderStore.folders()
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.name)
        #expect(orderedNames == ["News", "Alpha"])
    }

    @Test func moveFolderKlemmtTargetIndexAufGueltigenBereich() throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let folderStore = FeedFolderStore(database: database)
        try folderStore.save(FeedFolderRecord(id: "folder-a", name: "Alpha", sortIndex: 0))
        try folderStore.save(FeedFolderRecord(id: "folder-b", name: "Bravo", sortIndex: 1))

        try folderStore.moveFolder(name: "Alpha", targetIndex: 999)

        let orderedNames = try folderStore.folders()
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.name)
        #expect(orderedNames == ["Bravo", "Alpha"])
    }
}
