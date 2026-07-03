import Foundation

struct SQLiteArticleNavigationState: Equatable {
    static let empty = SQLiteArticleNavigationState()

    let previousArticleID: String?
    let nextArticleID: String?

    init(
        previousArticleID: String? = nil,
        nextArticleID: String? = nil
    ) {
        self.previousArticleID = previousArticleID
        self.nextArticleID = nextArticleID
    }

    init(articleIDs: [String], selectedArticleID: String?) {
        guard
            let selectedArticleID,
            let selectedIndex = articleIDs.firstIndex(of: selectedArticleID)
        else {
            self = .empty
            return
        }

        self.previousArticleID = selectedIndex > articleIDs.startIndex
            ? articleIDs[articleIDs.index(before: selectedIndex)]
            : nil
        self.nextArticleID = selectedIndex < articleIDs.index(before: articleIDs.endIndex)
            ? articleIDs[articleIDs.index(after: selectedIndex)]
            : nil
    }
}
