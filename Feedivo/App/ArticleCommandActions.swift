import SwiftUI

struct ArticleCommandActions {
    let selectedArticle: Article?
    let toggleRead: () -> Void
    let toggleStarred: () -> Void
    let copyLink: () -> Void
    let openOriginal: () -> Void
    let canSelectPreviousArticle: Bool
    let canSelectNextArticle: Bool
    let selectPreviousArticle: () -> Void
    let selectNextArticle: () -> Void

    init(
        selectedArticle: Article?,
        toggleRead: @escaping () -> Void,
        toggleStarred: @escaping () -> Void,
        copyLink: @escaping () -> Void,
        openOriginal: @escaping () -> Void,
        canSelectPreviousArticle: Bool = false,
        canSelectNextArticle: Bool = false,
        selectPreviousArticle: @escaping () -> Void = {},
        selectNextArticle: @escaping () -> Void = {}
    ) {
        self.selectedArticle = selectedArticle
        self.toggleRead = toggleRead
        self.toggleStarred = toggleStarred
        self.copyLink = copyLink
        self.openOriginal = openOriginal
        self.canSelectPreviousArticle = canSelectPreviousArticle
        self.canSelectNextArticle = canSelectNextArticle
        self.selectPreviousArticle = selectPreviousArticle
        self.selectNextArticle = selectNextArticle
    }

    var canPerformActions: Bool {
        selectedArticle != nil
    }

    var canPerformLinkActions: Bool {
        ArticleViewModel().originalURL(for: selectedArticle) != nil
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
