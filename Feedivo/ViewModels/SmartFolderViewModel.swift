import Foundation
import Observation
import SwiftData

enum SmartFolderMoveDirection {
    case up
    case down
}

struct SmartFolderConditionDraft: Identifiable, Equatable {
    var id = UUID()
    var field: SmartFolderConditionField
    var conditionOperator: SmartFolderConditionOperator
    var value: String
}

@Observable
@MainActor
final class SmartFolderViewModel {
    var errorMessage: String?

    static func sortedFolders(_ folders: [SmartFolder]) -> [SmartFolder] {
        folders.sorted { firstFolder, secondFolder in
            if firstFolder.sortOrder == secondFolder.sortOrder {
                return firstFolder.name.localizedCaseInsensitiveCompare(secondFolder.name) == .orderedAscending
            }

            return firstFolder.sortOrder < secondFolder.sortOrder
        }
    }

    func restoreDefaultFolders(existingFolders: [SmartFolder], context: ModelContext) {
        let existingNames = Set(existingFolders.map(\.name))
        var folders = Self.sortedFolders(existingFolders)
        // `defaultFolders` erzeugt 8 @Model-Instanzen pro Zugriff — einmal
        // erfassen und an `foldersSortedWithDefaultsFirst` weiterreichen statt
        // es dort erneut zu konstruieren.
        let defaults = Self.defaultFolders

        for defaultFolder in defaults where !existingNames.contains(defaultFolder.name) {
            defaultFolder.sortOrder = folders.count
            context.insert(defaultFolder)
            folders.append(defaultFolder)
        }

        normalizeSortOrder(in: foldersSortedWithDefaultsFirst(folders, defaults: defaults))
        save(context)
    }

    func createFolder(
        name: String,
        matchMode: RuleMatchMode,
        isShownInSidebar: Bool,
        iconName: String,
        colorHex: String,
        conditionDrafts: [SmartFolderConditionDraft],
        existingFolders: [SmartFolder],
        context: ModelContext
    ) {
        guard let normalizedName = normalizedName(name),
              let conditions = normalizedConditions(from: conditionDrafts)
        else {
            errorMessage = L10n.smartFolderErrorNameRequired
            return
        }

        let folder = SmartFolder(
            name: normalizedName,
            matchMode: matchMode,
            isShownInSidebar: isShownInSidebar,
            sortOrder: nextSortOrder(after: existingFolders),
            iconName: SmartFolderAppearance.normalizedIconName(iconName),
            colorHex: SmartFolderAppearance.normalizedColorHex(colorHex),
            conditions: conditions
        )
        context.insert(folder)
        save(context)
    }

    func updateFolder(
        _ folder: SmartFolder,
        name: String,
        matchMode: RuleMatchMode,
        isShownInSidebar: Bool,
        iconName: String,
        colorHex: String,
        conditionDrafts: [SmartFolderConditionDraft],
        context: ModelContext
    ) {
        guard let normalizedName = normalizedName(name),
              let conditions = normalizedConditions(from: conditionDrafts)
        else {
            errorMessage = L10n.smartFolderErrorNameRequired
            return
        }

        folder.name = normalizedName
        folder.matchModeRaw = matchMode.rawValue
        folder.isShownInSidebar = isShownInSidebar
        folder.iconName = SmartFolderAppearance.normalizedIconName(iconName)
        folder.colorHex = SmartFolderAppearance.normalizedColorHex(colorHex)
        // .nullify statt .cascade (CloudKit-kompatibel): removeAll würde die
        // alten Conditions nur verwaisten lassen — deshalb manuell löschen,
        // analog deleteFolder.
        for condition in Array(folder.conditions) {
            context.delete(condition)
        }
        folder.conditions = conditions
        save(context)
    }

    func duplicateFolder(_ folder: SmartFolder, existingFolders: [SmartFolder], context: ModelContext) {
        let duplicate = SmartFolder(
            name: "\(folder.name) Kopie",
            matchMode: RuleMatchMode.normalized(folder.matchModeRaw),
            isShownInSidebar: folder.isShownInSidebar,
            isDefault: false,
            iconName: folder.iconName,
            colorHex: folder.colorHex,
            conditions: sortedConditions(for: folder).enumerated().map { index, condition in
                SmartFolderCondition(
                    field: condition.fieldEnum ?? .title,
                    conditionOperator: condition.operatorEnum ?? .contains,
                    value: condition.value,
                    sortOrder: index
                )
            }
        )

        context.insert(duplicate)

        let orderedFolders = Self.sortedFolders(existingFolders)
        let originalIndex = orderedFolders.firstIndex { $0.id == folder.id } ?? orderedFolders.endIndex
        var reorderedFolders = orderedFolders
        reorderedFolders.insert(duplicate, at: min(originalIndex + 1, reorderedFolders.count))
        normalizeSortOrder(in: reorderedFolders)
        save(context)
    }

