import AppKit
import Foundation
import Testing
@testable import Feedivo

struct SidebarOutlineDropPolicyTests {
    private func makeFeed(id: String, folderName: String?) -> FeedSidebarSnapshot {
        FeedSidebarSnapshot(
            id: id, title: id, faviconURL: nil, folderName: folderName, sortIndex: 0,
            unreadCount: 0, hasRecentError: false
        )
    }

    @Test func feedAufOrdnerGezogenLiefertZielOrdnerUndEndeAlsIndex() {
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [makeFeed(id: "feed-1", folderName: nil), makeFeed(id: "feed-2", folderName: "News")],
            feedFolders: [FeedFolderRecord(id: "f1", name: "News", sortIndex: 0)],
            tagSnapshots: [], smartFolderSnapshots: []
        )
        let foldersHeader = nodes.first { $0.id == "header.folders" }!
        let folderNode = foldersHeader.children.first { $0.id == "folder:News" }!

        let result = SidebarOutlineDropPolicy.resolve(
            draggedNodeID: "feed:feed-1",
            proposedParent: folderNode,
            proposedChildIndex: NSOutlineViewDropOnItemIndex,
            rootNodes: nodes
        )

        #expect(result == .feedDrop(folderName: "News", targetIndex: 1))
    }

    @Test func feedInnerhalbOrdnerlosemBereichUmsortierenBerechnetKorrektenIndex() {
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [
                makeFeed(id: "feed-1", folderName: nil),
                makeFeed(id: "feed-2", folderName: nil),
                makeFeed(id: "feed-3", folderName: nil)
            ],
            feedFolders: [], tagSnapshots: [], smartFolderSnapshots: []
        )
        let foldersHeader = nodes.first { $0.id == "header.folders" }!

        // feed-3 wird an Position 0 gezogen (vor feed-1)
        let result = SidebarOutlineDropPolicy.resolve(
            draggedNodeID: "feed:feed-3",
            proposedParent: foldersHeader,
            proposedChildIndex: 0,
            rootNodes: nodes
        )

        #expect(result == .feedDrop(folderName: nil, targetIndex: 0))
    }

    @Test func ordnerKannNurUnterFoldersHeaderUmsortiertWerden() {
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [],
            feedFolders: [
                FeedFolderRecord(id: "f1", name: "Alpha", sortIndex: 0),
                FeedFolderRecord(id: "f2", name: "Bravo", sortIndex: 1)
            ],
            tagSnapshots: [], smartFolderSnapshots: []
        )
        let foldersHeader = nodes.first { $0.id == "header.folders" }!

        let result = SidebarOutlineDropPolicy.resolve(
            draggedNodeID: "folder:Bravo",
            proposedParent: foldersHeader,
            proposedChildIndex: 0,
            rootNodes: nodes
        )

        #expect(result == .folderReorder(targetIndex: 0))
    }

    @Test func tagKannNurUnterTagsHeaderUmsortiertWerden() {
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [], feedFolders: [],
            tagSnapshots: [
                TagSidebarSnapshot(id: "tag-a", name: "Alpha", colorHex: "#000", articleCount: 0),
                TagSidebarSnapshot(id: "tag-b", name: "Bravo", colorHex: "#000", articleCount: 0)
            ],
            smartFolderSnapshots: []
        )
        let tagsHeader = nodes.first { $0.id == "header.tags" }!

        let result = SidebarOutlineDropPolicy.resolve(
            draggedNodeID: "tag:tag-b",
            proposedParent: tagsHeader,
            proposedChildIndex: 0,
            rootNodes: nodes
        )

        #expect(result == .tagReorder(targetIndex: 0))
    }

    @Test func smartFolderKannNichtUeberGruppengrenzeGezogenWerden() {
        let defaultFolder = SQLiteSmartFolderSnapshot(id: "sf-default", name: "Alle", matchMode: .all, conditions: [], defaultKey: "all")
        let customFolder = SQLiteSmartFolderSnapshot(id: "sf-custom", name: "Meine", matchMode: .all, conditions: [], defaultKey: nil)
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [], feedFolders: [], tagSnapshots: [],
            smartFolderSnapshots: [defaultFolder, customFolder]
        )
        let customHeader = nodes.first { $0.id == "header.smartFolders.custom" }!

        // Standard-Smart-Folder wird auf die "Eigene"-Gruppe fallen gelassen — muss abgelehnt werden.
        let result = SidebarOutlineDropPolicy.resolve(
            draggedNodeID: "smartFolder:sf-default",
            proposedParent: customHeader,
            proposedChildIndex: 0,
            rootNodes: nodes
        )

        #expect(result == nil)
    }

    @Test func smartFolderInnerhalbEigenerGruppeUmsortierenIstErlaubt() {
        let folderA = SQLiteSmartFolderSnapshot(id: "sf-a", name: "A", matchMode: .all, conditions: [], defaultKey: nil)
        let folderB = SQLiteSmartFolderSnapshot(id: "sf-b", name: "B", matchMode: .all, conditions: [], defaultKey: nil)
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [], feedFolders: [], tagSnapshots: [],
            smartFolderSnapshots: [folderA, folderB]
        )
        let customHeader = nodes.first { $0.id == "header.smartFolders.custom" }!

        let result = SidebarOutlineDropPolicy.resolve(
            draggedNodeID: "smartFolder:sf-b",
            proposedParent: customHeader,
            proposedChildIndex: 0,
            rootNodes: nodes
        )

        #expect(result == .smartFolderReorder(isDefault: false, targetIndex: 0))
    }

    @Test func feedUmsortierenBerechnetKorrektenIndexWennOrdnerAlsGeschwisterVorhandenIst() {
        // Zwei ordnerlose Feeds UND ein Ordner (mit eigenem Feed) als
        // Geschwister unter header.folders — deckt ab, dass die gemischte
        // Geschwisterliste (Feeds + Ordner-Knoten) bei der Indexberechnung
        // korrekt behandelt wird, nicht nur eine reine Feed-Geschwisterliste.
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [
                makeFeed(id: "feed-1", folderName: nil),
                makeFeed(id: "feed-2", folderName: nil),
                makeFeed(id: "feed-3", folderName: "News")
            ],
            feedFolders: [FeedFolderRecord(id: "f1", name: "News", sortIndex: 0)],
            tagSnapshots: [], smartFolderSnapshots: []
        )
        let foldersHeader = nodes.first { $0.id == "header.folders" }!

        // Geschwisterliste unter header.folders: [feed-1, feed-2, folder:News]
        // feed-2 wird an Position 0 gezogen (vor feed-1), der Ordner-Knoten
        // bleibt unangetastet am Ende.
        let result = SidebarOutlineDropPolicy.resolve(
            draggedNodeID: "feed:feed-2",
            proposedParent: foldersHeader,
            proposedChildIndex: 0,
            rootNodes: nodes
        )

        #expect(result == .feedDrop(folderName: nil, targetIndex: 0))
    }

    @Test func feedKannNichtInDieTagsHeaderGezogenWerden() {
        let nodes = SidebarOutlineNode.buildTree(
            feedSnapshots: [makeFeed(id: "feed-1", folderName: nil)],
            feedFolders: [], tagSnapshots: [], smartFolderSnapshots: []
        )
        let tagsHeader = nodes.first { $0.id == "header.tags" }!

        let result = SidebarOutlineDropPolicy.resolve(
            draggedNodeID: "feed:feed-1",
            proposedParent: tagsHeader,
            proposedChildIndex: 0,
            rootNodes: nodes
        )

        #expect(result == nil)
    }
}
