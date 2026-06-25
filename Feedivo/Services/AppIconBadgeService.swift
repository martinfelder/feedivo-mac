import AppKit

protocol AppIconBadgeUpdating {
    var badgeLabel: String? { get set }
}

struct DockTileBadgeUpdater: AppIconBadgeUpdating {
    var badgeLabel: String? {
        get {
            NSApp.dockTile.badgeLabel
        }
        set {
            NSApp.dockTile.badgeLabel = newValue
        }
    }
}

enum AppIconBadgeService {
    static func unreadCount(in feeds: [Feed]) -> Int {
        feeds.reduce(0) { total, feed in
            total + feed.unreadCount
        }
    }

    static func updateBadge<Updater: AppIconBadgeUpdating>(
        unreadCount: Int,
        isEnabled: Bool,
        updater: inout Updater
    ) {
        guard isEnabled, unreadCount > 0 else {
            updater.badgeLabel = nil
            return
        }

        updater.badgeLabel = "\(unreadCount)"
    }

    static func updateBadge<Updater: AppIconBadgeUpdating>(
        for feeds: [Feed],
        isEnabled: Bool,
        updater: inout Updater
    ) {
        updateBadge(
            unreadCount: unreadCount(in: feeds),
            isEnabled: isEnabled,
            updater: &updater
        )
    }
}
