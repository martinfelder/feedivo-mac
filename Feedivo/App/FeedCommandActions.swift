import SwiftUI

struct FeedCommandActions {
    let selectedFeed: Feed?
    let requestAddFeed: () -> Void
    let refreshAllFeeds: () -> Void
    let refreshSelectedFeed: () -> Void
    let requestDelete: () -> Void

    var canAddFeed: Bool {
        true
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
