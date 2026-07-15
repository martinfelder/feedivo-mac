import Foundation
import Testing
@testable import Feedivo

struct SidebarOutlineNodeTests {
    private func makeFeed(id: String, title: String, folderName: String?, sortIndex: Int = 0) -> FeedSidebarSnapshot {
        FeedSidebarSnapshot(
            id: id,
            title: title,
            url: "https://example.com/\(id).xml",
            faviconURL: nil,
            folderName: folderName,
            sortIndex: sortIndex,
            unreadCount: 0,
            hasRecentError: false
        )
    }

    private func makeSmartFolder(id: String, name: String, defaultKey: String?) -> SQLiteSmartFolderSnapshot {
        SQLiteSmartFolderSnapshot(
            id: id,
            name: name,
            matchMode: .all,
            conditions: [],
            defaultKey: defaultKey
        )
    }

    @Test func buildTreeErzeugtGenauVierWurzelKnoten() {
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [],
            feedFolders: [],
            tagSnapshots: [],
            smartFolderSnapshots: []
        )
        #expect(nodes.count == 4)
        #expect(nodes.map(\.id) == [
            "header.smartFolders.default",
            "header.smartFolders.custom",
            "header.tags",
            "header.folders"
        ])
    }

    @Test func buildTreeTrenntStandardUndEigeneSmartFolders() {
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [],
            feedFolders: [],
            tagSnapshots: [],
            smartFolderSnapshots: [
                makeSmartFolder(id: "sf-default", name: "Alle", defaultKey: "all"),
                makeSmartFolder(id: "sf-custom", name: "Meine Auswahl", defaultKey: nil)
            ]
        )

        let defaultHeader = nodes.first { $0.id == "header.smartFolders.default" }
        let customHeader = nodes.first { $0.id == "header.smartFolders.custom" }
        #expect(defaultHeader?.children.map(\.id) == ["smartFolder:sf-default"])
        #expect(customHeader?.children.map(\.id) == ["smartFolder:sf-custom"])
    }

    @Test func buildTreeOrdnetFeedsOhneOrdnerVorDenOrdnernEin() {
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [
                makeFeed(id: "feed-1", title: "Ohne Ordner", folderName: nil),
                makeFeed(id: "feed-2", title: "Mit Ordner", folderName: "News")
            ],
            feedFolders: [FeedFolderRecord(id: "folder-1", name: "News", sortIndex: 0)],
            tagSnapshots: [],
            smartFolderSnapshots: []
        )

        let foldersHeader = nodes.first { $0.id == "header.folders" }
        #expect(foldersHeader?.children.map(\.id) == ["feed:feed-1", "folder:News"])

        let folderNode = foldersHeader?.children.first { $0.id == "folder:News" }
        #expect(folderNode?.children.map(\.id) == ["feed:feed-2"])
    }

    @Test func buildTreeUebernimmtTagsInSortIndexReihenfolge() {
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [],
            feedFolders: [],
            tagSnapshots: [
                TagSidebarSnapshot(id: "tag-a", name: "Alpha", colorHex: "#000000", articleCount: 0),
                TagSidebarSnapshot(id: "tag-b", name: "Bravo", colorHex: "#000000", articleCount: 0)
            ],
            smartFolderSnapshots: []
        )

        let tagsHeader = nodes.first { $0.id == "header.tags" }
        #expect(tagsHeader?.children.map(\.id) == ["tag:tag-a", "tag:tag-b"])
    }

    @Test func findDurchsuchtDenGesamtenBaumRekursiv() {
        let feed = makeFeed(id: "feed-1", title: "Verschachtelt", folderName: "News")
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [feed],
            feedFolders: [FeedFolderRecord(id: "folder-1", name: "News", sortIndex: 0)],
            tagSnapshots: [],
            smartFolderSnapshots: []
        )

        let found = SidebarOutlineNode.find(id: "feed:feed-1", in: nodes)
        #expect(found != nil)

        let notFound = SidebarOutlineNode.find(id: "feed:missing", in: nodes)
        #expect(notFound == nil)
    }

    @Test func nodesMitGleicherIdSindGleich() {
        let a = SidebarOutlineNode(id: "x", payload: .tagsHeader)
        let b = SidebarOutlineNode(id: "x", payload: .foldersHeader)
        #expect(a.isEqual(b))
    }
}
