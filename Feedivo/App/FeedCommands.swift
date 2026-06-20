import SwiftUI

struct FeedCommands: Commands {
    @FocusedValue(\.feedCommandActions)
    private var feedCommandActions

    var body: some Commands {
        CommandMenu(L10n.feedCommandsMenu) {
            Button(L10n.feedAddCommand) {
                feedCommandActions?.requestAddFeed()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(feedCommandActions?.canAddFeed != true)

            Button(L10n.feedImportOPMLCommand) {
                feedCommandActions?.requestImportOPML()
            }
            .disabled(feedCommandActions?.canImportOPML != true)

            Button(L10n.feedExportOPMLCommand) {
                feedCommandActions?.requestExportOPML()
            }
            .disabled(feedCommandActions?.canExportOPML != true)

            Divider()

            Button(L10n.feedRefreshAllCommand) {
                feedCommandActions?.refreshAllFeeds()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(feedCommandActions?.canRefreshAllFeeds != true)

            Button(L10n.feedRefreshCommand) {
                feedCommandActions?.refreshSelectedFeed()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(feedCommandActions?.canPerformFeedAction != true)

            Divider()

            Button(L10n.feedDeleteCommand) {
                feedCommandActions?.requestDelete()
            }
            .disabled(feedCommandActions?.canPerformFeedAction != true)
        }
    }
}
