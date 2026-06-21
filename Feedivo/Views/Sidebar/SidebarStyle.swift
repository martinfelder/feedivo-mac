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
}
