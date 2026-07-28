import Testing
@testable import Feedivo

struct FirstRunWizardStateTests {
    @Test func wizardWirdNachImportAlsAbgeschlossenMarkiert() {
        var hasCompletedWizard = false

        FirstRunWizardState.markCompleted(&hasCompletedWizard)

        #expect(hasCompletedWizard)
    }

    @Test func wizardWirdNachEinmaligerAnzeigeAlsPraesentiertMarkiert() {
        var hasBeenPresented = false

        FirstRunWizardState.markPresented(&hasBeenPresented)

        #expect(hasBeenPresented)
    }

    @Test func wizardWirdNachSpaeterGeloeschtenFeedsAlsHadFeedsMarkiert() {
        var hasHadFeeds = false

        FirstRunWizardState.markHadFeeds(&hasHadFeeds)

        #expect(hasHadFeeds)
    }
}
