import SwiftUI

struct ArticleCommands: Commands {
    @FocusedValue(\.articleCommandActions)
    private var articleCommandActions

    var body: some Commands {
        CommandMenu(L10n.articleCommandsMenu) {
            Button(L10n.articlePreviousCommand) {
                articleCommandActions?.selectPreviousArticle()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command])
            .disabled(articleCommandActions?.canSelectPreviousArticle != true)

            Button(L10n.articleNextCommand) {
                articleCommandActions?.selectNextArticle()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command])
            .disabled(articleCommandActions?.canSelectNextArticle != true)

            Divider()

            Button(articleCommandActions?.toggleReadTitle ?? L10n.articleRowMarkRead) {
                articleCommandActions?.toggleRead()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(articleCommandActions?.canPerformActions != true)

            Button(articleCommandActions?.toggleStarredTitle ?? L10n.articleRowStarAdd) {
                articleCommandActions?.toggleStarred()
            }
            .keyboardShortcut("d", modifiers: [.command])
            .disabled(articleCommandActions?.canPerformActions != true)

            Button(articleCommandActions?.toggleArchivedTitle ?? L10n.articleArchiveCommand) {
                articleCommandActions?.toggleArchived()
            }
            .disabled(articleCommandActions?.canPerformActions != true)

            Divider()

            Button(L10n.articleCopyLinkCommand) {
                articleCommandActions?.copyLink()
            }
            .disabled(articleCommandActions?.canPerformLinkActions != true)

            Button(L10n.articleOpenOriginalCommand) {
                articleCommandActions?.openOriginal()
            }
            .disabled(articleCommandActions?.canPerformLinkActions != true)

            Button(L10n.articleShareCommand) {
                articleCommandActions?.shareOriginal()
            }
            .disabled(articleCommandActions?.canPerformLinkActions != true)

            Button(L10n.articleExportCommand) {
                articleCommandActions?.requestExport()
            }
            .disabled(articleCommandActions?.canPerformActions != true)
        }
    }
}
