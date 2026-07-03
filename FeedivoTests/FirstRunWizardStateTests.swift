import Testing
@testable import Feedivo

struct FirstRunWizardStateTests {
    @Test func wizardWirdNurBeiLeeremFeedBestandUndOhneAbschlussAngezeigt() {
        #expect(FirstRunWizardState.shouldPresent(feedCount: 0, hasCompletedWizard: false))
        #expect(!FirstRunWizardState.shouldPresent(feedCount: 1, hasCompletedWizard: false))
    }

    @Test func wizardWirdBeiLeeremFeedBestandNachFrueheremAbschlussNichtErneutAngezeigt() {
        #expect(
            !FirstRunWizardState.shouldPresent(
                feedCount: 0,
                hasCompletedWizard: true,
                wasDismissedThisSession: false
            )
        )
    }

    @Test func wizardBleibtNachSpaeterDauerhaftAusgeblendet() {
        var hasCompletedWizard = false

        FirstRunWizardState.markCompleted(&hasCompletedWizard)

        #expect(
            !FirstRunWizardState.shouldPresent(
                feedCount: 0,
                hasCompletedWizard: hasCompletedWizard,
                wasDismissedThisSession: false
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
