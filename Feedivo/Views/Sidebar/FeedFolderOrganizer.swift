import Foundation

enum SidebarFeedVisibilitySettings {
    static let showsReadFeedsKey = "sidebar.showsReadFeeds"
    static let defaultShowsReadFeeds = true
}

enum FeedFolderOrganizer {

    static func folderNames(in feeds: [Feed], folders: [FeedFolder] = []) -> [String] {
        folderNames(
            feedFolderNames: feeds.map(\.folderName),
            explicitFolderNames: folders.map(\.name)
        )
    }

    static func folderNames(feedFolderNames: [String], explicitFolderNames: [String]) -> [String] {
        folderNames(
            feedFolderNames: feedFolderNames.map(Optional.some),
            explicitFolderNames: explicitFolderNames.map(Optional.some)
        )
    }

    static func folderNames(feedFolderNames: [String?], explicitFolderNames: [String?]) -> [String] {
        var canonicalNamesByLowercasedName: [String: String] = [:]

        for folderName in feedFolderNames {
            insert(folderName: folderName, into: &canonicalNamesByLowercasedName)
        }

        for folderName in explicitFolderNames {
            insert(folderName: folderName, into: &canonicalNamesByLowercasedName)
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

    // Snapshot-basierte Überladungen für den SQLite-only Sidebar-Pfad. Diese
    // Helfer arbeiten ausschließlich auf FeedSidebarSnapshot und brauchen kein
    // SwiftData-Feed-Objekt mehr.
    static func feedsWithoutFolder(from snapshots: [FeedSidebarSnapshot]) -> [FeedSidebarSnapshot] {
        sortedSnapshots(
            snapshots.filter { normalizedFolderName($0.folderName) == nil }
        )
    }

    static func feedsByFolderName(
        in snapshots: [FeedSidebarSnapshot],
        folders: [FeedFolderRecord] = []
    ) -> [(folderName: String, snapshots: [FeedSidebarSnapshot])] {
        let orderedFolderNames = folderNames(
            feedFolderNames: snapshots.map(\.folderName),
            explicitFolderNames: folders.map(\.name)
        )

        var snapshotsByLowercasedName: [String: [FeedSidebarSnapshot]] = [:]
        for snapshot in snapshots {
            guard let normalizedName = normalizedFolderName(snapshot.folderName) else {
                continue
            }
            snapshotsByLowercasedName[normalizedName.lowercased(), default: []].append(snapshot)
        }

        return orderedFolderNames.map { folderName in
            let grouped = snapshotsByLowercasedName[folderName.lowercased()] ?? []
            return (folderName, sortedSnapshots(grouped))
        }
    }

    private static func sortedSnapshots(_ snapshots: [FeedSidebarSnapshot]) -> [FeedSidebarSnapshot] {
        snapshots.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    /// Feeds pro Ordnername in einem Durchlauf gruppieren (M9) — statt für
    /// jeden Ordnernamen `feeds(in:from:)` (je O(F)) aufzurufen. Liefert die
    /// Paare in derselben Reihenfolge wie `folderNames(in:folders:)`, also
    /// alphabetisch nach kanonischem (getrimmtem) Ordnernamen. Ordner, die nur
    /// in `folders` angelegt, aber keiner Feed zugeordnet sind, enthalten ein
    /// leeres Feed-Array, damit der Sidebar-Abschnitt trotzdem gerendert wird.
    static func feedsByFolderName(
        in feeds: [Feed],
        folders: [FeedFolder] = []
    ) -> [(folderName: String, feeds: [Feed])] {
        let orderedFolderNames = folderNames(in: feeds, folders: folders)

        var feedsByLowercasedName: [String: [Feed]] = [:]
        for feed in feeds {
            guard let normalizedName = normalizedFolderName(feed.folderName) else {
                continue
            }
            feedsByLowercasedName[normalizedName.lowercased(), default: []].append(feed)
        }

        return orderedFolderNames.map { folderName in
            let grouped = feedsByLowercasedName[folderName.lowercased()] ?? []
            return (folderName, sortedFeeds(grouped))
        }
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
