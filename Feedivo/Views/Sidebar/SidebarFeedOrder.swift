import Foundation

/// Reine Nachschlage-Logik für den automatischen Feed-Sprung am Ende/Anfang
/// der Artikelliste: liefert die exakt sichtbare Sidebar-Reihenfolge aller
/// Feeds (nicht-einsortierte Feeds zuerst, dann Ordner der Reihe nach) und
/// findet darin den nächsten/vorherigen Feed mit ungelesenen Artikeln. Nutzt
/// dieselben Bausteine (`FeedFolderOrganizer`), die auch die eigentliche
/// Sidebar-Baumstruktur (`SidebarOutlineNode.buildTree`) verwendet — keine
/// AppKit-/NSOutlineView-Abhängigkeit.
enum SidebarFeedOrder {
    static func orderedFeeds(
        from snapshots: [FeedSidebarSnapshot],
        folders: [FeedFolderRecord]
    ) -> [FeedSidebarSnapshot] {
        let unfoldered = FeedFolderOrganizer.feedsWithoutFolder(from: snapshots)
        let foldered = FeedFolderOrganizer.feedsByFolderName(in: snapshots, folders: folders)
            .flatMap(\.snapshots)
        return unfoldered + foldered
    }

    static func nextFeedWithUnread(
        after feedID: String,
        in orderedFeeds: [FeedSidebarSnapshot]
    ) -> FeedSidebarSnapshot? {
        guard let currentIndex = orderedFeeds.firstIndex(where: { $0.id == feedID }) else {
            return nil
        }

        return orderedFeeds[orderedFeeds.index(after: currentIndex)...].first { $0.unreadCount > 0 }
    }

    static func previousFeedWithUnread(
        before feedID: String,
        in orderedFeeds: [FeedSidebarSnapshot]
    ) -> FeedSidebarSnapshot? {
        guard let currentIndex = orderedFeeds.firstIndex(where: { $0.id == feedID }) else {
            return nil
        }

        return orderedFeeds[..<currentIndex].reversed().first { $0.unreadCount > 0 }
    }
}
