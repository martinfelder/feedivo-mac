import Foundation
import SwiftData
import Testing
@testable import Feedivo

@MainActor
struct OPMLImportPreviewControllerTests {
    private func makeRow(
        title: String,
        xmlURL: String,
        status: OPMLImportFeedStatus,
        folderName: String? = nil,
        isSelected: Bool = false
    ) -> OPMLImportPreviewRow {
        OPMLImportPreviewRow(
            feed: OPMLFeed(title: title, xmlURL: xmlURL, htmlURL: nil, folderName: folderName),
            status: status,
            isSelected: isSelected
        )
    }

    @Test func selectAllImportableRowsMarkiertNurSichtbareImportierbareFeeds() {
        let controller = OPMLImportPreviewController()
        controller.rows = [
            makeRow(title: "A", xmlURL: "https://a.example.com/feed.xml", status: .available, isSelected: false),
            makeRow(title: "D", xmlURL: "https://d.example.com/feed.xml", status: .duplicate, isSelected: false),
            makeRow(title: "U", xmlURL: "https://u.example.com/feed.xml", status: .unreachable, isSelected: false)
        ]
        controller.statusFilter = .available
        controller.allowsDuplicates = false
        controller.allowsUnreachable = false

        controller.selectAllImportableRows()

        #expect(controller.rows[0].isSelected == true)
        #expect(controller.rows[1].isSelected == false)
        #expect(controller.rows[2].isSelected == false)
    }

    @Test func selectAllImportableRowsErlaubtDuplikateBeiOffenemFilter() {
        let controller = OPMLImportPreviewController()
        controller.rows = [
            makeRow(title: "D", xmlURL: "https://d.example.com/feed.xml", status: .duplicate, isSelected: false)
        ]
        controller.statusFilter = .all
        controller.allowsDuplicates = true

        controller.selectAllImportableRows()

        #expect(controller.rows[0].isSelected == true)
    }

    @Test func deselectVisibleRowsSetztNurSichtbareAufFalse() {
        let controller = OPMLImportPreviewController()
        controller.rows = [
            makeRow(title: "A", xmlURL: "https://a.example.com/feed.xml", status: .available, isSelected: true),
            makeRow(title: "D", xmlURL: "https://d.example.com/feed.xml", status: .duplicate, isSelected: true)
        ]
        controller.statusFilter = .available

        controller.deselectVisibleRows()

        #expect(controller.rows[0].isSelected == false)
        #expect(controller.rows[1].isSelected == true)
    }

    @Test func createFolderFuegtGetrimmtenOrdnerHinzuUndLeertFeld() {
        let controller = OPMLImportPreviewController()
        controller.newFolderName = " News "

        controller.createFolder()

        #expect(controller.customFolders == ["News"])
        #expect(controller.newFolderName == "")
    }

    @Test func createFolderDedupeltCaseInsensitive() {
        let controller = OPMLImportPreviewController()
        controller.customFolders = ["News"]
        controller.newFolderName = "news"

        controller.createFolder()

        #expect(controller.customFolders == ["News"])
    }

    @Test func createFolderIgnoriertLeerenNamen() {
        let controller = OPMLImportPreviewController()
        controller.newFolderName = "   "

        controller.createFolder()

        #expect(controller.customFolders == [])
        #expect(controller.newFolderName == "   ")
    }

    @Test func availableFoldersFasstExistingPreviewUndCustomZusammenUndSortiert() {
        let controller = OPMLImportPreviewController()
        controller.customFolders = ["Zeta"]
        controller.rows = [
            makeRow(title: "A", xmlURL: "https://a.example.com/feed.xml", status: .available, folderName: "Alpha"),
            makeRow(title: "A2", xmlURL: "https://a2.example.com/feed.xml", status: .available, folderName: "Alpha")
        ]
        let existing = ["Beta"]

        let folders = controller.availableFolders(existingFolderNames: existing)

        #expect(folders == ["Alpha", "Beta", "Zeta"])
    }

