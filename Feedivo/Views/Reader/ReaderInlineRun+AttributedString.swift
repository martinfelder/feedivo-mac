import SwiftUI

extension Array where Element == ReaderInlineRun {
    /// Baut aus den Runs eines Reader-Content-Blocks eine einzige
    /// `AttributedString` — Fett/Kursiv über `inlinePresentationIntent` (von
    /// `Text(AttributedString)` automatisch gerendert), Link über `.link`
    /// (macht den Bereich automatisch tippbar) plus durchgängiger
    /// Unterstreichung (SwiftUI `Text` unterstützt kein Hover-Tracking für
    /// einzelne Textbereiche innerhalb eines Fließtext-Absatzes, daher fest
    /// statt nur bei Mauszeiger-Hover), Farbe nur wenn
    /// `ReaderInlineColorSafety` gegen den aktuellen Farbmodus zustimmt.
    func attributedString(colorScheme: ColorScheme) -> AttributedString {
        let backgroundLuminance = colorScheme == .dark
            ? ReaderInlineColorSafety.darkBackgroundLuminance
            : ReaderInlineColorSafety.lightBackgroundLuminance

        var result = AttributedString()

        for run in self {
            var segment = AttributedString(run.text)

            var intent: InlinePresentationIntent = []
            if run.isBold {
                intent.insert(.stronglyEmphasized)
            }
            if run.isItalic {
                intent.insert(.emphasized)
            }
            if !intent.isEmpty {
                segment.inlinePresentationIntent = intent
            }

            if let linkURL = run.linkURL {
                segment.link = linkURL
                segment.underlineStyle = .single
            }

            if
                let colorHex = run.colorHex,
                ReaderInlineColorSafety.isSafeColor(hex: colorHex, againstBackgroundLuminance: backgroundLuminance),
                let color = ReaderInlineColorSafety.color(fromHex: colorHex)
            {
                segment.foregroundColor = color
            }

            result += segment
        }

        return result
    }
}
