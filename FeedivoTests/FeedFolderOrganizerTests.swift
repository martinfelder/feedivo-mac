import Testing
@testable import Feedivo

struct FeedFolderOrganizerTests {

    @Test func folderNamesSindGetrimmtEindeutigUndAlphabetischSortiert() {
        let feeds = [
            Feed(url: "https://example.com/a.xml", title: "A", folderName: " Tech "),
            Feed(url: "https://example.com/b.xml", title: "B", folderName: "News"),
            Feed(url: "https://example.com/c.xml", title: "C", folderName: "tech"),
            Feed(url: "https://example.com/d.xml", title: "D", folderName: " ")
        ]

        #expect(FeedFolderOrganizer.folderNames(in: feeds) == ["News", "Tech"])
    }

    @Test func folderNamesEnthaltenAuchLeereAngelegteOrdner() {
        let feeds = [
            Feed(url: "https://example.com/a.xml", title: "A", folderName: "Tech")
        ]
        let folders = [
            FeedFolder(name: "Later"),
            FeedFolder(name: " tech ")
        ]

        #expect(FeedFolderOrganizer.folderNames(in: feeds, folders: folders) == ["Later", "Tech"])
    }

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

    @Test func feedsOhneOrdnerIgnoriertLeereOrdnernamen() {
        let feeds = [
            Feed(url: "https://example.com/a.xml", title: "A", folderName: nil),
            Feed(url: "https://example.com/b.xml", title: "B", folderName: " "),
            Feed(url: "https://example.com/c.xml", title: "C", folderName: "Tech")
        ]

        let titles = FeedFolderOrganizer.feedsWithoutFolder(from: feeds).map(\.title)

        #expect(titles == ["A", "B"])
    }

    @Test func visibleFeedsBlendetGeleseneFeedsOptionalAus() {
        let unreadFeed = Feed(url: "https://example.com/unread.xml", title: "Ungelesen")
        unreadFeed.unreadCount = 2
        let readFeed = Feed(url: "https://example.com/read.xml", title: "Gelesen")
        readFeed.unreadCount = 0

        #expect(
            FeedFolderOrganizer.visibleFeeds(
                from: [readFeed, unreadFeed],
                showsReadFeeds: true
            )
            .map(\.title) == ["Gelesen", "Ungelesen"]
        )
        #expect(
            FeedFolderOrganizer.visibleFeeds(
                from: [readFeed, unreadFeed],
                showsReadFeeds: false
            )
            .map(\.title) == ["Ungelesen"]
        )
    }

    @Test func normalizeFolderNameSpeichertNilFuerLeereEingaben() {
        #expect(FeedFolderOrganizer.normalizedFolderName(" News ") == "News")
        #expect(FeedFolderOrganizer.normalizedFolderName(" ") == nil)
        #expect(FeedFolderOrganizer.normalizedFolderName(nil) == nil)
    }

    @Test func feedsByFolderNameGruppiertInEinemDurchlaufUndErhaeltLeereOrdner() {
        let feeds = [
            Feed(url: "https://example.com/a.xml", title: "A", folderName: "Tech"),
            Feed(url: "https://example.com/b.xml", title: "B", folderName: "tech"),
            Feed(url: "https://example.com/c.xml", title: "C", folderName: "News"),
            Feed(url: "https://example.com/d.xml", title: "D", folderName: nil)
        ]
        let folders = [
            FeedFolder(name: "Later")
        ]

        let grouped = FeedFolderOrganizer.feedsByFolderName(in: feeds, folders: folders)

        #expect(grouped.map(\.folderName) == ["Later", "News", "Tech"])
        #expect(grouped.first { $0.folderName == "Later" }?.feeds.isEmpty == true)
        #expect(grouped.first { $0.folderName == "News" }?.feeds.map(\.title) == ["C"])
        // "Tech" und "tech" werden case-insensitive zusammengefasst (kanonischer Name "Tech").
        #expect(grouped.first { $0.folderName == "Tech" }?.feeds.map(\.title) == ["A", "B"])
    }
}
