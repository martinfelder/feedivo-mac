import AppKit
import Testing
@testable import Feedivo

struct SidebarOutlinePasteboardTests {
    @Test func feedPasteboardItemSchreibtUndLiestIDZurueck() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.clearContents() }

        let writer = SidebarFeedPasteboardItem(feedID: "feed-123")
        pasteboard.clearContents()
        pasteboard.writeObjects([writer])

        let readBack = pasteboard.string(forType: .feedivoFeedDragItem)
        #expect(readBack == "feed-123")
    }

    @Test func folderPasteboardItemSchreibtUndLiestNamenZurueck() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.clearContents() }

        let writer = SidebarFolderPasteboardItem(folderName: "News")
        pasteboard.clearContents()
        pasteboard.writeObjects([writer])

        let readBack = pasteboard.string(forType: .feedivoFolderDragItem)
        #expect(readBack == "News")
    }

    @Test func tagPasteboardItemSchreibtUndLiestIDZurueck() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.clearContents() }

        let writer = SidebarTagPasteboardItem(tagID: "tag-456")
        pasteboard.clearContents()
        pasteboard.writeObjects([writer])

        let readBack = pasteboard.string(forType: .feedivoTagDragItem)
        #expect(readBack == "tag-456")
    }

    @Test func smartFolderPasteboardItemSchreibtUndLiestIDZurueck() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.clearContents() }

        let writer = SidebarSmartFolderPasteboardItem(smartFolderID: "sf-789")
        pasteboard.clearContents()
        pasteboard.writeObjects([writer])

        let readBack = pasteboard.string(forType: .feedivoSmartFolderDragItem)
        #expect(readBack == "sf-789")
    }
}
