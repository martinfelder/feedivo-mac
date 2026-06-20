import SwiftUI

struct FeedCommandActions {
    let selectedFeed: Feed?
    let refreshSelectedFeed: () -> Void
    let requestDelete: () -> Void

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
