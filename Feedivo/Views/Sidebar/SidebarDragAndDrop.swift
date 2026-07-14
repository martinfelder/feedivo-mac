import SwiftUI
import UniformTypeIdentifiers

// Reine In-Prozess-Nutzung (Drag & Drop nur innerhalb desselben Fensters,
// keine Interoperabilität mit anderen Apps/Finder/Spotlight nötig) — deshalb
// genügt UTType(exportedAs:) rein im Code, ganz ohne Info.plist-Eintrag unter
// UTExportedTypeDeclarations.
extension UTType {
    static let feedivoFeedDragItem = UTType(exportedAs: "ch.martin.Feedivo.feed-drag-item")
    static let feedivoFolderDragItem = UTType(exportedAs: "ch.martin.Feedivo.folder-drag-item")
}

/// Transferable-Payload für einen per Drag & Drop gezogenen Feed (Feed-ID).
struct FeedDragItem: Codable, Transferable {
    let feedID: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .feedivoFeedDragItem)
    }
}

/// Transferable-Payload für einen per Drag & Drop gezogenen Ordner (Ordnername).
struct FolderDragItem: Codable, Transferable {
    let folderName: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .feedivoFolderDragItem)
    }
}

/// Bestimmt anhand der Y-Position eines Drops innerhalb der Höhe einer
/// Zielzeile, ob "davor" oder "danach" eingefügt werden soll — gemeinsame
/// Logik für Feed- und Ordner-Reordering in SidebarView.swift.
enum DropInsertionSide: Equatable {
    case before
    case after

    static func of(location: CGPoint, in size: CGSize) -> DropInsertionSide {
        location.y < size.height / 2 ? .before : .after
    }
}
