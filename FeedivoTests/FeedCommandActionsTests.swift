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
            refreshSelectedFeed: {},
            requestDelete: {}
        )

        #expect(actions.canAddFeed)
        #expect(!actions.canPerformFeedAction)

        actions.requestAddFeed()

        #expect(didRequestAddFeed)
    }
}
