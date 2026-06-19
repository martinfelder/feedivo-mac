import SwiftUI

enum ReaderFontPreset: String, CaseIterable, Identifiable {
    case system
    case serif
    case rounded
    case monospace

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system:
            return L10n.readerFontSystem
        case .serif:
            return L10n.readerFontSerif
        case .rounded:
            return L10n.readerFontRounded
        case .monospace:
            return L10n.readerFontMonospace
        }
    }

    var design: Font.Design {
        switch self {
        case .system:
            return .default
        case .serif:
            return .serif
        case .rounded:
            return .rounded
        case .monospace:
            return .monospaced
        }
    }

    static func resolved(from rawValue: String) -> ReaderFontPreset {
        ReaderFontPreset(rawValue: rawValue) ?? .system
    }
}