    func moveFolder(
        _ folder: SmartFolder,
        direction: SmartFolderMoveDirection,
        existingFolders: [SmartFolder],
        context: ModelContext?
    ) {
        var orderedFolders = Self.sortedFolders(existingFolders)
        guard let currentIndex = orderedFolders.firstIndex(where: { $0.id == folder.id }) else {
            return
        }

        let destinationIndex: Int
        switch direction {
        case .up:
            destinationIndex = max(0, currentIndex - 1)
        case .down:
            destinationIndex = min(orderedFolders.count - 1, currentIndex + 1)
        }

        guard currentIndex != destinationIndex else {
            return
        }

        orderedFolders.swapAt(currentIndex, destinationIndex)
        normalizeSortOrder(in: orderedFolders)

        if let context {
            save(context)
        } else {
            errorMessage = nil
        }
    }

    func moveFolder(
        _ folder: SmartFolder,
        before targetFolder: SmartFolder,
        existingFolders: [SmartFolder],
        context: ModelContext?
    ) {
        var orderedFolders = Self.sortedFolders(existingFolders)
        guard let sourceIndex = orderedFolders.firstIndex(where: { $0.id == folder.id }),
              let targetIndex = orderedFolders.firstIndex(where: { $0.id == targetFolder.id }),
              sourceIndex != targetIndex
        else {
            return
        }

        let movedFolder = orderedFolders.remove(at: sourceIndex)
        let adjustedTargetIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        orderedFolders.insert(movedFolder, at: adjustedTargetIndex)
        normalizeSortOrder(in: orderedFolders)

        if let context {
            save(context)
        } else {
            errorMessage = nil
        }
    }

    func moveFolder(
        _ folder: SmartFolder,
        toPositionOf targetFolder: SmartFolder,
        existingFolders: [SmartFolder],
        context: ModelContext?
    ) {
        var orderedFolders = Self.sortedFolders(existingFolders)
        guard let sourceIndex = orderedFolders.firstIndex(where: { $0.id == folder.id }),
              let targetIndex = orderedFolders.firstIndex(where: { $0.id == targetFolder.id }),
              sourceIndex != targetIndex
        else {
            return
        }

        // Drag-Reorder: nach unten gezogen (source < target) → hinter dem Ziel
        // einfügen; nach oben gezogen (source > target) → vor dem Ziel. Beide
        // Fälle landen nach dem remove() auf demselben Index, weil das Ziel bei
        // Aufwärts-Bewegung bereits um eins nach vorne gerutscht ist. Der
        // frühere Ternary `source < target ? targetIndex : targetIndex` war ein
        // toter Zweig (beide Äste identisch) — Verhalten bleibt gleich, Code
        // wird klarer. (Siehe moveFolderToPositionOfTargetVerschiebtZeileBeimDragNachUnten.)
        let movedFolder = orderedFolders.remove(at: sourceIndex)
        orderedFolders.insert(movedFolder, at: targetIndex)
        normalizeSortOrder(in: orderedFolders)

        if let context {
            save(context)
        } else {
            errorMessage = nil
        }
    }

    func moveFolderToEnd(
        _ folder: SmartFolder,
        existingFolders: [SmartFolder],
        context: ModelContext?
    ) {
        var orderedFolders = Self.sortedFolders(existingFolders)
        guard let sourceIndex = orderedFolders.firstIndex(where: { $0.id == folder.id }),
              sourceIndex != orderedFolders.count - 1
        else {
            return
        }

        let movedFolder = orderedFolders.remove(at: sourceIndex)
        orderedFolders.append(movedFolder)
        normalizeSortOrder(in: orderedFolders)

        if let context {
            save(context)
        } else {
            errorMessage = nil
        }
    }

    func deleteFolder(_ folder: SmartFolder, context: ModelContext) {
        // .nullify statt .cascade (CloudKit-kompatibel): SwiftData würde die
        // Conditions nur verwaisten lassen — deshalb hier manuell löschen.
        for condition in Array(folder.conditions) {
            context.delete(condition)
        }
        context.delete(folder)
        save(context)
    }

