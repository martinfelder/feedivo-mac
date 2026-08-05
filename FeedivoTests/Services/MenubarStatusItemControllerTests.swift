import Testing
@testable import Feedivo

struct MenubarStatusItemControllerTests {

    @Test func symbolNameZeigtGefuellteAblageBeiUngelesenenArtikeln() {
        #expect(MenubarStatusItemController.symbolName(forUnreadCount: 1) == "tray.full")
        #expect(MenubarStatusItemController.symbolName(forUnreadCount: 42) == "tray.full")
    }

    @Test func symbolNameZeigtLeereAblageOhneUngelesenenArtikel() {
        #expect(MenubarStatusItemController.symbolName(forUnreadCount: 0) == "tray")
    }

    @Test func badgeTextZeigtZaehlerBeiUngelesenenArtikeln() {
        #expect(MenubarStatusItemController.badgeText(forUnreadCount: 1) == "1")
        #expect(MenubarStatusItemController.badgeText(forUnreadCount: 42) == "42")
    }

    @Test func badgeTextIstLeerOhneUngelesenenArtikel() {
        #expect(MenubarStatusItemController.badgeText(forUnreadCount: 0) == "")
    }

    @MainActor
    @Test func reagiertWiederholtAufStatusVersionSignal() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedViewModel = FeedViewModel()
        let controller = MenubarStatusItemController(
            feedivoDatabase: database,
            feedViewModel: feedViewModel
        )

        // Erster Bump: verifiziert nicht nur "kein Absturz", sondern auch, dass
        // `withObservationTracking`s `onChange`-Callback tatsächlich einmal feuert
        // (`statusVersionObservationFireCount` ist ein testbarer Zähler, der
        // ausschließlich zu diesem Zweck existiert — siehe Kommentar am Property
        // selbst in `MenubarStatusItemController.swift`).
        SQLiteDataInvalidation.shared.bumpStatusVersion()
        var attemptsAfterFirstBump = 0
        while controller.statusVersionObservationFireCount < 1 && attemptsAfterFirstBump < 50 {
            await Task.yield()
            attemptsAfterFirstBump += 1
        }
        #expect(controller.statusVersionObservationFireCount == 1)

        // Zweiter Bump: der eigentliche Regressionsschutz aus dem Review.
        // `withObservationTracking` beobachtet pro Aufruf nur EIN einziges Mal —
        // dieser zweite Bump beweist, dass sich die Beobachtung nach dem ersten
        // Feuern tatsächlich SELBST neu registriert hat
        // (`self?.observeStatusVersionSignal()` innerhalb von `onChange`). Würde
        // dieser Selbstaufruf versehentlich entfernt, bliebe der Zähler nach dem
        // ersten Bump für immer bei 1 stehen, unabhängig von weiteren Bumps — die
        // Menubar-Live-Aktualisierung wäre in Produktion nach dem ersten Update
        // still kaputt, während der ursprüngliche Einzel-Bump-Test dennoch grün
        // geblieben wäre.
        SQLiteDataInvalidation.shared.bumpStatusVersion()
        var attemptsAfterSecondBump = 0
        while controller.statusVersionObservationFireCount < 2 && attemptsAfterSecondBump < 50 {
            await Task.yield()
            attemptsAfterSecondBump += 1
        }
        #expect(controller.statusVersionObservationFireCount == 2)
    }
}
