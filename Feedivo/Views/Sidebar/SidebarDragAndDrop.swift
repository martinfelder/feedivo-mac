import SwiftUI
import UniformTypeIdentifiers

// UTType(exportedAs:) erzeugt zwar einen In-Prozess-UTType-Wert, aber macOS
// validiert beim tatsächlichen Drag-&-Drop-Betrieb trotzdem gegen die im
// Info.plist deklarierten UTExportedTypeDeclarations — auch bei rein
// appinterner Nutzung ohne Interoperabilität mit anderen Apps. Ohne passenden
// Eintrag dort meldet das System zur Laufzeit "Type ... was expected to be
// declared and exported in the Info.plist ... but it was not found."
// (gefunden per Nutzer-Report 2026-07-14, ursprüngliche Plan-Annahme "kein
// Info.plist-Eintrag nötig" war falsch). Beide Typen sind seither in
// Feedivo/Info.plist unter UTExportedTypeDeclarations deklariert.
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
