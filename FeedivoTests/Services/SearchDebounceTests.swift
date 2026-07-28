import Testing
@testable import Feedivo

struct SearchDebounceTests {
    @Test func waitGibtTrueZurueckWennUngestoertDurchgelaufen() async {
        let result = await SearchDebounce.wait()

        #expect(result == true)
    }

    @Test func waitGibtFalseZurueckWennTaskAbgebrochenWird() async {
        let task = Task {
            await SearchDebounce.wait()
        }
        task.cancel()

        let result = await task.value

        #expect(result == false)
    }
}
