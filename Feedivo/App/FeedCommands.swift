import SwiftUI

struct FeedCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    @FocusedValue(\.feedCommandActions)
    private var feedCommandActions

    @AppStorage(KeyboardShortcutOverrides.storageKey)
    private var shortcutOverridesRawValue = KeyboardShortcutOverrides().rawValue

    private var shortcutOverrides: KeyboardShortcutOverrides {
        KeyboardShortcutOverrides.resolved(from: shortcutOverridesRawValue)
    }

    var body: some Commands {
        CommandMenu(L10n.feedCommandsMenu) {
            Button(L10n.feedAddCommand) {
                feedCommandActions?.requestAddFeed()
            }
            .customizableKeyboardShortcut(.feedAdd, overrides: shortcutOverrides)
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

            Button("Verwaltung...") {
                openWindow(id: OrganizerWindowView.windowID)
            }

            Button(L10n.statisticsCommand) {
                openWindow(id: StatisticsWindowView.windowID)
            }
            .customizableKeyboardShortcut(.statisticsOpen, overrides: shortcutOverrides)

            Divider()

            Button(L10n.feedRefreshAllCommand) {
                feedCommandActions?.refreshAllFeeds()
            }
            .customizableKeyboardShortcut(.feedRefreshAll, overrides: shortcutOverrides)
            .disabled(feedCommandActions?.canRefreshAllFeeds != true)

            Button(L10n.feedRefreshCommand) {
                feedCommandActions?.refreshSelectedFeed()
            }
            .customizableKeyboardShortcut(.feedRefresh, overrides: shortcutOverrides)
            .disabled(feedCommandActions?.canPerformFeedAction != true)

            Divider()

            Button(L10n.feedDeleteCommand) {
                feedCommandActions?.requestDelete()
            }
            .disabled(feedCommandActions?.canPerformFeedAction != true)
        }
    }
}
