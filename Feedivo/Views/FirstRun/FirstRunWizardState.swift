import Foundation

enum FirstRunWizardState {
    static let completionStorageKey = "firstRunWizard.completed"

    static func shouldPresent(
        feedCount: Int,
        hasCompletedWizard: Bool,
        wasDismissedThisSession: Bool = false
    ) -> Bool {
        feedCount == 0 && !wasDismissedThisSession
    }

    static func markCompleted(_ hasCompletedWizard: inout Bool) {
        hasCompletedWizard = true
    }

    static func shouldKeepPresentedUntilUserStarts(
        isPresented: Bool,
        wasDismissedThisSession: Bool
    ) -> Bool {
        isPresented && !wasDismissedThisSession
    }
}
