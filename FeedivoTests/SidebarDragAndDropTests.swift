import Foundation
import Testing
@testable import Feedivo

struct SidebarDragAndDropTests {
    @Test func dropInsertionSideObererHaelfteIstBefore() {
        let side = DropInsertionSide.of(
            location: CGPoint(x: 10, y: 5),
            in: CGSize(width: 100, height: 30)
        )
        #expect(side == .before)
    }

    @Test func dropInsertionSideUntererHaelfteIstAfter() {
        let side = DropInsertionSide.of(
            location: CGPoint(x: 10, y: 25),
            in: CGSize(width: 100, height: 30)
        )
        #expect(side == .after)
    }

    @Test func dropInsertionSideExaktAufDerMitteIstAfter() {
        // Deterministischer Grenzfall: exakt bei der Hälfte zählt als "danach".
        let side = DropInsertionSide.of(
            location: CGPoint(x: 10, y: 15),
            in: CGSize(width: 100, height: 30)
        )
        #expect(side == .after)
    }
}
