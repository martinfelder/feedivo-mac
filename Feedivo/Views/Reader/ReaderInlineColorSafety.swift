import SwiftUI

/// Entscheidet, ob eine aus Artikel-HTML übernommene Textfarbe gegen den
/// aktuellen Reader-Hintergrund ausreichend Kontrast hat. Bewusst als reine,
/// unabhängig testbare Entscheidung ausgelagert (analog zu
/// BackgroundRefreshService.isPrematureTick(...)) — die eigentliche Anwendung
/// der Farbe passiert erst beim AttributedString-Aufbau (siehe
/// ReaderInlineRun+AttributedString.swift).
enum ReaderInlineColorSafety {
    /// Referenzhelligkeit für den hellen Reader-Hintergrund (nahezu Weiß).
    static let lightBackgroundLuminance = 1.0
    /// Referenzhelligkeit für den dunklen Reader-Hintergrund (typisches
    /// macOS-Dunkelmodus-Fensterhintergrund-Grau, kein reines Schwarz).
    static let darkBackgroundLuminance = 0.12

    /// Bewusst niedrig angesetzt (kein strenges WCAG-4.5:1-Textkontrast-Maß) —
    /// die Farbe ist eine dekorative Ergänzung zur ohnehin bereits lesbaren
    /// Standard-Textfarbe, kein alleiniger Lesbarkeits-Träger.
    private static let minimumContrastRatio = 2.5

    static func isSafeColor(hex: String, againstBackgroundLuminance backgroundLuminance: Double) -> Bool {
        guard let components = rgbComponents(fromHex: hex) else {
            return false
        }

        let colorLuminance = relativeLuminance(
            red: components.red,
            green: components.green,
            blue: components.blue
        )
        let lighter = max(colorLuminance, backgroundLuminance)
        let darker = min(colorLuminance, backgroundLuminance)
        let contrastRatio = (lighter + 0.05) / (darker + 0.05)

        return contrastRatio >= minimumContrastRatio
    }

    static func color(fromHex hex: String) -> Color? {
        guard let components = rgbComponents(fromHex: hex) else {
            return nil
        }

        return Color(red: components.red, green: components.green, blue: components.blue)
    }

    private static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private static func rgbComponents(fromHex hex: String) -> (red: Double, green: Double, blue: Double)? {
        var normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("#") {
            normalized.removeFirst()
        }

        let expanded: String
        switch normalized.count {
        case 3:
            expanded = normalized.map { "\($0)\($0)" }.joined()
        case 6:
            expanded = normalized
        default:
            return nil
        }

        guard let value = Int(expanded, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return (red, green, blue)
    }
}
