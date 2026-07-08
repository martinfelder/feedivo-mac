import SwiftUI

enum TagColorPalette {
    static let defaultColorHex = "#888888"

    // Single Source of Truth: dieselbe Apple-System-Spec-Palette wie die
    // Tag-Erstellung im Regel-Dialog (RuleDialogTagSwatches).
    static let colors = RuleDialogTagSwatches.colors

    static func color(for colorHex: String?) -> Color {
        let normalized = TagViewModel.normalizedColorHex(colorHex ?? defaultColorHex)
        let hex = String(normalized.dropFirst())

        guard let value = Int(hex, radix: 16) else {
            return Color.gray
        }

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255

        return Color(red: red, green: green, blue: blue)
    }
}
