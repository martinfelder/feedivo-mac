import AppKit

/// Ein Knoten im Sidebar-Baum, der von SidebarOutlineView (NSOutlineView-Bridge)
/// dargestellt wird. NSObject-Subklasse, weil NSOutlineViewDataSource für
/// Item-Identität Referenzsemantik voraussetzt. isEqual/hash sind auf `id`
/// überschrieben, damit ein bei jedem Reload komplett neu aufgebauter Baum
/// (siehe buildTree) trotzdem stabile Identität über reloadData()-Aufrufe
/// hinweg behält (nötig für expandItem/collapseItem-Wiederherstellung).
final class SidebarOutlineNode: NSObject {
    enum Payload {
        case smartFoldersHeader(isDefault: Bool)
        case smartFolder(SQLiteSmartFolderSnapshot)
        case tagsHeader
        case tag(TagSidebarSnapshot)
        case foldersHeader
        case folder(name: String)
        case feed(FeedSidebarSnapshot)
        /// Platzhalter-Zeile für einen leeren Abschnitt (z. B. "Keine
        /// Intelligenten Ordner vorhanden") — nicht selektierbar, nicht
        /// draggable.
        case emptyPlaceholder(text: String)
    }

    let id: String
    let payload: Payload
    private(set) var children: [SidebarOutlineNode]

    init(id: String, payload: Payload, children: [SidebarOutlineNode] = []) {
        self.id = id
        self.payload = payload
        self.children = children
    }

    var isDraggable: Bool {
        switch payload {
        case .feed, .folder, .tag, .smartFolder:
            true
        case .smartFoldersHeader, .tagsHeader, .foldersHeader, .emptyPlaceholder:
            false
        }
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? SidebarOutlineNode else { return false }
        return other.id == id
    }

    override var hash: Int {
        id.hashValue
    }
}

extension SidebarOutlineNode {
    static func buildTree(
        feedSnapshots: [FeedSidebarSnapshot],
        feedFolders: [FeedFolderRecord],
        tagSnapshots: [TagSidebarSnapshot],
        smartFolderSnapshots: [SQLiteSmartFolderSnapshot]
    ) -> [SidebarOutlineNode] {
        let defaultSmartFolders = SmartFolderSidebarGrouping.defaultFolders(from: smartFolderSnapshots)
        let customSmartFolders = SmartFolderSidebarGrouping.customFolders(from: smartFolderSnapshots)

        let defaultHeader = SidebarOutlineNode(
            id: "header.smartFolders.default",
            payload: .smartFoldersHeader(isDefault: true),
            children: defaultSmartFolders.map { folder in
                SidebarOutlineNode(id: "smartFolder:\(folder.id)", payload: .smartFolder(folder))
            }
        )

        let customHeader = SidebarOutlineNode(
            id: "header.smartFolders.custom",
            payload: .smartFoldersHeader(isDefault: false),
            children: customSmartFolders.map { folder in
                SidebarOutlineNode(id: "smartFolder:\(folder.id)", payload: .smartFolder(folder))
            }
        )

        let tagsHeader = SidebarOutlineNode(
            id: "header.tags",
            payload: .tagsHeader,
            children: tagSnapshots.map { tag in
                SidebarOutlineNode(id: "tag:\(tag.id)", payload: .tag(tag))
            }
        )

        let feedsWithoutFolder = FeedFolderOrganizer.feedsWithoutFolder(from: feedSnapshots)
        let folderEntries = FeedFolderOrganizer.feedsByFolderName(in: feedSnapshots, folders: feedFolders)

        var foldersChildren: [SidebarOutlineNode] = feedsWithoutFolder.map { snapshot in
            SidebarOutlineNode(id: "feed:\(snapshot.id)", payload: .feed(snapshot))
        }
        foldersChildren += folderEntries.map { entry in
            SidebarOutlineNode(
                id: "folder:\(entry.folderName)",
                payload: .folder(name: entry.folderName),
                children: entry.snapshots.map { snapshot in
                    SidebarOutlineNode(id: "feed:\(snapshot.id)", payload: .feed(snapshot))
                }
            )
        }

        let foldersHeader = SidebarOutlineNode(
            id: "header.folders",
            payload: .foldersHeader,
            children: foldersChildren
        )

        return [defaultHeader, customHeader, tagsHeader, foldersHeader]
    }

    /// Rekursive Suche über den gesamten Baum anhand der stabilen `id`.
    static func find(id: String, in nodes: [SidebarOutlineNode]) -> SidebarOutlineNode? {
        for node in nodes {
            if node.id == id {
                return node
            }
            if let found = find(id: id, in: node.children) {
                return found
            }
        }
        return nil
    }
}
