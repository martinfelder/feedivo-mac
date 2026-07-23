import SwiftUI

// Equatable, damit SwiftUIs `.focusedSceneValue(...)` zwei bei jedem
// ContentView.body-Durchlauf frisch gebaute Werte auf Gleichheit prüfen kann,
// statt jeden Durchlauf als "geändert" zu publizieren — sonst SwiftUI-Warnung
// "FocusedValue update tried to update multiple times per frame" bei
// mehreren Durchläufen im selben Frame (Root-Cause-Fund 2026-07-23). Der
// Vergleich betrachtet bewusst nur die Datenfelder, nicht die Closures (nicht
// vergleichbar, aber immer stabile Rücksprünge in dieselben Methoden).
struct FeedCommandActions: Equatable {
    // ContentView resolved den ausgewählten Feed als Sidebar-Snapshot. Für die
    // Menübefehle reicht der Nil-Check (canPerformFeedAction) — die Aktionen
    // laufen auf feedID.
    let selectedFeed: FeedSidebarSnapshot?
    let requestAddFeed: () -> Void
    let requestImportOPML: () -> Void
    let requestExportOPML: () -> Void
    let refreshAllFeeds: () -> Void
    let refreshSelectedFeed: () -> Void
    let requestDelete: () -> Void
    let hasFeeds: Bool

    static func == (lhs: FeedCommandActions, rhs: FeedCommandActions) -> Bool {
        lhs.selectedFeed == rhs.selectedFeed && lhs.hasFeeds == rhs.hasFeeds
    }

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
