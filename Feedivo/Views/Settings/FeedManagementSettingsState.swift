import Foundation

enum FeedManagementSettingsState {
    static func filteredFeeds(_ feeds: [FeedRecord], searchText: String) -> [FeedRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return feeds
        }

        return feeds.filter { feed in
            searchableText(for: feed).contains(query)
        }
    }

    static func selectVisibleFeeds(_ feeds: [FeedRecord], selectedFeedIDs: inout Set<String>) {
        selectedFeedIDs.formUnion(feeds.map(\.id))
    }

    static func clearSelection(_ selectedFeedIDs: inout Set<String>) {
        selectedFeedIDs.removeAll()
    }

    private static func searchableText(for feed: FeedRecord) -> String {
        [
            feed.title,
            feed.originalTitle,
            feed.url,
            feed.websiteURL,
            feed.folderName
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    }
}
