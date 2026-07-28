import Testing
@testable import Feedivo

struct ReaderToolbarItemTests {
    @Test func allCasesHatVierzehnEindeutigeItems() {
        let rawValues = ReaderToolbarItem.allCases.map(\.rawValue)

        #expect(ReaderToolbarItem.allCases.count == 14)
        #expect(Set(rawValues).count == 14)
    }

    @Test func idEntsprichtRawValue() {
        for item in ReaderToolbarItem.allCases {
            #expect(item.id == item.rawValue)
        }
    }

    @Test func systemImageIstFuerJedesItemGesetzt() {
        for item in ReaderToolbarItem.allCases {
            #expect(item.systemImage.isEmpty == false)
        }
    }

    @Test func deklarationsreihenfolgeEntsprichtHeutigerStandardToolbarReihenfolge() {
        let expectedOrder: [ReaderToolbarItem] = [
            .search, .openOriginal, .createRule, .star, .archive, .toggleRead,
            .copyLink, .export, .webBack, .webForward, .print,
            .displayModePicker, .appearance, .inspector
        ]

        #expect(ReaderToolbarItem.allCases == expectedOrder)
    }
}
