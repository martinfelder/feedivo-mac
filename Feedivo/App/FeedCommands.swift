import SwiftUI

struct FeedCommands: Commands {
    @FocusedValue(\.feedCommandActions)
    private var feedCommandActions

    var body: some Commands {
        CommandMenu(L10n.feedCommandsMenu) {
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
