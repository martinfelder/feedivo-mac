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
}
