import Testing
@testable import Feedivo

struct FeedCommandActionsTests {

    @Test func addFeedAktionIstOhneAuswahlVerfuegbar() {
        var didRequestAddFeed = false
        let actions = FeedCommandActions(
            selectedFeed: nil,
            requestAddFeed: {
                didRequestAddFeed = true
            },
            refreshAllFeeds: {},
            refreshSelectedFeed: {},
            requestDelete: {}
        )

        #expect(actions.canAddFeed)
        #expect(!actions.canPerformFeedAction)

        actions.requestAddFeed()

        #expect(didRequestAddFeed)
    }

    @Test func alleFeedsAktualisierenIstOhneAuswahlVerfuegbar() {
        var didRefreshAllFeeds = false
        let actions = FeedCommandActions(
            selectedFeed: nil,
            requestAddFeed: {},
            refreshAllFeeds: {
                didRefreshAllFeeds = true
            },
            refreshSelectedFeed: {},
            requestDelete: {}
        )

        #expect(actions.canRefreshAllFeeds)
        #expect(!actions.canPerformFeedAction)

        actions.refreshAllFeeds()

        #expect(didRefreshAllFeeds)
    }
}
