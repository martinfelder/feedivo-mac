import Testing
@testable import Feedivo

private struct CapturingBadgeUpdater: AppIconBadgeUpdating {
    var badgeLabel: String?
}

struct AppIconBadgeServiceTests {
    // T2/T9: SQLite-Variante — ContentView speist den Dock-Badge aus
    // `FeedSidebarSnapshot.unreadCount` (Summe), ohne SwiftData-`Feed`-Objekte.
    @Test func unreadCountAusSidebarSnapshotsSummiert() {
        let snapshots = [
            FeedSidebarSnapshot(id: "1", title: "A", url: "u", faviconURL: nil, folderName: nil, unreadCount: 4, hasRecentError: false),
            FeedSidebarSnapshot(id: "2", title: "B", url: "u", faviconURL: nil, folderName: nil, unreadCount: 0, hasRecentError: false),
            FeedSidebarSnapshot(id: "3", title: "C", url: "u", faviconURL: nil, folderName: nil, unreadCount: 6, hasRecentError: false)
        ]

        #expect(AppIconBadgeService.unreadCount(in: snapshots) == 10)
    }

    @Test func unreadCountAusLeerenSnapshotsIstNull() {
        #expect(AppIconBadgeService.unreadCount(in: [] as [FeedSidebarSnapshot]) == 0)
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
