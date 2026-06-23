import Foundation
import SwiftData

enum ArticleMetadataEditor {

    @MainActor
    static func addTag(
        named name: String,
        to article: Article,
        availableTags: [Tag],
        context: ModelContext
    ) {
        addTag(
            named: name,
            colorHex: TagColorPalette.defaultColorHex,
            to: article,
            availableTags: availableTags,
            context: context
        )
    }

    @MainActor
    static func addTag(
        named name: String,
        colorHex: String,
        to article: Article,
        availableTags: [Tag],
        context: ModelContext
    ) {
        guard let normalizedName = normalizedTagName(name),
              !article.tags.contains(where: { sameTagName($0.name, normalizedName) })
        else {
            return
        }

        let tag = availableTags.first { sameTagName($0.name, normalizedName) } ?? Tag(
            name: normalizedName,
            colorHex: colorHex
        )
        if tag.modelContext == nil {
            context.insert(tag)
        }

        article.tags.append(tag)
        try? context.save()
    }

    @MainActor
    static func removeTag(_ tag: Tag, from article: Article, context: ModelContext) {
        article.tags.removeAll { $0.id == tag.id }
        try? context.save()
    }

    @MainActor
    static func availableTagsToAdd(to article: Article, availableTags: [Tag]) -> [Tag] {
        availableTags
            .filter { tag in
                !article.tags.contains { articleTag in
                    sameTagName(articleTag.name, tag.name)
                }
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    @MainActor
    static func setFolderName(_ folderName: String?, for article: Article, context: ModelContext) {
        article.feed?.folderName = FeedFolderOrganizer.normalizedFolderName(folderName)
        try? context.save()
    }

    @MainActor
    static func createFolderAndAssign(
        named name: String,
        to article: Article,
        existingFolders: [FeedFolder],
        context: ModelContext
    ) {
        guard let normalizedName = FeedFolderOrganizer.normalizedFolderName(name) else {
            return
        }

        if !existingFolders.contains(where: { $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame }) {
            context.insert(FeedFolder(name: normalizedName))
        }

        article.feed?.folderName = normalizedName
        try? context.save()
    }

    static func normalizedTagName(_ name: String?) -> String? {
        guard let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedName.isEmpty
        else {
            return nil
        }

        return trimmedName
    }

    private static func sameTagName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }
}
