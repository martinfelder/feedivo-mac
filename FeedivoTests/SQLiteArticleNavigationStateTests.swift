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
}
