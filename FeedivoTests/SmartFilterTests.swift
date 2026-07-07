import Foundation
import Testing
@testable import Feedivo

struct SmartFilterTests {

    @Test func filterIconsHabenPassendeFarben() {
        #expect(SmartFilter.allArticles.iconColor == .blue)
        #expect(SmartFilter.unread.iconColor == .teal)
        #expect(SmartFilter.starred.iconColor == .yellow)
        #expect(SmartFilter.today.iconColor == .green)
        #expect(SmartFilter.hidden.iconColor == .gray)
    }
}
