import Foundation

enum FirstRunWizardState {
    static let completionStorageKey = "firstRunWizard.completed"
    static let presentationStorageKey = "firstRunWizard.hasBeenPresented"
    static let hadFeedsStorageKey = "firstRunWizard.hasHadFeeds"

    static func markCompleted(_ hasCompletedWizard: inout Bool) {
        hasCompletedWizard = true
    }

    static func markPresented(_ hasBeenPresented: inout Bool) {
        hasBeenPresented = true
    }

    static func markHadFeeds(_ hasHadFeeds: inout Bool) {
        hasHadFeeds = true
    }
}
