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

    // Root-Cause-Fund (Nutzer-Report 2026-07-23): ohne Equatable-Konformität
    // kann SwiftUI zwei bei jedem ContentView.body-Durchlauf frisch gebaute
    // FeedCommandActions-Werte nicht auf Gleichheit prüfen und publiziert
    // jeden Durchlauf über `.focusedSceneValue(...)` als "geändert" — bei
    // mehreren Durchläufen im selben Frame die SwiftUI-Warnung "FocusedValue
    // update tried to update multiple times per frame". Der Vergleich ignoriert
    // bewusst die Closures (nicht vergleichbar, aber immer stabile
    // Ruecksprünge in dieselben Methoden).
    @Test func gleicheDatenfelderSindGleichTrotzUnterschiedlicherClosures() {
        let lhs = FeedCommandActions(
            selectedFeed: nil,
            requestAddFeed: {},
            requestImportOPML: {},
            requestExportOPML: {},
            refreshAllFeeds: {},
            refreshSelectedFeed: {},
            requestDelete: {},
            hasFeeds: true
        )
        let rhs = FeedCommandActions(
            selectedFeed: nil,
            requestAddFeed: { print("anderer Rueckruf") },
            requestImportOPML: {},
            requestExportOPML: {},
            refreshAllFeeds: {},
            refreshSelectedFeed: {},
            requestDelete: {},
            hasFeeds: true
        )

        #expect(lhs == rhs)
    }

    @Test func unterschiedlicherSelectedFeedMachtWerteUngleich() {
        let feed = FeedSidebarSnapshot(
            id: "1",
            title: "Feed",
            unreadCount: 0,
            hasRecentError: false
        )
        let lhs = FeedCommandActions(
            selectedFeed: nil,
            requestAddFeed: {},
            requestImportOPML: {},
            requestExportOPML: {},
            refreshAllFeeds: {},
            refreshSelectedFeed: {},
            requestDelete: {},
            hasFeeds: true
        )
        let rhs = FeedCommandActions(
            selectedFeed: feed,
            requestAddFeed: {},
            requestImportOPML: {},
            requestExportOPML: {},
            refreshAllFeeds: {},
            refreshSelectedFeed: {},
            requestDelete: {},
            hasFeeds: true
        )

        #expect(lhs != rhs)
    }
}
