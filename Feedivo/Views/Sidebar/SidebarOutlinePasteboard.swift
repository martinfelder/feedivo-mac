import AppKit
import UniformTypeIdentifiers

// UTType(exportedAs:) erzeugt zwar einen In-Prozess-UTType-Wert, aber macOS
// validiert beim tatsächlichen Drag-&-Drop-Betrieb trotzdem gegen die im
// Info.plist deklarierten UTExportedTypeDeclarations — auch bei rein
// appinterner Nutzung ohne Interoperabilität mit anderen Apps (bekannter
// Gotcha, siehe CLAUDE.md, gefunden 2026-07-14 bei den beiden Vorgänger-
// UTTypes .feedivoFeedDragItem/.feedivoFolderDragItem).
//
// .feedivoFeedDragItem und .feedivoFolderDragItem waren ursprünglich in
// SidebarDragAndDrop.swift deklariert (SwiftUI-natives Drag & Drop, seit
// Task 6 der NSOutlineView-Migration entfernt); beide Deklarationen wurden
// hierher übernommen, da diese Datei die einzige verbleibende Konsumentin
// ist (NSPasteboard.PasteboardType-Erweiterung unten). Alle vier
// UTExportedTypeDeclarations-Einträge existieren unverändert in
// Feedivo/Info.plist.
extension UTType {
    static let feedivoFeedDragItem = UTType(exportedAs: "ch.martin.Feedivo.feed-drag-item")
    static let feedivoFolderDragItem = UTType(exportedAs: "ch.martin.Feedivo.folder-drag-item")
    static let feedivoTagDragItem = UTType(exportedAs: "ch.martin.Feedivo.tag-drag-item")
    static let feedivoSmartFolderDragItem = UTType(exportedAs: "ch.martin.Feedivo.smart-folder-drag-item")
}

extension NSPasteboard.PasteboardType {
    static let feedivoFeedDragItem = NSPasteboard.PasteboardType(UTType.feedivoFeedDragItem.identifier)
    static let feedivoFolderDragItem = NSPasteboard.PasteboardType(UTType.feedivoFolderDragItem.identifier)
    static let feedivoTagDragItem = NSPasteboard.PasteboardType(UTType.feedivoTagDragItem.identifier)
    static let feedivoSmartFolderDragItem = NSPasteboard.PasteboardType(UTType.feedivoSmartFolderDragItem.identifier)
}

/// NSPasteboardWriting-Objekte für die vier ziehbaren Sidebar-Knotentypen.
/// Jeder Typ schreibt ausschließlich seine eigene ID (bzw. den Ordnernamen)
/// als reinen String unter seinem dedizierten internen UTType — kein
/// Cross-App-Interop nötig, siehe Design-Spec „Nicht-Ziele".
final class SidebarFeedPasteboardItem: NSObject, NSPasteboardWriting {
    let feedID: String

    init(feedID: String) {
        self.feedID = feedID
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.feedivoFeedDragItem]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .feedivoFeedDragItem ? feedID : nil
    }
}

final class SidebarFolderPasteboardItem: NSObject, NSPasteboardWriting {
    let folderName: String

    init(folderName: String) {
        self.folderName = folderName
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.feedivoFolderDragItem]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .feedivoFolderDragItem ? folderName : nil
    }
}

final class SidebarTagPasteboardItem: NSObject, NSPasteboardWriting {
    let tagID: String

    init(tagID: String) {
        self.tagID = tagID
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.feedivoTagDragItem]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .feedivoTagDragItem ? tagID : nil
    }
}

final class SidebarSmartFolderPasteboardItem: NSObject, NSPasteboardWriting {
    let smartFolderID: String

    init(smartFolderID: String) {
        self.smartFolderID = smartFolderID
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.feedivoSmartFolderDragItem]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .feedivoSmartFolderDragItem ? smartFolderID : nil
    }
}
