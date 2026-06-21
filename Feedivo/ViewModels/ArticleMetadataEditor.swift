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
        guard let normalizedName = normalizedTagName(name),
              !article.tags.contains(where: { sameTagName($0.name, normalizedName) })
        else {
            return
        }

        let tag = availableTags.first { sameTagName($0.name, normalizedName) } ?? Tag(name: normalizedName)
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
    static func setFolderName(_ folderName: String?, for article: Article, context: ModelContext) {
        article.feed?.folderName = FeedFolderOrganizer.normalizedFolderName(folderName)
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
