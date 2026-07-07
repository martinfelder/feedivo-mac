import Foundation

/// Normalisierungshelfer für Tag-Namen und -Farben, weiterhin von den
/// SQLite-nativen Tag-Views genutzt (`TagManagerView`, `FeedPropertiesView`,
/// `RuleWizardView`, `TagColorPalette`).
enum TagViewModel {
    static func normalizedTagName(_ name: String?) -> String? {
        guard let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedName.isEmpty
        else {
            return nil
        }

        return trimmedName
    }

    static func normalizedColorHex(_ colorHex: String) -> String {
        let trimmed = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutHash = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard withoutHash.count == 6,
              Int(withoutHash, radix: 16) != nil
        else {
            return "#888888"
        }

        return "#\(withoutHash.uppercased())"
    }
}
