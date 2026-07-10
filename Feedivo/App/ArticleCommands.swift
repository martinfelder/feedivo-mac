import SwiftUI

struct ArticleCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.articleCommandActions)
    private var articleCommandActions

    @AppStorage(KeyboardShortcutOverrides.storageKey)
    private var shortcutOverridesRawValue = KeyboardShortcutOverrides().rawValue

    private var shortcutOverrides: KeyboardShortcutOverrides {
        KeyboardShortcutOverrides.resolved(from: shortcutOverridesRawValue)
    }

    var body: some Commands {
        CommandMenu(L10n.articleCommandsMenu) {
            Button(L10n.articlePreviousCommand) {
                articleCommandActions?.selectPreviousArticle()
            }
            .customizableKeyboardShortcut(.articleSelectPrevious, overrides: shortcutOverrides)
            .disabled(articleCommandActions?.canSelectPreviousArticle != true)

            Button(L10n.articleNextCommand) {
                articleCommandActions?.selectNextArticle()
            }
            .customizableKeyboardShortcut(.articleSelectNext, overrides: shortcutOverrides)
            .disabled(articleCommandActions?.canSelectNextArticle != true)

            Divider()

            Button(L10n.articleSearchCommand) {
                openWindow(id: ArticleSearchWindowView.windowID)
            }
            .customizableKeyboardShortcut(.articleSearch, overrides: shortcutOverrides)

            Divider()

            Button(articleCommandActions?.toggleReadTitle ?? L10n.articleRowMarkRead) {
                articleCommandActions?.toggleRead()
            }
            .customizableKeyboardShortcut(.articleToggleRead, overrides: shortcutOverrides)
            .disabled(articleCommandActions?.canPerformActions != true)

            Button(articleCommandActions?.toggleStarredTitle ?? L10n.articleRowStarAdd) {
                articleCommandActions?.toggleStarred()
            }
            .customizableKeyboardShortcut(.articleToggleStarred, overrides: shortcutOverrides)
            .disabled(articleCommandActions?.canPerformActions != true)

            Button(articleCommandActions?.toggleArchivedTitle ?? L10n.articleArchiveCommand) {
                articleCommandActions?.toggleArchived()
            }
            .disabled(articleCommandActions?.canPerformActions != true)

            Divider()

            Button(L10n.articleOpenInWindowCommand) {
                articleCommandActions?.openInArticleWindow()
            }
            .customizableKeyboardShortcut(.articleOpenInWindow, overrides: shortcutOverrides)
            .disabled(articleCommandActions?.canPerformActions != true)

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
