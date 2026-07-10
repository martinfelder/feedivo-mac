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
}
