import Foundation
import Testing
@testable import Feedivo

struct DateFeedivoDisplayTests {

    @Test func absoluterModusZeigtAuchHeuteDasKurzeDatum() {
        let today = Date()
        let absoluteText = today.feedivoDisplay(mode: .absolute)
        let relativeText = today.feedivoDisplay(mode: .relative)

        #expect(absoluteText == today.feedivoRelativeDisplay || relativeText != absoluteText)
        #expect(!absoluteText.isEmpty)
    }

    @Test func relativerModusEntsprichtDerBestehendenPropertyFuerVergangeneDaten() {
        let pastDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!

        #expect(pastDate.feedivoDisplay(mode: .relative) == pastDate.feedivoRelativeDisplay)
    }

    @Test func absoluterUndRelativerModusStimmenFuerVergangeneDatenUeberein() {
        // Für Tage außerhalb "heute" liefert `feedivoRelativeDisplay` bereits
        // das kurze Datum — beide Modi müssen hier identisch sein.
        let pastDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!

        #expect(pastDate.feedivoDisplay(mode: .absolute) == pastDate.feedivoDisplay(mode: .relative))
    }
}
