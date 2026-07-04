import Foundation

enum FirstRunWizardState {
    static let completionStorageKey = "firstRunWizard.completed"
    static let presentationStorageKey = "firstRunWizard.hasBeenPresented"
    static let hadFeedsStorageKey = "firstRunWizard.hasHadFeeds"

    static func shouldPresent(
        feedCount: Int,
        hasCompletedWizard: Bool,
        wasDismissedThisSession: Bool = false,
        hasBeenPresented: Bool = false,
        hasHadFeeds: Bool = false
    ) -> Bool {
        feedCount == 0
            && !hasCompletedWizard
            && !wasDismissedThisSession
            && !hasBeenPresented
            && !hasHadFeeds
    }

    static func markCompleted(_ hasCompletedWizard: inout Bool) {
        hasCompletedWizard = true
    }

    static func markPresented(_ hasBeenPresented: inout Bool) {
        hasBeenPresented = true
    }

    static func markHadFeeds(_ hasHadFeeds: inout Bool) {
        hasHadFeeds = true
    }

    static func shouldKeepPresentedUntilUserStarts(
        isPresented: Bool,
        wasDismissedThisSession: Bool
    ) -> Bool {
        isPresented && !wasDismissedThisSession
    }
}
