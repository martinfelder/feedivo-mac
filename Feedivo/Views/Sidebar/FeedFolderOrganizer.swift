import Foundation

enum SidebarFeedVisibilitySettings {
    static let showsReadFeedsKey = "sidebar.showsReadFeeds"
    static let defaultShowsReadFeeds = true
}

enum FeedFolderOrganizer {

    static func folderNames(in feeds: [Feed], folders: [FeedFolder] = []) -> [String] {
        var canonicalNamesByLowercasedName: [String: String] = [:]

        for feed in feeds {
            insert(folderName: feed.folderName, into: &canonicalNamesByLowercasedName)
        }

        for folder in folders {
            insert(folderName: folder.name, into: &canonicalNamesByLowercasedName)
        }

        return canonicalNamesByLowercasedName.values.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    static func feedsWithoutFolder(from feeds: [Feed]) -> [Feed] {
        sortedFeeds(
            feeds.filter { normalizedFolderName($0.folderName) == nil }
        )
    }

    static func visibleFeeds(from feeds: [Feed], showsReadFeeds: Bool) -> [Feed] {
        guard !showsReadFeeds else {
            return sortedFeeds(feeds)
        }

        return sortedFeeds(
            feeds.filter { $0.unreadCount > 0 }
        )
    }

    static func feeds(in folderName: String, from feeds: [Feed]) -> [Feed] {
        let normalizedName = normalizedFolderName(folderName)

        return sortedFeeds(
            feeds.filter {
                normalizedFolderName($0.folderName)?.caseInsensitiveCompare(normalizedName ?? "") == .orderedSame
            }
        )
    }

    static func normalizedFolderName(_ folderName: String?) -> String? {
        guard let trimmedName = folderName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedName.isEmpty
        else {
            return nil
        }

        return trimmedName
    }

    private static func sortedFeeds(_ feeds: [Feed]) -> [Feed] {
        feeds.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private static func insert(
        folderName: String?,
        into canonicalNamesByLowercasedName: inout [String: String]
    ) {
        guard let folderName = normalizedFolderName(folderName) else {
            return
        }

        let key = folderName.lowercased()
        if canonicalNamesByLowercasedName[key] == nil {
            canonicalNamesByLowercasedName[key] = folderName
        }
    }
}
