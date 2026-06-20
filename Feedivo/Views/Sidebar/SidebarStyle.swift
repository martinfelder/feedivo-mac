import SwiftUI

enum SidebarStyle {
    static let darkPrimaryTextOpacity = 0.96
    static let darkSecondaryTextOpacity = 0.54
    static let darkIconOpacity = 1.0
    static let darkActiveSelectionOpacity = 0.11
    static let darkActiveBorderOpacity = 0.07

    static let darkBackground = Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255)
    static let darkPrimaryText = Color.white.opacity(darkPrimaryTextOpacity)
    static let darkSecondaryText = Color.white.opacity(darkSecondaryTextOpacity)
    static let darkSectionText = Color.white.opacity(0.42)
    static let darkRowHover = Color.white.opacity(0.08)
    static let darkActiveSelection = Color.white.opacity(darkActiveSelectionOpacity)
    static let darkActiveBorder = Color.white.opacity(darkActiveBorderOpacity)
    static let darkSeparator = Color.white.opacity(0.07)
}
