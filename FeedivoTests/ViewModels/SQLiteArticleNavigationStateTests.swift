import Testing
@testable import Feedivo

struct SQLiteArticleNavigationStateTests {
    @Test func navigationBerechnetNachbarnAusSQLiteIDs() {
        let state = SQLiteArticleNavigationState(
            articleIDs: ["a", "b", "c"],
            selectedArticleID: "b"
        )

        #expect(state.previousArticleID == "a")
        #expect(state.nextArticleID == "c")
    }

    @Test func navigationBleibtLeerWennAuswahlNichtSichtbarIst() {
        let state = SQLiteArticleNavigationState(
            articleIDs: ["a", "b", "c"],
            selectedArticleID: "x"
        )

        #expect(state == .empty)
    }

    /// Dokumentiert eine bewusst in Kauf genommene Mehrdeutigkeit: ein Feed mit
    /// genau einem (sichtbaren) Artikel liefert einen wertgleich zu `.empty`
    /// geladenen Zustand (kein Vorgänger, kein Nachfolger) - ununterscheidbar von
    /// "noch nicht geladen". `ContentView.swift`s automatischer Feed-Sprung darf
    /// sich deshalb NICHT allein auf `sqliteArticleNavigationState != .empty`
    /// verlassen, um seine Sprung-Sperre freizugeben (siehe Kommentar bei
    /// `isJumpingToFeedWithUnread` dort) - sonst bleibt die Sperre nach einem
    /// Sprung auf einen Ein-Artikel-Feed dauerhaft hängen.
    @Test func navigationIstWertgleichZuEmptyBeiGenauEinemArtikel() {
        let state = SQLiteArticleNavigationState(
            articleIDs: ["nur-dieser"],
            selectedArticleID: "nur-dieser"
        )

        #expect(state == .empty)
    }
}
