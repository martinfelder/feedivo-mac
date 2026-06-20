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
            requestImportOPML: {},
            requestExportOPML: {},
            refreshAllFeeds: {},
            refreshSelectedFeed: {},
            requestDelete: {},
            hasFeeds: false
        )

        #expect(actions.canAddFeed)
        #expect(actions.canImportOPML)
        #expect(!actions.canExportOPML)
        #expect(!actions.canPerformFeedAction)

        actions.requestAddFeed()

        #expect(didRequestAddFeed)
    }

    @Test func opmlImportIstOhneFeedsVerfuegbar() {
        var didRequestImport = false
        let actions = FeedCommandActions(
            selectedFeed: nil,
            requestAddFeed: {},
            requestImportOPML: {
                didRequestImport = true
            },
            requestExportOPML: {},
            refreshAllFeeds: {},
            refreshSelectedFeed: {},
            requestDelete: {},
            hasFeeds: false
        )

        #expect(actions.canImportOPML)

        actions.requestImportOPML()

        #expect(didRequestImport)
    }

    @Test func opmlExportBrauchtMindestensEinenFeed() {
        var didRequestExport = false
        let actions = FeedCommandActions(
            selectedFeed: nil,
            requestAddFeed: {},
            requestImportOPML: {},
            requestExportOPML: {
                didRequestExport = true
            },
            refreshAllFeeds: {},
            refreshSelectedFeed: {},
            requestDelete: {},
            hasFeeds: true
        )

        #expect(actions.canExportOPML)

        actions.requestExportOPML()

        #expect(didRequestExport)
    }

    @Test func alleFeedsAktualisierenIstOhneAuswahlVerfuegbar() {
        var didRefreshAllFeeds = false
        let actions = FeedCommandActions(
            selectedFeed: nil,
            requestAddFeed: {},
            requestImportOPML: {},
            requestExportOPML: {},
            refreshAllFeeds: {
                didRefreshAllFeeds = true
            },
            refreshSelectedFeed: {},
            requestDelete: {},
            hasFeeds: false
        )

        #expect(actions.canRefreshAllFeeds)
        #expect(!actions.canPerformFeedAction)

        actions.refreshAllFeeds()

        #expect(didRefreshAllFeeds)
    }
}