    @Test func duplicateUnreachableUndFolderCountZaehlenKorrekt() {
        let controller = OPMLImportPreviewController()
        controller.allowsDuplicates = true
        controller.rows = [
            makeRow(title: "A", xmlURL: "https://a.example.com/feed.xml", status: .available, folderName: "News", isSelected: true),
            makeRow(title: "D", xmlURL: "https://d.example.com/feed.xml", status: .duplicate, folderName: "News", isSelected: true),
            makeRow(title: "U", xmlURL: "https://u.example.com/feed.xml", status: .unreachable, isSelected: false)
        ]

        #expect(controller.duplicateCount == 1)
        #expect(controller.unreachableCount == 1)
        #expect(controller.selectedImportRows.count == 2)
        // `folderCount` nutzt den Sentinel „Ohne Ordner" bewusst NICHT lokalisiert —
        // er ist interner Daten-Schlüssel (Spec Observation 1060), keine Anzeige-
        // Zeichenkette. Der lokalisierte Anzeige-String für „ohne Ordner" liegt
        // separat in `Localizable.xcstrings` und wird in der View-Schicht verwendet.
        #expect(controller.folderCount == 1)
    }

    @Test func resetStelltInitialStringsWiederHerUndLeertRows() {
        let controller = OPMLImportPreviewController(configuration: .firstRun)
        let initialSource = controller.sourceDescription
        let initialProgress = controller.previewProgressText
        controller.rows = [makeRow(title: "A", xmlURL: "https://a.example.com/feed.xml", status: .available, isSelected: true)]
        controller.allowsDuplicates = true
        controller.statusFilter = .duplicates
        controller.sourceDescription = "Zwischenstand"
        controller.previewProgressText = "Zwischenstand"
        controller.errorMessage = "irgendwas"

        controller.reset()

        #expect(controller.rows == [])
        #expect(controller.allowsDuplicates == false)
        #expect(controller.allowsUnreachable == false)
        #expect(controller.statusFilter == .all)
        #expect(controller.sourceDescription == initialSource)
        #expect(controller.previewProgressText == initialProgress)
        #expect(controller.errorMessage == nil)
    }

    @Test func resetBrichtLaufendenPreviewAbUndSetztStateZurueck() async {
        let controller = OPMLImportPreviewController()
        controller.isPreparingPreview = true
        controller.rows = [makeRow(title: "A", xmlURL: "https://a.example.com/feed.xml", status: .available, isSelected: true)]
        controller.sourceDescription = "Zwischenstand"
        controller.previewProgressText = "Zwischenstand"

        controller.reset()

        #expect(controller.isPreparingPreview == false)
        #expect(controller.rows == [])
        // Task-Handle ist nach reset wieder nil (kein aktiver Preview).
        #expect(controller.previewTask == nil)
    }

    @Test func applyToggleSelectionToRowsSetztDuplikateBeiOffenemFilter() {
        let controller = OPMLImportPreviewController()
        controller.rows = [
            makeRow(title: "A", xmlURL: "https://a.example.com/feed.xml", status: .duplicate, isSelected: false),
            makeRow(title: "U", xmlURL: "https://u.example.com/feed.xml", status: .unreachable, isSelected: true)
        ]
        controller.allowsDuplicates = true
        controller.allowsUnreachable = false

        controller.applyToggleSelectionToRows()

        #expect(controller.rows[0].isSelected == true)   // Duplikat → selected
        #expect(controller.rows[1].isSelected == false)  // Unreachable → abgewählt
    }

    @Test func resetSetztSelectedFileNameAufInitialwertZurueck() {
        let controller = OPMLImportPreviewController(configuration: .importSheet)
        controller.selectedFileName = "alt.opml"

        controller.reset()

        #expect(controller.selectedFileName == "Keine OPML-Datei ausgewählt")
    }

    @Test func opmlPreviewMarkiertSQLiteFeedAlsDuplikat() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        try FeedStore(database: database).save(
            FeedRecord(url: "https://example.com/existing.xml", title: "Schon da")
        )
        let viewModel = FeedViewModel(
            fetchFeed: { urlString in
                ParsedFeed(sourceURL: urlString, title: "Preview", description: nil, siteURL: nil, articles: [])
            },
            discoverFaviconURL: { _ in nil },
            enrichArticleImages: { articles in articles }
        )

        let rows = await viewModel.opmlImportPreviewRows(
            for: [
                OPMLFeed(
                    title: "Schon da",
                    xmlURL: "https://example.com/existing.xml",
                    htmlURL: nil,
                    folderName: nil
                )
            ],
            sqliteDatabase: database
        )

        #expect(rows.map(\.status) == [.duplicate])
    }
}
