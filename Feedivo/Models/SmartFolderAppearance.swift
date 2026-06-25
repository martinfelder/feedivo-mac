import SwiftUI

enum SmartFolderAppearance {
    static let defaultIconName = "folder.badge.gearshape"
    static let defaultColorHex = "#6B7280"

    static let iconNames = [
        "tray.full",
        "circle.fill",
        "star.fill",
        "calendar",
        "eye.slash",
        "archivebox",
        "bookmark",
        "tag",
        "folder.badge.gearshape",
        "doc.text.magnifyingglass"
    ]

    static let colorHexValues = [
        "#3B82F6",
        "#14B8A6",
        "#F59E0B",
        "#22C55E",
        "#6B7280",
        "#8B5CF6",
        "#EF4444",
        "#F97316"
    ]

    static func normalizedIconName(_ iconName: String) -> String {
        let trimmed = iconName.trimmingCharacters(in: .whitespacesAndNewlines)
        return iconNames.contains(trimmed) ? trimmed : defaultIconName
    }

    static func normalizedColorHex(_ colorHex: String) -> String {
        let trimmed = colorHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return colorHexValues.contains(trimmed) ? trimmed : defaultColorHex
    }

    static func color(for colorHex: String) -> Color {
        let normalized = normalizedColorHex(colorHex)
        let scanner = Scanner(string: normalized)
        _ = scanner.scanString("#")

        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)

        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