    private static var defaultFolders: [SmartFolder] {
        [
            SmartFolder(
                name: "Alle Artikel",
                matchMode: .all,
                isDefault: true,
                iconName: "tray.full",
                colorHex: "#3B82F6",
                conditions: []
            ),
            SmartFolder(
                name: "Ungelesen",
                matchMode: .all,
                isDefault: true,
                iconName: "circle.fill",
                colorHex: "#14B8A6",
                conditions: [
                    SmartFolderCondition(field: .status, conditionOperator: .is, value: SmartFolderStatusValue.unread.rawValue)
                ]
            ),
            SmartFolder(
                name: "Mit Stern",
                matchMode: .all,
                isDefault: true,
                iconName: "star.fill",
                colorHex: "#F59E0B",
                conditions: [
                    SmartFolderCondition(field: .status, conditionOperator: .is, value: SmartFolderStatusValue.starred.rawValue)
                ]
            ),
            SmartFolder(
                name: "Heute",
                matchMode: .all,
                isDefault: true,
                iconName: "calendar",
                colorHex: "#22C55E",
                conditions: [
                    SmartFolderCondition(field: .date, conditionOperator: .is, value: SmartFolderDateValue.today.rawValue)
                ]
            ),
            SmartFolder(
                name: "Ausgeblendet",
                matchMode: .all,
                isDefault: true,
                iconName: "eye.slash",
                colorHex: "#6B7280",
                conditions: [
                    SmartFolderCondition(field: .status, conditionOperator: .is, value: SmartFolderStatusValue.hidden.rawValue)
                ]
            ),
            SmartFolder(
                name: "Archiviert",
                matchMode: .all,
                isDefault: true,
                iconName: "archivebox",
                colorHex: "#8B5CF6",
                conditions: [
                    SmartFolderCondition(field: .status, conditionOperator: .is, value: SmartFolderStatusValue.archived.rawValue)
                ]
            ),
            SmartFolder(
                name: "Diese Woche",
                matchMode: .all,
                isDefault: true,
                iconName: "calendar",
                colorHex: "#22C55E",
                conditions: [
                    SmartFolderCondition(field: .date, conditionOperator: .is, value: SmartFolderDateValue.thisWeek.rawValue)
                ]
            ),
            SmartFolder(
                name: "Gespeichert",
                matchMode: .any,
                isDefault: true,
                iconName: "bookmark",
                colorHex: "#F97316",
                conditions: [
                    SmartFolderCondition(field: .status, conditionOperator: .is, value: SmartFolderStatusValue.starred.rawValue),
                    SmartFolderCondition(field: .status, conditionOperator: .is, value: SmartFolderStatusValue.archived.rawValue)
                ]
            )
        ]
    }

    private func foldersSortedWithDefaultsFirst(
        _ folders: [SmartFolder],
        defaults: [SmartFolder]
    ) -> [SmartFolder] {
        let defaultOrder = Dictionary(
            uniqueKeysWithValues: defaults.enumerated().map { index, folder in
                (folder.name, index)
            }
        )
        let defaultFolders = folders
            .filter { defaultOrder[$0.name] != nil }
            .sorted { firstFolder, secondFolder in
                (defaultOrder[firstFolder.name] ?? Int.max) < (defaultOrder[secondFolder.name] ?? Int.max)
            }
        let customFolders = Self.sortedFolders(folders.filter { defaultOrder[$0.name] == nil })

        return defaultFolders + customFolders
    }

    private func normalizeSortOrder(in folders: [SmartFolder]) {
        for (index, folder) in folders.enumerated() {
            folder.sortOrder = index
        }
    }

    private func nextSortOrder(after folders: [SmartFolder]) -> Int {
        (folders.map(\.sortOrder).max() ?? -1) + 1
    }

    private func normalizedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedConditions(from drafts: [SmartFolderConditionDraft]) -> [SmartFolderCondition]? {
        let conditions = drafts.enumerated().compactMap { index, draft -> SmartFolderCondition? in
            let value = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                return nil
            }

            return SmartFolderCondition(
                field: draft.field,
                conditionOperator: draft.conditionOperator,
                value: value,
                sortOrder: index
            )
        }

        return conditions
    }

    private func sortedConditions(for folder: SmartFolder) -> [SmartFolderCondition] {
        folder.conditions.sorted { firstCondition, secondCondition in
            firstCondition.sortOrder < secondCondition.sortOrder
        }
    }

    private func save(_ context: ModelContext) {
        do {
            try context.save()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
