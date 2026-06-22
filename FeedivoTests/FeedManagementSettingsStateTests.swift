import Foundation
import Testing
@testable import Feedivo

struct FeedManagementSettingsStateTests {
    @MainActor
    @Test func filteredFeedsSuchtNachTitelURLWebsiteUndOrdner() {
        let macFeed = Feed(
            url: "https://example.com/mac.xml",
            title: "Apple News",
            siteURL: "https://mac.example.com",
            folderName: "Technik"
        )
        let adminFeed = Feed(
            url: "https://admin.example.com/feed.xml",
            title: "PowerShell Blog",
            siteURL: "https://admin.example.com",
            folderName: "IT"
        )
        let feeds = [macFeed, adminFeed]

        #expect(FeedManagementSettingsState.filteredFeeds(feeds, searchText: "mac") == [macFeed])
        #expect(FeedManagementSettingsState.filteredFeeds(feeds, searchText: "admin.example") == [adminFeed])
        #expect(FeedManagementSettingsState.filteredFeeds(feeds, searchText: "technik") == [macFeed])
        #expect(FeedManagementSettingsState.filteredFeeds(feeds, searchText: " ") == feeds)
    }

    @MainActor
    @Test func selectVisibleFeedsErgaenztAuswahlUndClearLeertSie() {
        let firstFeed = Feed(url: "https://example.com/1.xml", title: "One")
        let secondFeed = Feed(url: "https://example.com/2.xml", title: "Two")
        let hiddenFeed = Feed(url: "https://example.com/3.xml", title: "Three")
        var selectedFeedIDs: Set<UUID> = [hiddenFeed.id]

        FeedManagementSettingsState.selectVisibleFeeds(
            [firstFeed, secondFeed],
            selectedFeedIDs: &selectedFeedIDs
        )

        #expect(selectedFeedIDs == [firstFeed.id, secondFeed.id, hiddenFeed.id])

        FeedManagementSettingsState.clearSelection(&selectedFeedIDs)

        #expect(selectedFeedIDs.isEmpty)
    }
}
