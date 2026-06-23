import Testing
@testable import Feedivo

struct FirstRunWizardStateTests {
    @Test func wizardWirdNurBeiLeeremFeedBestandUndOhneAbschlussAngezeigt() {
        #expect(FirstRunWizardState.shouldPresent(feedCount: 0, hasCompletedWizard: false))
        #expect(!FirstRunWizardState.shouldPresent(feedCount: 1, hasCompletedWizard: false))
    }

    @Test func wizardWirdBeiLeeremFeedBestandAuchNachFrueheremAbschlussAngezeigt() {
        #expect(
            FirstRunWizardState.shouldPresent(
                feedCount: 0,
                hasCompletedWizard: true,
                wasDismissedThisSession: false
            )
        )
    }

    @Test func wizardBleibtNachSpaeterNurInAktuellerSitzungAusgeblendet() {
        #expect(
            !FirstRunWizardState.shouldPresent(
                feedCount: 0,
                hasCompletedWizard: true,
                wasDismissedThisSession: true
            )
        )
    }

    @Test func wizardWirdNachImportAlsAbgeschlossenMarkiert() {
        var hasCompletedWizard = false

        FirstRunWizardState.markCompleted(&hasCompletedWizard)

        #expect(hasCompletedWizard)
    }

    @Test func sichtbarerWizardBleibtNachImportOffenBisAktivGestartetWird() {
        #expect(
            FirstRunWizardState.shouldKeepPresentedUntilUserStarts(
                isPresented: true,
                wasDismissedThisSession: false
            )
        )
        #expect(
            !FirstRunWizardState.shouldKeepPresentedUntilUserStarts(
                isPresented: true,
                wasDismissedThisSession: true
            )
        )
    }
}
