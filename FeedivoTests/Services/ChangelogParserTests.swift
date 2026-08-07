import Testing
@testable import Feedivo

struct ChangelogParserTests {

    @Test func parstMehrereVersionsBloeckeMitVersionUndDatum() {
        let markdown = """
        # Changelog

        Einleitungstext, der ignoriert werden soll.

        <!-- versions -->

        ## [1.0 (28)] - 2026-08-07

        - Neu: Erster Punkt
        - Fehlerbehebung: Zweiter Punkt

        ## [1.0 (27)] - 2026-08-05

        - Verbesserung: Dritter Punkt
        """

        let entries = ChangelogParser.parse(markdown)

        #expect(entries.count == 2)
        #expect(entries[0].version == "1.0 (28)")
        #expect(entries[0].date == "2026-08-07")
        #expect(entries[0].bullets == ["Neu: Erster Punkt", "Fehlerbehebung: Zweiter Punkt"])
        #expect(entries[1].version == "1.0 (27)")
        #expect(entries[1].date == "2026-08-05")
        #expect(entries[1].bullets == ["Verbesserung: Dritter Punkt"])
    }

    @Test func fuegtMehrzeiligUmgebrocheneBulletsWiederZusammen() {
        let markdown = """
        <!-- versions -->

        ## [1.0 (1)] - 2026-01-01

        - Neu: Ein langer Satz, der über
          mehrere Zeilen
          umgebrochen wurde
        - Kurzer zweiter Punkt
        """

        let entries = ChangelogParser.parse(markdown)

        #expect(entries.count == 1)
        #expect(entries[0].bullets == [
            "Neu: Ein langer Satz, der über mehrere Zeilen umgebrochen wurde",
            "Kurzer zweiter Punkt"
        ])
    }

    @Test func ignoriertPreambelTextVorDerErstenUeberschrift() {
        let markdown = """
        # Changelog

        Alle nennenswerten Änderungen werden hier dokumentiert.
        Ein zweiter Absatz ohne Bullet-Punkte.

        <!-- versions -->

        ## [2.0] - 2026-01-01

        - Einziger Punkt
        """

        let entries = ChangelogParser.parse(markdown)

        #expect(entries.count == 1)
        #expect(entries[0].bullets == ["Einziger Punkt"])
    }

    @Test func leererTextLiefertLeeresArray() {
        #expect(ChangelogParser.parse("").isEmpty)
    }

    @Test func versionOhneBulletsLiefertLeereBulletliste() {
        let markdown = """
        <!-- versions -->

        ## [1.0] - 2026-01-01

        ## [0.9] - 2025-12-01

        - Ein Punkt
        """

        let entries = ChangelogParser.parse(markdown)

        #expect(entries.count == 2)
        #expect(entries[0].bullets.isEmpty)
        #expect(entries[1].bullets == ["Ein Punkt"])
    }

    @Test func ueberschriftOhneDatumsangabeWirdIgnoriert() {
        let markdown = """
        <!-- versions -->

        ## [Kaputte Überschrift ohne Datum]

        - Dieser Punkt gehört zu keiner erkannten Version
        """

        let entries = ChangelogParser.parse(markdown)

        #expect(entries.isEmpty)
    }

    @Test func reihenfolgeDerQuelldateiBleibtErhalten() {
        let markdown = """
        <!-- versions -->

        ## [3] - 2026-03-01

        - C

        ## [2] - 2026-02-01

        - B

        ## [1] - 2026-01-01

        - A
        """

        let entries = ChangelogParser.parse(markdown)

        #expect(entries.map(\.version) == ["3", "2", "1"])
    }
}
