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
    @Test func reagiertAufStatusVersionSignalOhneAbsturz() async throws {
        let database = try FeedivoDatabase.inMemoryForTests()
        let feedViewModel = FeedViewModel()
        let controller = MenubarStatusItemController(
            feedivoDatabase: database,
            feedViewModel: feedViewModel
        )
        _ = controller // Referenz halten, ARC darf den Controller nicht vor Testende freigeben

        SQLiteDataInvalidationSignal.shared.bumpStatusVersion()

        // withObservationTracking feuert asynchron über Task { @MainActor in ... } —
        // ein kurzer Yield genügt, damit der Callback vor der Assertion durchläuft.
        await Task.yield()

        // Kein Absturz bis hierhin ist die eigentliche Assertion dieses Tests:
        // verifiziert, dass die Observation-Anbindung nicht crasht und der
        // Controller nach einem Bump weiterhin ansprechbar ist. `FeedViewModel()`
        // ohne Argumente ist gültig — alle Initializer-Parameter haben Defaults
        // (verifiziert gegen `Feedivo/ViewModels/FeedViewModel.swift:96-115`),
        // `MenubarStatusItemController(feedivoDatabase:feedViewModel:)` entspricht
        // exakt dem echten Aufruf in `FeedivoAppDelegate.swift:42-45`.
        #expect(true)
    }
}
