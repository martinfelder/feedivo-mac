import Foundation
import Testing
@testable import Feedivo

struct ArticleRowHeightMetricsTests {
    @Test func hoeheSteigtMonotonMitSummaryZeilenzahl() {
        let heights = (0...3).map {
            ArticleRowHeightMetrics.height(
                interfaceTextSize: .standard,
                imagePosition: .left,
                summaryLineCount: $0
            )
        }

        #expect(heights == heights.sorted())
        #expect(Set(heights).count == heights.count)
    }

    @Test func hoeheSkaliertMitInterfaceTextSize() {
        let small = ArticleRowHeightMetrics.height(
            interfaceTextSize: .small,
            imagePosition: .left,
            summaryLineCount: 2
        )
        let large = ArticleRowHeightMetrics.height(
            interfaceTextSize: .large,
            imagePosition: .left,
            summaryLineCount: 2
        )
        let extraLarge = ArticleRowHeightMetrics.height(
            interfaceTextSize: .extraLarge,
            imagePosition: .left,
            summaryLineCount: 2
        )

        #expect(small < large)
        #expect(large < extraLarge)
    }

    @Test func bildhoeheWirktAlsUntergrenzeBeiFehlenderSummary() {
        let height = ArticleRowHeightMetrics.height(
            interfaceTextSize: .small,
            imagePosition: .left,
            summaryLineCount: 0
        )

        // Bildhöhe (skaliert) + vertikales Padding muss mindestens erreicht
        // werden, unabhängig von den Textzeilen.
        let minimumExpected: CGFloat = InterfaceTextSize.small.scaled(CGFloat(56)) + 12

        #expect(height >= minimumExpected)
    }

    @Test func versteckesBildBeeinflusstHoeheNichtWennTextstapelOhnehinHoeherIst() {
        // Bei voller Summary-Zeilenzahl ist der Textstapel garantiert höher
        // als das 56pt-Bild — die Bildposition darf die Höhe dann nicht
        // verändern, ob sichtbar oder nicht.
        let withImage = ArticleRowHeightMetrics.height(
            interfaceTextSize: .standard,
            imagePosition: .left,
            summaryLineCount: 3
        )
        let withoutImage = ArticleRowHeightMetrics.height(
            interfaceTextSize: .standard,
            imagePosition: .hidden,
            summaryLineCount: 3
        )

        #expect(withImage == withoutImage)
    }
}
