import Foundation

enum FeedManagementSettingsState {
    static func filteredFeeds(_ feeds: [Feed], searchText: String) -> [Feed] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return feeds
        }

        return feeds.filter { feed in
            searchableText(for: feed).contains(query)
        }
    }

    static func selectVisibleFeeds(_ feeds: [Feed], selectedFeedIDs: inout Set<UUID>) {
        selectedFeedIDs.formUnion(feeds.map(\.id))
    }

    static func clearSelection(_ selectedFeedIDs: inout Set<UUID>) {
        selectedFeedIDs.removeAll()
    }

    private static func searchableText(for feed: Feed) -> String {
        [
            feed.title,
            feed.originalTitle,
            feed.url,
            feed.siteURL,
            feed.folderName
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    }
}
