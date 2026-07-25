import Testing
@testable import Feedivo

struct FeedFolderOrganizerTests {

    @Test func folderNamesKoennenAusLeichtenStringsGebildetWerden() {
        let feedFolderNames = [" Tech ", "News", "tech", ""]
        let folderNames = ["Later", " news "]

        #expect(
            FeedFolderOrganizer.folderNames(
                feedFolderNames: feedFolderNames,
                explicitFolderNames: folderNames
            ) == ["Later", "News", "Tech"]
        )
    }

    @Test func normalizeFolderNameSpeichertNilFuerLeereEingaben() {
        #expect(FeedFolderOrganizer.normalizedFolderName(" News ") == "News")
        #expect(FeedFolderOrganizer.normalizedFolderName(" ") == nil)
        #expect(FeedFolderOrganizer.normalizedFolderName(nil) == nil)
    }

    @Test func feedsWithoutFolderSortiertNachSortIndexNichtAlphabetisch() {
        let snapshots = [
            FeedSidebarSnapshot(id: "1", title: "Zulu", sortIndex: 0, unreadCount: 0, hasRecentError: false),
            FeedSidebarSnapshot(id: "2", title: "Alpha", sortIndex: 1, unreadCount: 0, hasRecentError: false)
        ]

        let ordered = FeedFolderOrganizer.feedsWithoutFolder(from: snapshots)

        #expect(ordered.map(\.id) == ["1", "2"])
    }

    @Test func feedsByFolderNameSortiertOrdnerNachSortIndexDerFeedFolderRecords() {
        let snapshots = [
            FeedSidebarSnapshot(id: "1", title: "A", folderName: "Zeta", unreadCount: 0, hasRecentError: false),
            FeedSidebarSnapshot(id: "2", title: "B", folderName: "Alpha", unreadCount: 0, hasRecentError: false)
        ]
        let folders = [
            FeedFolderRecord(id: "f-zeta", name: "Zeta", sortIndex: 0),
            FeedFolderRecord(id: "f-alpha", name: "Alpha", sortIndex: 1)
        ]

        let grouped = FeedFolderOrganizer.feedsByFolderName(in: snapshots, folders: folders)

        #expect(grouped.map(\.folderName) == ["Zeta", "Alpha"])
    }

    @Test func folderNamesMitExplicitFoldersSortiertNachSortIndexMitAlphabetischemFallback() {
        let folders = [
            FeedFolderRecord(id: "f-b", name: "Bravo", sortIndex: 0),
            FeedFolderRecord(id: "f-a", name: "Alpha", sortIndex: 1)
        ]

        let names = FeedFolderOrganizer.folderNames(feedFolderNames: [], explicitFolders: folders)

        #expect(names == ["Bravo", "Alpha"])
    }
}
