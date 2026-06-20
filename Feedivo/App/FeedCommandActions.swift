import SwiftUI

struct FeedCommandActions {
    let selectedFeed: Feed?
    let requestAddFeed: () -> Void
    let requestImportOPML: () -> Void
    let requestExportOPML: () -> Void
    let refreshAllFeeds: () -> Void
    let refreshSelectedFeed: () -> Void
    let requestDelete: () -> Void
    let hasFeeds: Bool

    var canAddFeed: Bool {
        true
    }

    var canImportOPML: Bool {
        true
    }

    var canExportOPML: Bool {
        hasFeeds
    }

    var canRefreshAllFeeds: Bool {
        true
    }

    var canPerformFeedAction: Bool {
        selectedFeed != nil
    }
}

private struct FeedCommandActionsKey: FocusedValueKey {
    typealias Value = FeedCommandActions
}

extension FocusedValues {
    var feedCommandActions: FeedCommandActions? {
        get { self[FeedCommandActionsKey.self] }
        set { self[FeedCommandActionsKey.self] = newValue }
    }
}
