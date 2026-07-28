import AppKit

/// Berechnet eine feste Zeilenhöhe für `ArticleRowView` ausschließlich aus
/// den app-weiten Anzeige-Einstellungen — NIE aus Artikelinhalt (Titel-
/// /Summary-Text, Datum, Feedname). Das macht jede Zeile innerhalb derselben
/// Einstellungs-Kombination exakt gleich hoch (NetNewsWire-Vergleich,
/// 2026-07-28, siehe docs/performance/netnewswire-feedivo-mechanik-vergleich.md
/// und docs/superpowers/specs/2026-07-28-artikelliste-feste-zeilenhoehe-design.md)
/// — SwiftUIs `List` muss dadurch nie pro sichtbarer Zeile Text-Layout neu
/// berechnen. Kürzere Titel/Summaries lassen dadurch bewusst Leerraum statt
/// sich eng an den Inhalt anzuschmiegen.
enum ArticleRowHeightMetrics {
    /// Zeilenzahl, die für den Titel reserviert wird — entspricht
    /// `.lineLimit(2)` in `ArticleRowView`.
    private static let titleLineCount = 2
    private static let titleFontSize: Double = 14
    private static let metadataFontSize: Double = 11
    private static let summaryFontSize: Double = 13

    /// Entspricht `.padding(.vertical, 6)` (oben UND unten) in `ArticleRowView`.
    private static let outerVerticalPadding: CGFloat = 12
    /// Entspricht dem `spacing: 6` der äußeren `VStack` in `ArticleRowView`.
    private static let interElementSpacing: CGFloat = 6
    /// Entspricht `previewImageSide` (unskaliert) in `ArticleRowView`.
    private static let unscaledImageSide: Double = 56
    /// Puffer gegen minimale Abweichungen zwischen `NSFont`- und SwiftUI-
    /// `Text`-Metriken (siehe Design-Doc, Abschnitt „Offene Punkte/Risiken").
    private static let safetyBuffer: CGFloat = 4

    static func height(
        interfaceTextSize: InterfaceTextSize,
        imagePosition: ArticleListImagePosition,
        summaryLineCount: Int
    ) -> CGFloat {
        let titleHeight = lineHeight(fontSize: titleFontSize, interfaceTextSize: interfaceTextSize) * CGFloat(titleLineCount)
        let metadataHeight = lineHeight(fontSize: metadataFontSize, interfaceTextSize: interfaceTextSize)
        let summaryHeight = summaryLineCount > 0
            ? lineHeight(fontSize: summaryFontSize, interfaceTextSize: interfaceTextSize) * CGFloat(summaryLineCount)
            : 0

        // Metadaten-Zeile + Titel sind immer sichtbar, Summary nur bei
        // summaryLineCount > 0 — bestimmt die Anzahl der Spacing-Lücken.
        let visibleElementCount = 2 + (summaryLineCount > 0 ? 1 : 0)
        let spacingTotal = interElementSpacing * CGFloat(visibleElementCount - 1)

        let textStackHeight = titleHeight + metadataHeight + summaryHeight + spacingTotal
        let imageHeight = imagePosition == .hidden ? 0 : interfaceTextSize.scaled(unscaledImageSide)
        let contentHeight = max(textStackHeight, imageHeight)

        return contentHeight + outerVerticalPadding + safetyBuffer
    }

    /// Inhaltshöhe OHNE das äußere vertikale Padding — für die rechte Spalte
    /// (Ungelesen-Punkt + Stern-Button) in `ArticleRowView`, die innerhalb
    /// des bereits gepolsterten Bereichs liegt.
    static func contentHeight(
        interfaceTextSize: InterfaceTextSize,
        imagePosition: ArticleListImagePosition,
        summaryLineCount: Int
    ) -> CGFloat {
        height(
            interfaceTextSize: interfaceTextSize,
            imagePosition: imagePosition,
            summaryLineCount: summaryLineCount
        ) - outerVerticalPadding - safetyBuffer
    }

    private static func lineHeight(fontSize: Double, interfaceTextSize: InterfaceTextSize) -> CGFloat {
        let font = NSFont.systemFont(ofSize: interfaceTextSize.scaled(fontSize))
        return NSLayoutManager().defaultLineHeight(for: font)
    }
}
