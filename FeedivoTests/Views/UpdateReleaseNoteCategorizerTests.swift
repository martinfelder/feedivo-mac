import Testing
@testable import Feedivo

struct UpdateReleaseNoteCategorizerTests {

    private func run(_ text: String) -> ReaderInlineRun {
        ReaderInlineRun(text: text, isBold: false, isItalic: false, linkURL: nil, colorHex: nil)
    }

    @Test func erkenntDesignPraefixUndEntferntIhnAusDemAngezeigtenText() {
        let (category, displayRuns) = UpdateReleaseNoteCategorizer.categorize([run("Design: Einheitliches Blau in der ganzen App")])

        #expect(category == .design)
        #expect(displayRuns.first?.text == "Einheitliches Blau in der ganzen App")
    }

    @Test func erkenntPraefixUnabhaengigVonGrossKleinschreibung() {
        let (category, displayRuns) = UpdateReleaseNoteCategorizer.categorize([run("FEAT: Neue Funktion")])

        #expect(category == .feature)
        #expect(displayRuns.first?.text == "Neue Funktion")
    }

    @Test func choreLandetInDerSonstigesKategorie() {
        let (category, displayRuns) = UpdateReleaseNoteCategorizer.categorize([run("chore: Xcode-Workspace-State")])

        #expect(category == .other)
        #expect(displayRuns.first?.text == "Xcode-Workspace-State")
    }

    @Test func unbekannterPraefixLandetInSonstigesOhneTextZuVeraendern() {
        let runs = [run("Whatever: Irgendetwas")]
        let (category, displayRuns) = UpdateReleaseNoteCategorizer.categorize(runs)

        #expect(category == .other)
        #expect(displayRuns.first?.text == "Whatever: Irgendetwas")
    }

    @Test func zeileOhneDoppelpunktLandetInSonstigesUnveraendert() {
        let runs = [run("Ein Satz ohne Praefix")]
        let (category, displayRuns) = UpdateReleaseNoteCategorizer.categorize(runs)

        #expect(category == .other)
        #expect(displayRuns.first?.text == "Ein Satz ohne Praefix")
    }

    @Test func entferntMehrereLeerzeichenNachDemDoppelpunkt() {
        let (_, displayRuns) = UpdateReleaseNoteCategorizer.categorize([run("Fix:   Zwei Leerzeichen")])

        #expect(displayRuns.first?.text == "Zwei Leerzeichen")
    }

    @Test func erkenntDeutschePraefixeAlsAequivalenteDerEnglischenKategorien() {
        #expect(UpdateReleaseNoteCategorizer.categorize("Neu: Etwas Neues").category == .feature)
        #expect(UpdateReleaseNoteCategorizer.categorize("Verbesserung: Etwas Besseres").category == .feature)
        #expect(UpdateReleaseNoteCategorizer.categorize("Fehlerbehebung: Ein Bug").category == .fix)
        #expect(UpdateReleaseNoteCategorizer.categorize("Cleanup: Aufgeräumt").category == .refactor)
        #expect(UpdateReleaseNoteCategorizer.categorize("Test: Neue Tests").category == .other)
    }

    @Test func stringPraefixWirdAusDemAngezeigtenTextEntfernt() {
        let (category, displayText) = UpdateReleaseNoteCategorizer.categorize("Fehlerbehebung: Ein Artikel-Link wurde überschrieben")

        #expect(category == .fix)
        #expect(displayText == "Ein Artikel-Link wurde überschrieben")
    }

    @Test func stringOhneDoppelpunktLandetInSonstigesUnveraendert() {
        let (category, displayText) = UpdateReleaseNoteCategorizer.categorize("Ein Satz ohne Praefix")

        #expect(category == .other)
        #expect(displayText == "Ein Satz ohne Praefix")
    }

    @Test func stringMitUnbekanntemPraefixLandetInSonstigesUnveraendert() {
        let (category, displayText) = UpdateReleaseNoteCategorizer.categorize("Whatever: Irgendetwas")

        #expect(category == .other)
        #expect(displayText == "Whatever: Irgendetwas")
    }
}
