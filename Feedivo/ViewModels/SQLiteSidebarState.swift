import Foundation
import Observation

@MainActor
@Observable
final class SQLiteSidebarState {
    private(set) var snapshots: [FeedSidebarSnapshot] = []
    private(set) var totalUnreadCount = 0
    private(set) var errorMessage: String?

    private var snapshotsByFeedID: [String: FeedSidebarSnapshot] = [:]
    private var visibleFeedIDs: Set<String> = []

    func load(database: FeedivoDatabase?, showsReadFeeds: Bool) {
        guard let database else {
            snapshots = []
            snapshotsByFeedID = [:]
            visibleFeedIDs = []
            totalUnreadCount = 0
            errorMessage = nil
            return
        }

        do {
            let store = FeedStore(database: database)
            let loadedSnapshots = try store.sidebarFeeds(showsReadFeeds: showsReadFeeds)
            snapshots = loadedSnapshots
            snapshotsByFeedID = Dictionary(uniqueKeysWithValues: loadedSnapshots.map { ($0.id, $0) })
            visibleFeedIDs = Set(loadedSnapshots.map(\.id))
            totalUnreadCount = loadedSnapshots.reduce(0) { total, snapshot in
                total + snapshot.unreadCount
            }
            errorMessage = nil
        } catch {
            snapshots = []
            snapshotsByFeedID = [:]
            visibleFeedIDs = []
            totalUnreadCount = 0
            errorMessage = error.localizedDescription
        }
    }

    func snapshot(for feed: Feed) -> FeedSidebarSnapshot? {
        snapshotsByFeedID[feed.id.uuidString]
    }

    func visibleFeeds(from feeds: [Feed], showsReadFeeds: Bool) -> [Feed] {
        guard !snapshots.isEmpty else {
            return FeedFolderOrganizer.visibleFeeds(
                from: feeds,
                showsReadFeeds: showsReadFeeds
            )
        }

        let feedsByID = Dictionary(uniqueKeysWithValues: feeds.map { ($0.id.uuidString, $0) })
        let visibleFeeds = snapshots.compactMap { snapshot in
            feedsByID[snapshot.id]
        }

        guard !visibleFeeds.isEmpty else {
            return FeedFolderOrganizer.visibleFeeds(
                from: feeds,
                showsReadFeeds: showsReadFeeds
            )
        }

        return visibleFeeds
    }
}
