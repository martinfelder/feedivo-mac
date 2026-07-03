import SwiftUI

struct ArticleCommandActions {
    let canPerformActions: Bool
    let canPerformLinkActions: Bool
    let toggleReadTitle: String
    let toggleStarredTitle: String
    let toggleArchivedTitle: String
    let toggleRead: () -> Void
    let toggleStarred: () -> Void
    let toggleArchived: () -> Void
    let copyLink: () -> Void
    let openOriginal: () -> Void
    let shareOriginal: () -> Void
    let openInArticleWindow: () -> Void
    let requestExport: () -> Void
    let canSelectPreviousArticle: Bool
    let canSelectNextArticle: Bool
    let selectPreviousArticle: () -> Void
    let selectNextArticle: () -> Void

    init(
        canPerformActions: Bool,
        canPerformLinkActions: Bool,
        toggleReadTitle: String,
        toggleStarredTitle: String,
        toggleArchivedTitle: String,
        toggleRead: @escaping () -> Void,
        toggleStarred: @escaping () -> Void,
        toggleArchived: @escaping () -> Void = {},
        copyLink: @escaping () -> Void,
        openOriginal: @escaping () -> Void,
        shareOriginal: @escaping () -> Void = {},
        openInArticleWindow: @escaping () -> Void = {},
        requestExport: @escaping () -> Void = {},
        canSelectPreviousArticle: Bool = false,
        canSelectNextArticle: Bool = false,
        selectPreviousArticle: @escaping () -> Void = {},
        selectNextArticle: @escaping () -> Void = {}
    ) {
        self.canPerformActions = canPerformActions
        self.canPerformLinkActions = canPerformLinkActions
        self.toggleReadTitle = toggleReadTitle
        self.toggleStarredTitle = toggleStarredTitle
        self.toggleArchivedTitle = toggleArchivedTitle
        self.toggleRead = toggleRead
        self.toggleStarred = toggleStarred
        self.toggleArchived = toggleArchived
        self.copyLink = copyLink
        self.openOriginal = openOriginal
        self.shareOriginal = shareOriginal
        self.openInArticleWindow = openInArticleWindow
        self.requestExport = requestExport
        self.canSelectPreviousArticle = canSelectPreviousArticle
        self.canSelectNextArticle = canSelectNextArticle
        self.selectPreviousArticle = selectPreviousArticle
        self.selectNextArticle = selectNextArticle
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
