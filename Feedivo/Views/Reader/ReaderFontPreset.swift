import SwiftUI

enum ReaderFontPreset: String, CaseIterable, Identifiable {
    case system
    case geist
    case inter
    case manrope
    case dmSans
    case literata
    case newsreader
    case ibmPlexSans
    case atkinsonHyperlegible
    case sourceSerif4
    case libreFranklin
    case lora
    case merriweather
    case notoSans
    case notoSerif
    case robotoSlab
    case crimsonPro
    case fraunces
    case serif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .geist:
            return "Geist"
        case .inter:
            return "Inter"
        case .manrope:
            return "Manrope"
        case .dmSans:
            return "DM Sans"
        case .literata:
            return "Literata"
        case .newsreader:
            return "Newsreader"
        case .ibmPlexSans:
            return "IBM Plex Sans"
        case .atkinsonHyperlegible:
            return "Atkinson Hyperlegible"
        case .sourceSerif4:
            return "Source Serif 4"
        case .libreFranklin:
            return "Libre Franklin"
        case .lora:
            return "Lora"
        case .merriweather:
            return "Merriweather"
        case .notoSans:
            return "Noto Sans"
        case .notoSerif:
            return "Noto Serif"
        case .robotoSlab:
            return "Roboto Slab"
        case .crimsonPro:
            return "Crimson Pro"
        case .fraunces:
            return "Fraunces"
        case .serif:
            return "Serif"
        }
    }

    func font(size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        switch self {
        case .system:
            return .system(size: size)
        case .serif:
            return .system(size: size, design: .serif)
        default:
            return .custom(title, size: size, relativeTo: textStyle)
        }
    }

    static func resolved(from rawValue: String) -> ReaderFontPreset {
        ReaderFontPreset(rawValue: rawValue) ?? .system
    }
}
