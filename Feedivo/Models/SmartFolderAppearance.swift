import SwiftUI

enum SmartFolderAppearance {
    static let defaultIconName = "folder.badge.gearshape"
    static let defaultColorHex = "#48484B"

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
        "#0A84FF",
        "#14B8A6",
        "#FF9F0A",
        "#30D158",
        "#48484B",
        "#BF5AF2",
        "#FF453A",
        "#FF7A00"
    ]

    static func normalizedIconName(_ iconName: String) -> String {
        let trimmed = iconName.trimmingCharacters(in: .whitespacesAndNewlines)
        return iconNames.contains(trimmed) ? trimmed : defaultIconName
    }

    // Nur Hex-Format wird geprüft, keine Zugehörigkeit zu `colorHexValues`:
    // Bestehende Ordner (u. a. die Standard-Ordner in SQLiteSmartFolderStore)
    // nutzen Farben aus einer älteren Palette, die nicht mehr Teil der
    // Picker-Optionen ist. `colorHexValues` ist nur das Angebot im Farb-
    // Picker, kein Whitelist-Filter für gespeicherte Werte (analog zu
    // `TagViewModel.normalizedColorHex`).
    static func normalizedColorHex(_ colorHex: String) -> String {
        let trimmed = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutHash = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard withoutHash.count == 6,
              Int(withoutHash, radix: 16) != nil
        else {
            return defaultColorHex
        }

        return "#\(withoutHash.uppercased())"
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
