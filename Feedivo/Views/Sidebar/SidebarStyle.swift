import SwiftUI

enum SidebarStyle {
    static let primaryTextOpacity = 0.92
    static let secondaryTextOpacity = 0.62
    static let iconOpacity = 1.0
    static let activeSelectionOpacity = 0.14
    static let activeBorderOpacity = 0.12

    static let background = Color(nsColor: .controlBackgroundColor)
    static let primaryText = Color.primary.opacity(primaryTextOpacity)
    static let secondaryText = Color.secondary.opacity(secondaryTextOpacity)
    static let sectionText = Color.secondary.opacity(0.72)
    static let rowHover = Color.primary.opacity(0.06)
    static let activeSelection = Color.accentColor.opacity(activeSelectionOpacity)
    static let activeBorder = Color.accentColor.opacity(activeBorderOpacity)
    static let separator = Color.primary.opacity(0.08)

    // Graue Zähler-Pille (z. B. Gesamtanzahl bei "Alle Artikel", "Mit Stern",
    // "Heute") - heller Rahmen statt blauem Tint, damit sie sich klar vom
    // blauen Ungelesen-Badge abhebt.
    static let secondaryBadgeFill = Color.gray.opacity(0.10)
    static let secondaryBadgeBorder = Color.gray.opacity(0.45)
}
