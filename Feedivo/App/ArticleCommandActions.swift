import SwiftUI

struct ArticleCommandActions {
    let selectedArticle: Article?
    let toggleRead: () -> Void
    let toggleStarred: () -> Void

    var canPerformActions: Bool {
        selectedArticle != nil
    }

    var toggleReadTitle: String {
        guard let selectedArticle else {
            return L10n.articleRowMarkRead
        }

        return selectedArticle.isRead ? L10n.articleRowMarkUnread : L10n.articleRowMarkRead
    }

    var toggleStarredTitle: String {
        guard let selectedArticle else {
            return L10n.articleRowStarAdd
        }

        return selectedArticle.isStarred ? L10n.articleRowStarRemove : L10n.articleRowStarAdd
    }
}

private struct ArticleCommandActionsKey: FocusedValueKey {
    typealias Value = ArticleCommandActions
}

extension FocusedValues {
    var articleCommandActions: ArticleCommandActions? {
        get { self[ArticleCommandActionsKey.self] }
        set { self[ArticleCommandActionsKey.self] = newValue }
    }
}
