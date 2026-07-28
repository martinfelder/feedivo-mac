import Foundation
import Testing
@testable import Feedivo

struct FeedManagementSettingsStateTests {
    @Test func filteredFeedsSuchtNachTitelURLWebsiteUndOrdner() {
        let macFeed = FeedRecord(
            id: "feed-mac",
            url: "https://example.com/mac.xml",
            title: "Apple News",
            websiteURL: "https://mac.example.com",
            folderName: "Technik"
        )
        let adminFeed = FeedRecord(
            id: "feed-admin",
            url: "https://admin.example.com/feed.xml",
            title: "PowerShell Blog",
            websiteURL: "https://admin.example.com",
            folderName: "IT"
        )
        let feeds = [macFeed, adminFeed]

        #expect(FeedManagementSettingsState.filteredFeeds(feeds, searchText: "mac") == [macFeed])
        #expect(FeedManagementSettingsState.filteredFeeds(feeds, searchText: "admin.example") == [adminFeed])
        #expect(FeedManagementSettingsState.filteredFeeds(feeds, searchText: "technik") == [macFeed])
        #expect(FeedManagementSettingsState.filteredFeeds(feeds, searchText: " ") == feeds)
    }

    @Test func selectVisibleFeedsErgaenztAuswahlUndClearLeertSie() {
        let firstFeed = FeedRecord(id: "feed-1", url: "https://example.com/1.xml", title: "One")
        let secondFeed = FeedRecord(id: "feed-2", url: "https://example.com/2.xml", title: "Two")
        let hiddenFeed = FeedRecord(id: "feed-3", url: "https://example.com/3.xml", title: "Three")
        var selectedFeedIDs: Set<String> = [hiddenFeed.id]

        FeedManagementSettingsState.selectVisibleFeeds(
            [firstFeed, secondFeed],
            selectedFeedIDs: &selectedFeedIDs
        )

        #expect(selectedFeedIDs == [firstFeed.id, secondFeed.id, hiddenFeed.id])

        FeedManagementSettingsState.clearSelection(&selectedFeedIDs)

        #expect(selectedFeedIDs.isEmpty)
    }
}
