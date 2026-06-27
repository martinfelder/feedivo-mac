import Foundation
import SwiftData
import Testing
@testable import Feedivo

struct SmartFolderViewModelTests {
    @MainActor
    @Test func restoreDefaultFoldersLegtAlleVordefiniertenIntelligentenOrdnerAn() throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            RuleCondition.self,
            SmartFolder.self,
            SmartFolderCondition.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let viewModel = SmartFolderViewModel()

        viewModel.restoreDefaultFolders(existingFolders: [], context: context)

        let folders = try context.fetch(FetchDescriptor<SmartFolder>())
        #expect(SmartFolderViewModel.sortedFolders(folders).map(\.name) == [
            "Alle Artikel",
            "Ungelesen",
            "Mit Stern",
            "Heute",
            "Ausgeblendet",
            "Archiviert",
            "Diese Woche",
            "Gespeichert"
        ])
        #expect(folders.allSatisfy { folder in folder.isShownInSidebar })
        #expect(folders.allSatisfy { folder in folder.isDefault })

        let allArticlesFolder = try #require(folders.first { $0.name == "Alle Artikel" })
        #expect(allArticlesFolder.conditions.isEmpty)
        #expect(allArticlesFolder.iconName == "tray.full")
        #expect(allArticlesFolder.colorHex == "#3B82F6")

        let starredFolder = try #require(folders.first { $0.name == "Mit Stern" })
        #expect(starredFolder.conditions.first?.value == SmartFolderStatusValue.starred.rawValue)
        #expect(starredFolder.iconName == "star.fill")
        #expect(starredFolder.colorHex == "#F59E0B")
    }

    @MainActor
    @Test func duplicateFolderFuegtKopieDirektNachOriginalEin() throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            RuleCondition.self,
            SmartFolder.self,
            SmartFolderCondition.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let firstFolder = SmartFolder(
            name: "Swift",
            matchMode: .all,
            iconName: "tag",
            colorHex: "#F97316",
            conditions: [
                SmartFolderCondition(field: .title, conditionOperator: .contains, value: "Swift")
            ]
        )
        firstFolder.sortOrder = 0
        let secondFolder = SmartFolder(
            name: "Apple",
            matchMode: .all,
            conditions: [
                SmartFolderCondition(field: .title, conditionOperator: .contains, value: "Apple")
            ]
        )
        secondFolder.sortOrder = 1
        context.insert(firstFolder)
        context.insert(secondFolder)
        let viewModel = SmartFolderViewModel()

        viewModel.duplicateFolder(firstFolder, existingFolders: [firstFolder, secondFolder], context: context)

        let folders = try context.fetch(FetchDescriptor<SmartFolder>())
        #expect(SmartFolderViewModel.sortedFolders(folders).map(\.name) == ["Swift", "Swift Kopie", "Apple"])
        let duplicate = try #require(folders.first { $0.name == "Swift Kopie" })
        #expect(duplicate.sortOrder == 1)
        #expect(duplicate.conditions.count == 1)
        #expect(duplicate.isDefault == false)
        #expect(duplicate.iconName == "tag")
        #expect(duplicate.colorHex == "#F97316")
    }

    @MainActor
    @Test func moveFolderVorZielAktualisiertSortierreihenfolgeFuerDragAndDrop() {
        let firstFolder = SmartFolder(name: "A")
        firstFolder.sortOrder = 0
        let secondFolder = SmartFolder(name: "B")
        secondFolder.sortOrder = 1
        let thirdFolder = SmartFolder(name: "C")
        thirdFolder.sortOrder = 2
        let viewModel = SmartFolderViewModel()

        viewModel.moveFolder(secondFolder, before: firstFolder, existingFolders: [firstFolder, secondFolder, thirdFolder], context: nil)

        #expect(SmartFolderViewModel.sortedFolders([firstFolder, secondFolder, thirdFolder]).map(\.name) == ["B", "A", "C"])
    }

    @MainActor
    @Test func moveFolderAnListenendeAktualisiertSortierreihenfolgeFuerDragAndDrop() {
        let firstFolder = SmartFolder(name: "A")
        firstFolder.sortOrder = 0
        let secondFolder = SmartFolder(name: "B")
        secondFolder.sortOrder = 1
        let thirdFolder = SmartFolder(name: "C")
        thirdFolder.sortOrder = 2
        let viewModel = SmartFolderViewModel()

        viewModel.moveFolderToEnd(firstFolder, existingFolders: [firstFolder, secondFolder, thirdFolder], context: nil)

        #expect(SmartFolderViewModel.sortedFolders([firstFolder, secondFolder, thirdFolder]).map(\.name) == ["B", "C", "A"])
    }

    @MainActor
    @Test func moveFolderToPositionOfTargetVerschiebtZeileBeimDragNachUnten() {
        let firstFolder = SmartFolder(name: "A")
        firstFolder.sortOrder = 0
        let secondFolder = SmartFolder(name: "B")
        secondFolder.sortOrder = 1
        let thirdFolder = SmartFolder(name: "C")
        thirdFolder.sortOrder = 2
        let viewModel = SmartFolderViewModel()

        viewModel.moveFolder(firstFolder, toPositionOf: thirdFolder, existingFolders: [firstFolder, secondFolder, thirdFolder], context: nil)

        #expect(SmartFolderViewModel.sortedFolders([firstFolder, secondFolder, thirdFolder]).map(\.name) == ["B", "C", "A"])
    }

    @MainActor
    @Test func moveFolderToPositionOfTargetVerschiebtZeileBeimDragNachOben() {
        let firstFolder = SmartFolder(name: "A")
        firstFolder.sortOrder = 0
        let secondFolder = SmartFolder(name: "B")
        secondFolder.sortOrder = 1
        let thirdFolder = SmartFolder(name: "C")
        thirdFolder.sortOrder = 2
        let viewModel = SmartFolderViewModel()

        viewModel.moveFolder(thirdFolder, toPositionOf: firstFolder, existingFolders: [firstFolder, secondFolder, thirdFolder], context: nil)

        #expect(SmartFolderViewModel.sortedFolders([firstFolder, secondFolder, thirdFolder]).map(\.name) == ["C", "A", "B"])
    }

    @MainActor
    @Test func createFolderSpeichertIconUndFarbe() throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            RuleCondition.self,
            SmartFolder.self,
            SmartFolderCondition.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let viewModel = SmartFolderViewModel()

        viewModel.createFolder(
            name: "Swift",
            matchMode: .all,
            isShownInSidebar: true,
            iconName: "tag",
            colorHex: "#F97316",
            conditionDrafts: [],
            existingFolders: [],
            context: context
        )

        let folder = try #require(try context.fetch(FetchDescriptor<SmartFolder>()).first)
        #expect(folder.iconName == "tag")
        #expect(folder.colorHex == "#F97316")
    }

    @MainActor
    @Test func deleteFolderEntferntZugehoerigeConditions() throws {
        let container = try ModelContainer(
            for: Feed.self,
            Article.self,
            Tag.self,
            Rule.self,
            RuleCondition.self,
            SmartFolder.self,
            SmartFolderCondition.self,
            FeedLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let folder = SmartFolder(name: "Smart", matchMode: .all, conditions: [
            SmartFolderCondition(
                field: .title,
                conditionOperator: .contains,
                value: "Swift",
                sortOrder: 0
            ),
            SmartFolderCondition(
                field: .text,
                conditionOperator: .contains,
                value: "Mac",
                sortOrder: 1
            )
        ])
        context.insert(folder)
        try context.save()
        let viewModel = SmartFolderViewModel()

        viewModel.deleteFolder(folder, context: context)

        let folders = try context.fetch(FetchDescriptor<SmartFolder>())
        #expect(folders.isEmpty)
        // .nullify statt .cascade — manuelles Cascade muss die Conditions löschen.
        let conditions = try context.fetch(FetchDescriptor<SmartFolderCondition>())
        #expect(conditions.isEmpty, "Conditions müssen mit dem Ordner gelöscht werden")
    }
}
