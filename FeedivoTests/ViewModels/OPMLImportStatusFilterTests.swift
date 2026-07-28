import Foundation
import Testing
@testable import Feedivo

struct OPMLImportStatusFilterTests {
    @Test func droppedFileAcceptsOPMLAndXMLOnly() {
        #expect(OPMLImportDroppedFile.isSupported(URL(fileURLWithPath: "/tmp/feeds.opml")))
        #expect(OPMLImportDroppedFile.isSupported(URL(fileURLWithPath: "/tmp/feeds.xml")))
        #expect(!OPMLImportDroppedFile.isSupported(URL(fileURLWithPath: "/tmp/feeds.txt")))
    }

    @Test func selectionOptionsErlaubenNichtErreichbareFeedsNurBewusst() {
        let standardOptions = OPMLImportSelectionOptions(
            allowsDuplicates: false,
            allowsUnreachable: false
        )
        let permissiveOptions = OPMLImportSelectionOptions(
            allowsDuplicates: true,
            allowsUnreachable: true
        )

        #expect(standardOptions.canImport(.available))
        #expect(!standardOptions.canImport(.duplicate))
        #expect(!standardOptions.canImport(.unreachable))
        #expect(permissiveOptions.canImport(.available))
        #expect(permissiveOptions.canImport(.duplicate))
        #expect(permissiveOptions.canImport(.unreachable))
    }

    @MainActor
    @Test func filteredRowsZeigtNurPassendeStatiUndBehältOriginalRowsUnverändert() {
        var rows = [
            OPMLImportPreviewRow(
                feed: OPMLFeed(title: "Neu", xmlURL: "https://example.com/new.xml", htmlURL: nil, folderName: "News"),
                status: .available,
                isSelected: true
            ),
            OPMLImportPreviewRow(
                feed: OPMLFeed(title: "Duplikat", xmlURL: "https://example.com/duplicate.xml", htmlURL: nil, folderName: "Alt"),
                status: .duplicate,
                isSelected: false
            ),
            OPMLImportPreviewRow(
                feed: OPMLFeed(title: "Kaputt", xmlURL: "https://example.com/broken.xml", htmlURL: nil, folderName: nil),
                status: .unreachable,
                isSelected: false
            )
        ]

        let duplicateRows = OPMLImportStatusFilter.duplicates.filteredRows(from: rows)
        rows[1].isSelected = true
        rows[1].feed = OPMLFeed(
            title: "Duplikat",
            xmlURL: "https://example.com/duplicate.xml",
            htmlURL: nil,
            folderName: "Importiert"
        )

        #expect(duplicateRows.map(\.status) == [.duplicate])
        #expect(OPMLImportStatusFilter.all.filteredRows(from: rows).count == 3)
        #expect(OPMLImportStatusFilter.duplicates.filteredRows(from: rows).first?.isSelected == true)
        #expect(OPMLImportStatusFilter.duplicates.filteredRows(from: rows).first?.feed.folderName == "Importiert")
    }
}
