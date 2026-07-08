import SwiftUI

// Exakte Farb-Tokens aus RuleDialogCards.dc.html (Konzept A). Keine Werte
// aus dem System-Farbschema — der Dialog hat ein eigenes, festes Farbsystem
// für Light/Dark, das 1:1 dem Referenz-Prototyp entspricht.
struct RuleDialogTheme {
    let bg: Color
    let card: Color
    let card2: Color
    let text: Color
    let text2: Color
    let border: Color
    let accent: Color
    let track: Color
    let pill: Color
    let input: Color

    static let switchOn = Color(hex: 0x34C759)
    static let thenBadgeText = Color(hex: 0x2FA84F)

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            bg = Color(hex: 0x28282B)
            card = Color(hex: 0x323235)
            card2 = Color(hex: 0x3A3A3D)
            text = Color(hex: 0xF5F5F7)
            text2 = Color(hex: 0x9A9AA0)
            border = Color.white.opacity(0.12)
            accent = Color(hex: 0x0A84FF)
            track = Color(hex: 0x48484B)
            pill = Color(hex: 0x6A6A6E)
            input = Color(hex: 0x1F1F22)
        } else {
            bg = Color(hex: 0xFFFFFF)
            card = Color(hex: 0xF5F5F7)
            card2 = Color(hex: 0xFFFFFF)
            text = Color(hex: 0x1D1D1F)
            text2 = Color(hex: 0x86868B)
            border = Color.black.opacity(0.10)
            accent = Color(hex: 0x0A84FF)
            track = Color(hex: 0xE9E9EB)
            pill = Color(hex: 0xFFFFFF)
            input = Color(hex: 0xFFFFFF)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
