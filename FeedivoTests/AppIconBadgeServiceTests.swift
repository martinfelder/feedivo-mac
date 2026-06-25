import Testing
@testable import Feedivo

private struct CapturingBadgeUpdater: AppIconBadgeUpdating {
    var badgeLabel: String?
}

struct AppIconBadgeServiceTests {
    @Test func unreadCountZaehltGespeicherteFeedZaehler() {
        let firstFeed = Feed(url: "https://example.com/first.xml", title: "Erster Feed")
        let secondFeed = Feed(url: "https://example.com/second.xml", title: "Zweiter Feed")
        firstFeed.unreadCount = 2
        secondFeed.unreadCount = 3

        #expect(AppIconBadgeService.unreadCount(in: [firstFeed, secondFeed]) == 5)
    }

    @Test func updateBadgeSetztUngelesenZaehlerWennAktiv() {
        var updater = CapturingBadgeUpdater()

        AppIconBadgeService.updateBadge(
            unreadCount: 7,
            isEnabled: true,
            updater: &updater
        )

        #expect(updater.badgeLabel == "7")
    }

    @Test func updateBadgeLeertBadgeWennKeineUngelesenenArtikelVorhandenSind() {
        var updater = CapturingBadgeUpdater(badgeLabel: "3")

        AppIconBadgeService.updateBadge(
            unreadCount: 0,
            isEnabled: true,
            updater: &updater
        )

        #expect(updater.badgeLabel == nil)
    }

    @Test func updateBadgeLeertBadgeWennEinstellungDeaktiviertIst() {
        var updater = CapturingBadgeUpdater(badgeLabel: "3")

        AppIconBadgeService.updateBadge(
            unreadCount: 3,
            isEnabled: false,
            updater: &updater
        )

        #expect(updater.badgeLabel == nil)
    }
}
