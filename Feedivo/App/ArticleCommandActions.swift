import SwiftUI

// Equatable, damit SwiftUIs `.focusedValue(...)` zwei bei jedem
// ContentView.body-Durchlauf frisch gebaute Werte auf Gleichheit prüfen kann,
// statt jeden Durchlauf als "geändert" zu publizieren — sonst SwiftUI-Warnung
// "FocusedValue update tried to update multiple times per frame" bei
// mehreren Durchläufen im selben Frame (Root-Cause-Fund 2026-07-23). Der
// Vergleich betrachtet bewusst nur die Datenfelder, nicht die Closures (nicht
// vergleichbar, aber immer stabile Rücksprünge in dieselben Methoden).
struct ArticleCommandActions: Equatable {
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

    static func == (lhs: ArticleCommandActions, rhs: ArticleCommandActions) -> Bool {
        lhs.canPerformActions == rhs.canPerformActions
            && lhs.canPerformLinkActions == rhs.canPerformLinkActions
            && lhs.toggleReadTitle == rhs.toggleReadTitle
            && lhs.toggleStarredTitle == rhs.toggleStarredTitle
            && lhs.toggleArchivedTitle == rhs.toggleArchivedTitle
            && lhs.canSelectPreviousArticle == rhs.canSelectPreviousArticle
            && lhs.canSelectNextArticle == rhs.canSelectNextArticle
    }

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
