import SwiftUI

struct ArticleCommands: Commands {
    @FocusedValue(\.articleCommandActions)
    private var articleCommandActions

    var body: some Commands {
        CommandMenu(L10n.articleCommandsMenu) {
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
        }
    }
}
