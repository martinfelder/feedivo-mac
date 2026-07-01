import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class TagViewModel {
    var errorMessage: String?

    @discardableResult
    func createTag(
        name: String,
        colorHex: String,
        availableTags: [Tag],
        context: ModelContext
    ) -> Tag? {
        guard let normalizedName = Self.normalizedTagName(name) else {
            errorMessage = L10n.tagManagerEmptyNameError
            return nil
        }

        guard !Self.containsTag(named: normalizedName, in: availableTags) else {
            errorMessage = L10n.tagManagerDuplicateNameError
            return nil
        }

        let tag = Tag(
            name: normalizedName,
            colorHex: Self.normalizedColorHex(colorHex)
        )
        context.insert(tag)
        save(context)

        // Rollback: wenn das Speichern scheitert, bleibt der Tag sonst als
        // ungespeichertes, aber insertetes Objekt im Context hängen und taucht
        // in @Query-Beobachtungen auf. Deshalb wieder entfernen.
        guard errorMessage == nil else {
            context.delete(tag)
            return nil
        }

        return tag
    }

    func renameTag(
        _ tag: Tag,
        name: String,
        availableTags: [Tag],
        context: ModelContext
    ) {
        guard let normalizedName = Self.normalizedTagName(name) else {
            errorMessage = L10n.tagManagerEmptyNameError
            return
        }

        guard !Self.containsTag(named: normalizedName, in: availableTags, excluding: tag) else {
            errorMessage = L10n.tagManagerDuplicateNameError
            return
        }

        guard tag.name != normalizedName else {
            errorMessage = nil
            return
        }

        tag.name = normalizedName
        save(context)
    }

    func updateColor(_ tag: Tag, colorHex: String, context: ModelContext) {
        tag.colorHex = Self.normalizedColorHex(colorHex)
        save(context)
    }

    func deleteTag(_ tag: Tag, context: ModelContext) {
        tag.articles = []
        tag.feeds = []
        context.delete(tag)
        save(context)
    }

    static func normalizedTagName(_ name: String?) -> String? {
        guard let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedName.isEmpty
        else {
            return nil
        }

        return trimmedName
    }

    static func normalizedColorHex(_ colorHex: String) -> String {
        let trimmed = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutHash = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard withoutHash.count == 6,
              Int(withoutHash, radix: 16) != nil
        else {
            return "#888888"
        }

        return "#\(withoutHash.uppercased())"
    }

    private static func containsTag(named name: String, in tags: [Tag], excluding excludedTag: Tag? = nil) -> Bool {
        tags.contains { tag in
            if let excludedTag, tag.persistentModelID == excludedTag.persistentModelID {
                return false
            }

            return tag.name.caseInsensitiveCompare(name) == .orderedSame
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
