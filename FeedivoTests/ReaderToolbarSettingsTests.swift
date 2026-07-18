import Testing
@testable import Feedivo

struct ReaderToolbarSettingsTests {
    @Test func defaultLayoutEnthaeltAlleItemsSichtbarInDeklarationsreihenfolge() {
        let layout = ReaderToolbarLayout()

        #expect(layout.orderedItems == ReaderToolbarItem.allCases)
        #expect(layout.visibleOrderedItems == ReaderToolbarItem.allCases)
        #expect(layout.hiddenItemIDs.isEmpty)
    }

    @Test func rawValueRundtripErhaeltReihenfolgeUndSichtbarkeit() {
        var layout = ReaderToolbarLayout()
        layout.move(fromOffsets: [3], toOffset: 0)
        layout.setHidden(true, for: .print)

        let restored = ReaderToolbarLayout.resolved(from: layout.rawValue)

        #expect(restored.order == layout.order)
        #expect(restored.hiddenItemIDs == layout.hiddenItemIDs)
    }

    @Test func resolvedLiefertDefaultBeiUngueltigemJSON() {
        let layout = ReaderToolbarLayout.resolved(from: "das ist kein JSON")

        #expect(layout == ReaderToolbarLayout())
    }

    @Test func setHiddenBlendetItemAusSichtbarerListeAusBleibtAberInOrderedItems() {
        var layout = ReaderToolbarLayout()
        layout.setHidden(true, for: .star)

        #expect(layout.visibleOrderedItems.contains(.star) == false)
        #expect(layout.orderedItems.contains(.star) == true)

        layout.setHidden(false, for: .star)
        #expect(layout.visibleOrderedItems.contains(.star) == true)
    }

    @Test func resolvedHaengtFehlendesItemSichtbarAnsEndeAn() {
        let allButInspector = ReaderToolbarItem.allCases
            .map(\.rawValue)
            .filter { $0 != ReaderToolbarItem.inspector.rawValue }
        let rawValue = "{\"order\":\(jsonArray(allButInspector)),\"hidden\":[]}"

        let layout = ReaderToolbarLayout.resolved(from: rawValue)

        #expect(layout.order.last == ReaderToolbarItem.inspector.rawValue)
        #expect(layout.visibleOrderedItems.contains(.inspector) == true)
    }

    @Test func resolvedEntferntUnbekannteVeralteteEintraege() {
        let rawValue = "{\"order\":[\"obsoleteItem\",\"search\"],\"hidden\":[]}"

        let layout = ReaderToolbarLayout.resolved(from: rawValue)

        #expect(layout.order.contains("obsoleteItem") == false)
        #expect(layout.orderedItems.count == ReaderToolbarItem.allCases.count)
    }

    @Test func resetToDefaultSetztAufAuslieferungszustandZurueck() {
        var layout = ReaderToolbarLayout()
        layout.setHidden(true, for: .print)
        layout.move(fromOffsets: [0], toOffset: 5)

        let reset = ReaderToolbarLayout.resetToDefault()

        #expect(reset == ReaderToolbarLayout())
    }

    private func jsonArray(_ values: [String]) -> String {
        "[" + values.map { "\"\($0)\"" }.joined(separator: ",") + "]"
    }
}
