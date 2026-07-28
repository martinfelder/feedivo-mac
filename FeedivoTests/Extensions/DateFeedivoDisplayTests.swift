import Foundation
import Testing
@testable import Feedivo

struct DateFeedivoDisplayTests {

    @Test func absoluterModusZeigtAuchHeuteDasKurzeDatum() {
        let today = Date()
        let absoluteText = today.feedivoDisplay(mode: .absolute)

        // Baut lokal denselben kurzen DateFormatter, den auch `Date+RelativeDisplay`
        // intern (privat) verwendet — inkl. identischer Locale-Auflösung über den
        // gleichen `UserDefaults`-Key "appLanguage". So ist der Vergleich robust
        // gegenüber dem tatsächlichen UserDefaults-Zustand der Testumgebung, statt
        // von einer "sauberen" Umgebung ohne gesetzten Key auszugehen.
        let rawLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.system.rawValue
        let resolvedLocale = AppLanguage.resolved(from: rawLanguage).locale
        let referenceFormatter = DateFormatter()
        referenceFormatter.dateStyle = .short
        referenceFormatter.timeStyle = .none
        referenceFormatter.locale = resolvedLocale
        let expectedAbsoluteText = referenceFormatter.string(from: today)

        // Echte Inhaltsprüfung: `.absolute` muss für "heute" das kurze Datum liefern.
        #expect(absoluteText == expectedAbsoluteText)

        // Und explizit NICHT die relative Formulierung, die `.relative` für "heute"
        // liefern würde (z. B. "jetzt"/"vor 2 Minuten") — genau das Szenario, das der
        // Testname verspricht. Würde `.absolute` versehentlich auf
        // `feedivoRelativeDisplay` durchfallen, wären beide Texte identisch und
        // dieser Vergleich schlüge fehl.
        #expect(absoluteText != today.feedivoRelativeDisplay)
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
